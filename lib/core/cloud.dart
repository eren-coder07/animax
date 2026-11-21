import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http.dart';

/// Firebase project (from google-services.json), used over Firebase's REST
/// APIs: Identity Toolkit (email + password auth), Realtime Database and
/// Cloud Storage. REST keeps it working regardless of the Android package
/// name and on Windows too.
class FirebaseConfig {
  FirebaseConfig._();
  static const String apiKey = 'AIzaSyAhIYxujLn5O3TCesaHI_10LuOdbDgvnv8';
  static const String dbUrl =
      'https://cimacloud-22762-default-rtdb.firebaseio.com';
  static const String bucket = 'cimacloud-22762.appspot.com';

  /// All Animax data lives under this node (the project also hosts other
  /// apps' data — never touched).
  static const String root = 'animax';
}

class CloudException implements Exception {
  CloudException(this.message, {this.code = ''});
  final String message;
  final String code;
  @override
  String toString() => message;
}

/// Signed-in account.
class CloudUser {
  const CloudUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String email;
  final String name;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  CloudUser copyWith({String? name, String? idToken, String? refreshToken, DateTime? expiresAt}) =>
      CloudUser(
        uid: uid,
        email: email,
        name: name ?? this.name,
        idToken: idToken ?? this.idToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'email': email,
        'name': name,
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static CloudUser? fromJson(Map<String, dynamic> j) {
    final String uid = (j['uid'] ?? '').toString();
    if (uid.isEmpty) return null;
    return CloudUser(
      uid: uid,
      email: (j['email'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      idToken: (j['idToken'] ?? '').toString(),
      refreshToken: (j['refreshToken'] ?? '').toString(),
      expiresAt: DateTime.tryParse((j['expiresAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Email + password authentication with a persisted, auto-refreshed session.
class CloudAuth extends ChangeNotifier {
  CloudAuth._();
  static final CloudAuth I = CloudAuth._();

  static const String _prefKey = 'cloud.session';
  final http.Client _http = createHttpClient();

  CloudUser? _user;
  CloudUser? get user => _user;
  bool get signedIn => _user != null;

  Future<void> restore() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_prefKey);
      if (raw == null) return;
      _user = CloudUser.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      notifyListeners();
      if (_user != null) await freshToken(); // validates the session
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      if (_user == null) {
        await sp.remove(_prefKey);
      } else {
        await sp.setString(_prefKey, jsonEncode(_user!.toJson()));
      }
    } catch (_) {}
  }

  static String _arabic(String code) {
    if (code.startsWith('EMAIL_EXISTS')) return 'هذا البريد مسجّل بالفعل — سجّل الدخول.';
    if (code.startsWith('INVALID_LOGIN_CREDENTIALS') ||
        code.startsWith('INVALID_PASSWORD') ||
        code.startsWith('EMAIL_NOT_FOUND')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    }
    if (code.startsWith('WEAK_PASSWORD')) return 'كلمة المرور ضعيفة — 6 أحرف على الأقل.';
    if (code.startsWith('TOO_MANY_ATTEMPTS')) return 'محاولات كثيرة — حاول بعد قليل.';
    if (code.startsWith('USER_DISABLED')) return 'هذا الحساب موقوف.';
    if (code.startsWith('OPERATION_NOT_ALLOWED')) {
      return 'تسجيل البريد غير مفعّل في Firebase (Authentication → Email/Password).';
    }
    if (code.startsWith('INVALID_EMAIL')) return 'صيغة البريد الإلكتروني غير صحيحة.';
    return 'تعذّر الاتصال بالخادم — حاول مرة أخرى.';
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) async {
    http.Response r;
    try {
      r = await _http
          .post(Uri.parse(url),
              headers: <String, String>{'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw CloudException('تعذّر الاتصال بالخادم — تحقّق من اتصالك.');
    }
    final dynamic j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (r.statusCode != 200) {
      final String code =
          (j is Map && j['error'] is Map) ? (j['error']['message'] ?? '').toString() : '';
      throw CloudException(_arabic(code), code: code);
    }
    return Map<String, dynamic>.from(j as Map);
  }

  CloudUser _fromAuth(Map<String, dynamic> j, {String? name}) => CloudUser(
        uid: (j['localId'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        name: name ?? (j['displayName'] ?? '').toString(),
        idToken: (j['idToken'] ?? '').toString(),
        refreshToken: (j['refreshToken'] ?? '').toString(),
        expiresAt: DateTime.now().add(Duration(
            seconds: (int.tryParse('${j['expiresIn'] ?? 3600}') ?? 3600) - 120)),
      );

  Future<CloudUser> register(String email, String password, String name) async {
    final Map<String, dynamic> j = await _post(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FirebaseConfig.apiKey}',
        <String, dynamic>{
          'email': email.trim().toLowerCase(),
          'password': password,
          'returnSecureToken': true,
        });
    _user = _fromAuth(j, name: name.trim());
    try {
      await _post(
          'https://identitytoolkit.googleapis.com/v1/accounts:update?key=${FirebaseConfig.apiKey}',
          <String, dynamic>{
            'idToken': _user!.idToken,
            'displayName': name.trim(),
            'returnSecureToken': false,
          });
    } catch (_) {}
    await _persist();
    notifyListeners();
    return _user!;
  }

  Future<CloudUser> signIn(String email, String password) async {
    final Map<String, dynamic> j = await _post(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FirebaseConfig.apiKey}',
        <String, dynamic>{
          'email': email.trim().toLowerCase(),
          'password': password,
          'returnSecureToken': true,
        });
    _user = _fromAuth(j);
    await _persist();
    notifyListeners();
    return _user!;
  }

  Future<void> signOut() async {
    _user = null;
    await _persist();
    notifyListeners();
  }

  Future<void> setName(String name) async {
    if (_user == null) return;
    _user = _user!.copyWith(name: name.trim());
    await _persist();
    notifyListeners();
  }

  /// A valid ID token (refreshed when close to expiry), or null.
  Future<String?> freshToken() async {
    final CloudUser? u = _user;
    if (u == null) return null;
    if (DateTime.now().isBefore(u.expiresAt)) return u.idToken;
    try {
      final http.Response r = await _http
          .post(
              Uri.parse(
                  'https://securetoken.googleapis.com/v1/token?key=${FirebaseConfig.apiKey}'),
              headers: <String, String>{
                'Content-Type': 'application/x-www-form-urlencoded'
              },
              body: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(u.refreshToken)}')
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        if (r.statusCode == 400) await signOut(); // revoked / deleted
        return null;
      }
      final Map<String, dynamic> j =
          Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      _user = u.copyWith(
        idToken: (j['id_token'] ?? '').toString(),
        refreshToken: (j['refresh_token'] ?? u.refreshToken).toString(),
        expiresAt: DateTime.now().add(Duration(
            seconds: (int.tryParse('${j['expires_in'] ?? 3600}') ?? 3600) - 120)),
      );
      await _persist();
      return _user!.idToken;
    } catch (_) {
      return null;
    }
  }
}

/// Server value: atomic increment.
Map<String, dynamic> inc([int by = 1]) => <String, dynamic>{
      '.sv': <String, dynamic>{'increment': by}
    };

/// Server value: server timestamp (ms).
const Map<String, String> serverTime = <String, String>{'.sv': 'timestamp'};

/// Realtime Database over REST, scoped to [FirebaseConfig.root].
class CloudDb {
  CloudDb._();
  static final CloudDb I = CloudDb._();
  final http.Client _http = createHttpClient();

  /// Makes any string safe as a database key (no . $ # [ ] /).
  static String key(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

  Future<Uri> _uri(String path, [Map<String, String>? q]) async {
    final String? tok = await CloudAuth.I.freshToken();
    final Map<String, String> params = <String, String>{
      ...?q,
      if (tok != null) 'auth': tok,
    };
    final String p = path.isEmpty ? FirebaseConfig.root : '${FirebaseConfig.root}/$path';
    return Uri.parse('${FirebaseConfig.dbUrl}/$p.json')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, String>? query}) async {
    final Uri u = await _uri(path, query);
    http.Response r;
    try {
      final http.Request req = http.Request(method, u)
        ..headers['Content-Type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw CloudException('تعذّر الاتصال بالخادم.');
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw CloudException('غير مسموح — سجّل الدخول أولًا.', code: 'denied');
    }
    if (r.statusCode >= 400) {
      throw CloudException('خطأ في الخادم (${r.statusCode}).');
    }
    return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> put(String path, Object? value) =>
      _send('PUT', path, body: value);
  Future<dynamic> patch(String path, Map<String, dynamic> value) =>
      _send('PATCH', path, body: value);
  Future<void> delete(String path) async => _send('DELETE', path);

  /// Appends with a chronological push id; returns the id.
  Future<String> push(String path, Object value) async {
    final dynamic r = await _send('POST', path, body: value);
    return (r is Map ? r['name'] : '').toString();
  }

  /// Multi-path atomic update relative to the Animax root.
  Future<void> update(Map<String, dynamic> paths) async =>
      _send('PATCH', '', body: paths);

  /// Lightweight reachability check (used by the splash).
  Future<bool> ping() async {
    try {
      final Uri u = Uri.parse('${FirebaseConfig.dbUrl}/.json')
          .replace(queryParameters: <String, String>{'shallow': 'true'});
      final http.Response r =
          await _http.get(u).timeout(const Duration(seconds: 8));
      return r.statusCode == 200 || r.statusCode == 401;
    } catch (_) {
      return false;
    }
  }
}

/// Cloud Storage uploads (clips).
class CloudStorage {
  CloudStorage._();
  static final CloudStorage I = CloudStorage._();
  final http.Client _http = createHttpClient();

  /// Uploads [bytes] to `animax/<path>`; returns a public download URL.
  Future<String> upload(String path, Uint8List bytes, String contentType) async {
    final String? tok = await CloudAuth.I.freshToken();
    if (tok == null) throw CloudException('سجّل الدخول أولًا.');
    final String name = '${FirebaseConfig.root}/$path';
    final Uri u = Uri.parse(
            'https://firebasestorage.googleapis.com/v0/b/${FirebaseConfig.bucket}/o')
        .replace(queryParameters: <String, String>{
      'uploadType': 'media',
      'name': name,
    });
    http.Response r;
    try {
      r = await _http
          .post(u,
              headers: <String, String>{
                'Authorization': 'Firebase $tok',
                'Content-Type': contentType,
              },
              body: bytes)
          .timeout(const Duration(minutes: 3));
    } catch (_) {
      throw CloudException('تعذّر رفع المقطع — تحقّق من اتصالك.');
    }
    if (r.statusCode != 200) {
      throw CloudException('تعذّر رفع المقطع (${r.statusCode}).');
    }
    final Map<String, dynamic> j =
        Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    final String token = (j['downloadTokens'] ?? '').toString().split(',').first;
    return 'https://firebasestorage.googleapis.com/v0/b/${FirebaseConfig.bucket}/o/'
        '${Uri.encodeComponent(name)}?alt=media${token.isEmpty ? '' : '&token=$token'}';
  }
}
