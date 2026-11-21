import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_prefs.dart';

/// Monthly **mobile-data** budget ("ميزانية البيانات").
///
/// The app's own traffic is sampled every 15 s from Android's per-app
/// counters (TrafficStats); a sample's delta is billed to the month only
/// while the active network is cellular. As usage approaches the budget
/// the app degrades gracefully:
///  * ≥ 80 %  → low-data mode (lowest video quality, data-saver manga);
///  * ≥ 100 % → playback asks before using mobile data, downloads wait for
///    Wi-Fi.
class DataBudget extends ChangeNotifier {
  DataBudget._();
  static final DataBudget I = DataBudget._();

  static const MethodChannel _ch = MethodChannel('animax/app');
  static const String _prefKey = 'dataBudget.state';

  String _month = '';
  int usedBytes = 0;
  int _lastTotal = -1;
  bool _cellular = false;
  Timer? _timer;
  SharedPreferences? _sp;

  /// User accepted going over the budget for this app session.
  bool overrideThisSession = false;

  int get budgetMb => AppPrefs.I.dataBudgetMb;
  bool get enabled => budgetMb > 0;
  double get usedMb => usedBytes / (1024 * 1024);
  double get fraction => enabled ? usedMb / budgetMb : 0;

  bool get nearLimit => enabled && fraction >= 0.8;
  bool get over => enabled && fraction >= 1;

  /// Currently on mobile data (last sample).
  bool get onCellular => _cellular;

  static String monthOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> start() async {
    try {
      _sp = await SharedPreferences.getInstance();
      final String? raw = _sp!.getString(_prefKey);
      if (raw != null) {
        final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
        _month = (j['month'] ?? '').toString();
        usedBytes = (j['used'] as num?)?.toInt() ?? 0;
        _lastTotal = (j['last'] as num?)?.toInt() ?? -1;
      }
    } catch (_) {}
    await sample();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => sample());
  }

  /// Pure accounting step (unit-tested): returns the new state after the
  /// app's cumulative traffic counter reads [total] on [network].
  static ({String month, int used, int last}) account({
    required String month,
    required int used,
    required int last,
    required int total,
    required bool cellular,
    required DateTime now,
  }) {
    final String m = monthOf(now);
    if (m != month) used = 0; // new month → fresh budget
    if (total >= 0) {
      // Counter resets on reboot: the whole new value is new traffic.
      final int delta = last < 0 ? 0 : (total >= last ? total - last : total);
      if (cellular && delta > 0) used += delta;
      last = total;
    }
    return (month: m, used: used, last: last);
  }

  Future<void> sample() async {
    int total = -1;
    String net = '';
    try {
      total = await _ch.invokeMethod<int>('trafficBytes') ?? -1;
      net = await _ch.invokeMethod<String>('networkType') ?? '';
    } catch (_) {
      return; // not Android / channel unavailable
    }
    final bool wasNear = nearLimit, wasOver = over;
    _cellular = net == 'cellular';
    final ({String month, int used, int last}) r = account(
      month: _month,
      used: usedBytes,
      last: _lastTotal,
      total: total,
      cellular: _cellular,
      now: DateTime.now(),
    );
    _month = r.month;
    usedBytes = r.used;
    _lastTotal = r.last;
    unawaited(
      _sp?.setString(
        _prefKey,
        jsonEncode(<String, dynamic>{
          'month': _month,
          'used': usedBytes,
          'last': _lastTotal,
        }),
      ),
    );
    if (wasNear != nearLimit || wasOver != over || enabled) notifyListeners();
  }

  void resetMonth() {
    usedBytes = 0;
    overrideThisSession = false;
    unawaited(
      _sp?.setString(
        _prefKey,
        jsonEncode(<String, dynamic>{
          'month': _month,
          'used': 0,
          'last': _lastTotal,
        }),
      ),
    );
    notifyListeners();
  }

  /// Gate before starting a stream. Returns false when the user chose not
  /// to spend mobile data past the budget.
  Future<bool> allowStreaming(BuildContext context) async {
    if (!over || !_cellular || overrideThisSession) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تجاوزت ميزانية البيانات'),
          content: Text(
            'استهلكت ${usedMb.toStringAsFixed(0)} م.ب من ميزانيتك الشهرية ($budgetMb م.ب) على بيانات الجوال.\n'
            'يمكنك الانتظار حتى تتصل بشبكة Wi-Fi أو المتابعة على أي حال.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انتظار Wi-Fi'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة على أي حال'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) overrideThisSession = true;
    return ok == true;
  }

  static String fmtMb(double mb) => mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(2)} ج.ب'
      : '${mb.toStringAsFixed(0)} م.ب';
}
