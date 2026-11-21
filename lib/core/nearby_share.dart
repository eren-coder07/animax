import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cloud.dart';
import 'download_manager.dart';

enum NearbyPhase { idle, waiting, confirm, connecting, transferring, done, error }

class NearbyPeer {
  const NearbyPeer(this.id, this.name);
  final String id;
  final String name;
}

/// Offline phone-to-phone transfer ("أرسل لجهاز قريب") over Google Nearby
/// Connections — Bluetooth + Wi-Fi Direct, no internet required.
///
/// Sender: [send] advertises the file. Receiver: [receive] lists nearby
/// senders; [connect] to one. Both phones then show the same 4-digit
/// [code] and must [accept]. The received file lands in
/// `Download/Animax/…` and is added to the Downloads list.
class NearbyShare extends ChangeNotifier {
  NearbyShare._() {
    _ch.setMethodCallHandler(_onEvent);
  }
  static final NearbyShare I = NearbyShare._();

  static const MethodChannel _ch = MethodChannel('animax/nearby');

  NearbyPhase phase = NearbyPhase.idle;
  bool sending = false;
  final List<NearbyPeer> peers = <NearbyPeer>[];

  /// Pending connection awaiting confirmation.
  String pendingId = '';
  String pendingName = '';
  String code = '';

  int bytes = 0;
  int total = 0;
  String message = '';
  String fileTitle = '';
  DownloadItem? received;

  double get fraction => total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0;

  String get _myName {
    final String n = CloudAuth.I.user?.name ?? '';
    return n.isEmpty ? 'مستخدم أنيماكس' : n;
  }

  void _set(NearbyPhase p, {String msg = ''}) {
    phase = p;
    message = msg;
    notifyListeners();
  }

  void _reset() {
    peers.clear();
    pendingId = '';
    pendingName = '';
    code = '';
    bytes = 0;
    total = 0;
    message = '';
    received = null;
  }

  Future<bool> _permissions() async {
    try {
      final bool ok = await _ch.invokeMethod<bool>('permissions') ?? false;
      if (!ok) {
        _set(NearbyPhase.error,
            msg: 'يلزم السماح بأذونات «الأجهزة القريبة» (والموقع في الإصدارات الأقدم) للإرسال بدون إنترنت.');
      }
      return ok;
    } on MissingPluginException {
      _set(NearbyPhase.error, msg: 'الإرسال للأجهزة القريبة متاح على أندرويد فقط.');
      return false;
    } catch (e) {
      _set(NearbyPhase.error, msg: e.toString());
      return false;
    }
  }

  /// Starts offering [item] (a finished download) to a nearby phone.
  Future<void> send(DownloadItem item) async {
    await stop();
    _reset();
    sending = true;
    fileTitle = item.title;
    if (item.resultUri.isEmpty) {
      _set(NearbyPhase.error, msg: 'الملف غير متاح على الجهاز.');
      return;
    }
    if (!await _permissions()) return;
    try {
      final String ext = item.mime == 'application/pdf'
          ? 'pdf'
          : item.mime.startsWith('image/')
              ? 'png'
              : 'mp4';
      await _ch.invokeMethod<bool>('send', <String, dynamic>{
        'name': '$_myName · ${item.title}',
        'uri': item.resultUri,
        'meta': <String, dynamic>{
          'title': item.title,
          'subtitle': item.subtitle,
          'poster': item.poster,
          'mime': item.mime.isEmpty ? 'video/mp4' : item.mime,
          'name': '${item.fileBase}.$ext',
          'size': item.received > 0 ? item.received : item.total,
          'kind': item.kind.name,
        },
      });
      _set(NearbyPhase.waiting,
          msg: 'بانتظار جهاز قريب… اطلب من صديقك فتح أنيماكس ← التحميلات ← «استلام من جهاز قريب».');
    } on PlatformException catch (e) {
      _set(NearbyPhase.error, msg: e.message ?? e.code);
    }
  }

  /// Looks for nearby phones that are sending.
  Future<void> receive() async {
    await stop();
    _reset();
    sending = false;
    if (!await _permissions()) return;
    try {
      await _ch.invokeMethod<bool>('receive');
      _set(NearbyPhase.waiting, msg: 'جارٍ البحث عن أجهزة قريبة ترسل ملفًا…');
    } on PlatformException catch (e) {
      _set(NearbyPhase.error, msg: e.message ?? e.code);
    }
  }

  Future<void> connect(NearbyPeer p) async {
    try {
      _set(NearbyPhase.connecting, msg: 'جارٍ الاتصال بـ ${p.name}…');
      await _ch.invokeMethod<bool>('connect', <String, dynamic>{'name': _myName, 'id': p.id});
    } on PlatformException catch (e) {
      _set(NearbyPhase.error, msg: e.message ?? e.code);
    }
  }

  Future<void> accept() async {
    try {
      _set(NearbyPhase.connecting, msg: 'بانتظار موافقة الجهاز الآخر…');
      await _ch.invokeMethod<bool>('accept', <String, dynamic>{'id': pendingId});
    } on PlatformException catch (e) {
      _set(NearbyPhase.error, msg: e.message ?? e.code);
    }
  }

  Future<void> reject() async {
    try {
      await _ch.invokeMethod<bool>('reject', <String, dynamic>{'id': pendingId});
    } catch (_) {}
    pendingId = '';
    _set(NearbyPhase.waiting, msg: 'تم الرفض. ما زال البحث مستمرًا…');
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod<bool>('stop');
    } catch (_) {}
    if (phase != NearbyPhase.idle) {
      phase = NearbyPhase.idle;
      notifyListeners();
    }
  }

  Future<dynamic> _onEvent(MethodCall call) async {
    final Map<dynamic, dynamic> a =
        (call.arguments as Map<dynamic, dynamic>?) ?? const <dynamic, dynamic>{};
    switch (call.method) {
      case 'found':
        final String id = (a['id'] ?? '').toString();
        if (!peers.any((NearbyPeer p) => p.id == id)) {
          peers.add(NearbyPeer(id, (a['name'] ?? '').toString()));
          notifyListeners();
        }
      case 'lost':
        peers.removeWhere((NearbyPeer p) => p.id == (a['id'] ?? '').toString());
        notifyListeners();
      case 'auth':
        pendingId = (a['id'] ?? '').toString();
        pendingName = (a['name'] ?? '').toString();
        code = (a['code'] ?? '').toString();
        _set(NearbyPhase.confirm);
      case 'connected':
        _set(NearbyPhase.transferring,
            msg: sending ? 'جارٍ الإرسال…' : 'جارٍ الاستلام…');
      case 'meta':
        fileTitle = (a['title'] ?? '').toString();
        total = (a['size'] as num?)?.toInt() ?? total;
        notifyListeners();
      case 'progress':
        bytes = (a['bytes'] as num?)?.toInt() ?? bytes;
        total = (a['total'] as num?)?.toInt() ?? total;
        if (phase != NearbyPhase.transferring) phase = NearbyPhase.transferring;
        notifyListeners();
      case 'sent':
        bytes = total;
        _set(NearbyPhase.done, msg: 'تم إرسال «$fileTitle» بنجاح ✅');
        final String doneMsg = message;
        // Let the receiver finish saving before tearing the link down.
        unawaited(Future<void>.delayed(const Duration(seconds: 4))
            .then((_) => stop())
            .then((_) => _set(NearbyPhase.done, msg: doneMsg)));
      case 'received':
        received = await DownloadManager.I.addReceivedFile(
          title: (a['title'] ?? 'ملف مستلم').toString(),
          subtitle: (a['subtitle'] ?? '').toString(),
          poster: (a['poster'] ?? '').toString(),
          uri: (a['uri'] ?? '').toString(),
          location: (a['location'] ?? '').toString(),
          mime: (a['mime'] ?? 'video/mp4').toString(),
          size: (a['size'] as num?)?.toInt() ?? 0,
        );
        bytes = total;
        _set(NearbyPhase.done, msg: 'تم استلام «$fileTitle» وحُفظ في التحميلات ✅');
        final String doneMsg = message;
        unawaited(stop().then((_) => _set(NearbyPhase.done, msg: doneMsg)));
      case 'error':
        _set(NearbyPhase.error, msg: (a['message'] ?? 'حدث خطأ').toString());
      case 'disconnected':
        if (phase == NearbyPhase.transferring) {
          _set(NearbyPhase.error, msg: 'انقطع الاتصال قبل اكتمال النقل.');
        }
    }
    return null;
  }
}
