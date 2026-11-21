import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_prefs.dart';
import 'cloud.dart';
import 'library_store.dart';

/// Keeps My List, watch progress and history in your account
/// (`sync/{uid}`, private): sign in on another phone and everything —
/// "continue watching", resume points, watched marks — is there.
///
/// On sign-in (and app start) the cloud copy is merged in (newest change
/// per item wins), then the merged result is uploaded. Local changes are
/// uploaded 15 s after they settle.
class CloudSync extends ChangeNotifier {
  CloudSync._();
  static final CloudSync I = CloudSync._();

  DateTime? lastSync;
  bool busy = false;
  String error = '';
  String _uid = '';
  Timer? _debounce;
  bool _applying = false;
  bool _started = false;

  bool get enabled => AppPrefs.I.cloudSync;

  void start() {
    if (_started) return;
    _started = true;
    CloudAuth.I.addListener(_onAuth);
    LibraryStore.I.addListener(_onLocalChange);
    _onAuth();
  }

  void _onAuth() {
    final String uid = CloudAuth.I.user?.uid ?? '';
    if (uid == _uid) return;
    _uid = uid;
    if (uid.isNotEmpty && enabled) unawaited(syncNow());
  }

  void _onLocalChange() {
    if (_applying || _uid.isEmpty || !enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 15), () => unawaited(push()));
  }

  Future<void>? _inflight;

  /// Pull + merge + push (concurrent callers share the run in flight).
  Future<void> syncNow() =>
      _inflight ??= _sync().whenComplete(() => _inflight = null);

  Future<void> _sync() async {
    if (_uid.isEmpty) return;
    busy = true;
    error = '';
    notifyListeners();
    try {
      final dynamic remote = await CloudDb.I.get('sync/$_uid');
      if (remote is Map && remote['data'] is String) {
        final Object? data = jsonDecode(remote['data'] as String);
        if (data is Map) {
          _applying = true;
          try {
            LibraryStore.I.mergeJson(Map<String, dynamic>.from(data));
          } finally {
            _applying = false;
          }
        }
      }
      await _upload();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Uploads the local library now.
  Future<void> push() async {
    if (_uid.isEmpty || !enabled) return;
    try {
      await _upload();
      error = '';
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> _upload() async {
    final String data = jsonEncode(LibraryStore.I.exportJson());
    await CloudDb.I.put('sync/$_uid', <String, dynamic>{
      'data': data,
      'at': serverTime,
    });
    lastSync = DateTime.now();
  }
}
