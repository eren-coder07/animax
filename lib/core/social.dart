import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud.dart';

/// Social layer on the Realtime Database (all under `/animax`):
///
/// ```
/// users/{uid}                 {name, joined, followers, following, clips}
/// following/{uid}/{target}    true          followers/{target}/{uid} true
/// items/{k}                   {views, likes, comments, title, poster, kind}
/// itemLikes/{k}/{uid}         true
/// comments/{k}/{cid}          {uid, name, text, at, likes}
/// commentLikes/{k}/{cid}/{uid} true
/// clips/{id}                  {uid, name, title, poster, kind, source, ref,
///                              startMs, endMs, label, at, likes, comments,
///                              reposts, views}
/// clipLikes/{id}/{uid}, clipComments/{id}/{cid}, clipReposts/{id}/{uid}
/// reposts/{uid}/{id}          at
/// bingo/{uid}                 {cells: {goal: true}, lines, badges}
/// binge/{uid}                 {streak, best, last}
/// ```
/// `k` = [CloudDb.key] of the item key (e.g. `akwam:/movie/1/x`).
class Social {
  Social._();

  static String get _uid => CloudAuth.I.user?.uid ?? '';
  static String get _name => CloudAuth.I.user?.name ?? '';

  static void _needLogin() {
    if (!CloudAuth.I.signedIn) {
      throw CloudException('سجّل الدخول لاستخدام هذه الميزة.', code: 'login');
    }
  }

  // ----------------------------------------------------------- items / views

  /// Counts the view of an item (fire-and-forget) and stores its card info.
  static Future<void> countView(String itemKey,
      {String title = '', String poster = '', String kind = ''}) async {
    try {
      final String k = CloudDb.key(itemKey);
      await CloudDb.I.update(<String, dynamic>{
        'items/$k/views': inc(),
        if (title.isNotEmpty) 'items/$k/title': title,
        if (poster.isNotEmpty) 'items/$k/poster': poster,
        if (kind.isNotEmpty) 'items/$k/kind': kind,
      });
      _counts.remove(itemKey);
      BingoStore.I.record(kind == 'manga' ? BingoGoal.readManga : BingoGoal.forKind(kind));
    } catch (_) {}
  }

  static final Map<String, ({ItemStats stats, DateTime at})> _counts =
      <String, ({ItemStats stats, DateTime at})>{};

  static Future<ItemStats> stats(String itemKey) async {
    final ({ItemStats stats, DateTime at})? hit = _counts[itemKey];
    if (hit != null && DateTime.now().difference(hit.at).inSeconds < 30) {
      return hit.stats;
    }
    final String k = CloudDb.key(itemKey);
    final dynamic v = await CloudDb.I.get('items/$k');
    bool liked = false;
    if (_uid.isNotEmpty) {
      liked = (await CloudDb.I.get('itemLikes/$k/$_uid')) == true;
    }
    final ItemStats s = ItemStats.fromJson(v, liked: liked);
    _counts[itemKey] = (stats: s, at: DateTime.now());
    return s;
  }

  static Future<void> setLike(String itemKey, bool like) async {
    _needLogin();
    final String k = CloudDb.key(itemKey);
    await CloudDb.I.update(<String, dynamic>{
      'itemLikes/$k/$_uid': like ? true : null,
      'items/$k/likes': inc(like ? 1 : -1),
    });
    _counts.remove(itemKey);
    if (like) BingoStore.I.record(BingoGoal.like);
  }

  // --------------------------------------------------------------- comments

  static Future<List<Comment>> comments(String threadPath, String key,
      {int limit = 60}) async {
    final dynamic v = await CloudDb.I.get('$threadPath/${CloudDb.key(key)}',
        query: <String, String>{
          'orderBy': '"\$key"',
          'limitToLast': '$limit',
        });
    final List<Comment> out = <Comment>[];
    if (v is Map) {
      v.forEach((dynamic id, dynamic c) {
        if (c is Map) out.add(Comment.fromJson(id.toString(), c));
      });
    }
    out.sort((Comment a, Comment b) => b.at.compareTo(a.at));
    return out;
  }

  /// [threadPath]: `comments` (items) or `clipComments` (clips).
  /// [counterPath]: `items/{k}` or `clips/{id}`.
  static Future<Comment> addComment(
      String threadPath, String key, String counterPath, String text) async {
    _needLogin();
    final String t = text.trim();
    if (t.isEmpty) throw CloudException('اكتب تعليقًا أولًا.');
    if (t.length > 500) throw CloudException('التعليق طويل جدًا (500 حرف كحد أقصى).');
    final String k = CloudDb.key(key);
    final String id = await CloudDb.I.push('$threadPath/$k', <String, dynamic>{
      'uid': _uid,
      'name': _name,
      'text': t,
      'at': serverTime,
      'likes': 0,
    });
    await CloudDb.I.update(<String, dynamic>{'$counterPath/comments': inc()});
    _counts.remove(key);
    BingoStore.I.record(BingoGoal.comment);
    return Comment(
        id: id, uid: _uid, name: _name, text: t, at: DateTime.now(), likes: 0);
  }

  static Future<void> deleteComment(
      String threadPath, String key, String counterPath, Comment c) async {
    _needLogin();
    if (c.uid != _uid) return;
    final String k = CloudDb.key(key);
    await CloudDb.I.update(<String, dynamic>{
      '$threadPath/$k/${c.id}': null,
      '$counterPath/comments': inc(-1),
    });
  }

  static Future<bool> commentLiked(String threadPath, String key, String cid) async {
    if (_uid.isEmpty) return false;
    return (await CloudDb.I
            .get('${threadPath}Likes/${CloudDb.key(key)}/$cid/$_uid')) ==
        true;
  }

  static Future<void> setCommentLike(
      String threadPath, String key, String cid, bool like) async {
    _needLogin();
    final String k = CloudDb.key(key);
    await CloudDb.I.update(<String, dynamic>{
      '${threadPath}Likes/$k/$cid/$_uid': like ? true : null,
      '$threadPath/$k/$cid/likes': inc(like ? 1 : -1),
    });
  }

  // ---------------------------------------------------------------- users

  static Future<void> ensureProfile() async {
    if (_uid.isEmpty) return;
    try {
      final dynamic v = await CloudDb.I.get('users/$_uid/name');
      if (v == null || v.toString() != _name) {
        await CloudDb.I.patch('users/$_uid', <String, dynamic>{
          'name': _name,
          if (v == null) 'joined': serverTime,
        });
      }
    } catch (_) {}
  }

  static Future<UserProfile?> profile(String uid) async {
    final dynamic v = await CloudDb.I.get('users/$uid');
    if (v is! Map) return null;
    bool following = false;
    if (_uid.isNotEmpty && _uid != uid) {
      following = (await CloudDb.I.get('following/$_uid/$uid')) == true;
    }
    return UserProfile.fromJson(uid, v, following: following);
  }

  static Future<void> setFollow(String target, bool follow) async {
    _needLogin();
    if (target == _uid) return;
    await CloudDb.I.update(<String, dynamic>{
      'following/$_uid/$target': follow ? true : null,
      'followers/$target/$_uid': follow ? true : null,
      'users/$target/followers': inc(follow ? 1 : -1),
      'users/$_uid/following': inc(follow ? 1 : -1),
    });
    if (follow) BingoStore.I.record(BingoGoal.follow);
  }

  // ---------------------------------------------------------------- clips

  static Future<String> createClip(VideoClip c) async {
    _needLogin();
    final String id = await CloudDb.I.push('clips', <String, dynamic>{
      ...c.toJson(),
      'uid': _uid,
      'name': _name,
      'at': serverTime,
      'likes': 0,
      'comments': 0,
      'reposts': 0,
      'views': 0,
    });
    await CloudDb.I.update(<String, dynamic>{'users/$_uid/clips': inc()});
    BingoStore.I.record(BingoGoal.clip);
    return id;
  }

  /// Newest clips first.
  static Future<List<VideoClip>> clipsFeed({int limit = 40}) async {
    final dynamic v = await CloudDb.I.get('clips', query: <String, String>{
      'orderBy': '"\$key"',
      'limitToLast': '$limit',
    });
    final List<VideoClip> out = <VideoClip>[];
    if (v is Map) {
      v.forEach((dynamic id, dynamic c) {
        if (c is Map) out.add(VideoClip.fromJson(id.toString(), c));
      });
    }
    out.sort((VideoClip a, VideoClip b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return out;
  }

  static Future<List<VideoClip>> clipsOf(String uid) async {
    final List<VideoClip> all = await clipsFeed(limit: 200);
    final Map<dynamic, dynamic> reposts =
        (await CloudDb.I.get('reposts/$uid') as Map<dynamic, dynamic>?) ??
            <dynamic, dynamic>{};
    return all
        .where((VideoClip c) => c.uid == uid || reposts.containsKey(c.id))
        .toList();
  }

  static Future<({bool liked, bool reposted})> clipState(String id) async {
    if (_uid.isEmpty) return (liked: false, reposted: false);
    final List<dynamic> r = await Future.wait(<Future<dynamic>>[
      CloudDb.I.get('clipLikes/$id/$_uid'),
      CloudDb.I.get('clipReposts/$id/$_uid'),
    ]);
    return (liked: r[0] == true, reposted: r[1] != null);
  }

  static Future<void> setClipLike(String id, bool like) async {
    _needLogin();
    await CloudDb.I.update(<String, dynamic>{
      'clipLikes/$id/$_uid': like ? true : null,
      'clips/$id/likes': inc(like ? 1 : -1),
    });
    if (like) BingoStore.I.record(BingoGoal.like);
  }

  static Future<void> setRepost(String id, bool repost) async {
    _needLogin();
    await CloudDb.I.update(<String, dynamic>{
      'clipReposts/$id/$_uid': repost ? serverTime : null,
      'reposts/$_uid/$id': repost ? serverTime : null,
      'clips/$id/reposts': inc(repost ? 1 : -1),
    });
  }

  static Future<void> countClipView(String id) async {
    try {
      await CloudDb.I.update(<String, dynamic>{'clips/$id/views': inc()});
    } catch (_) {}
  }

  static Future<void> deleteClip(VideoClip c) async {
    _needLogin();
    if (c.uid != _uid) return;
    await CloudDb.I.update(<String, dynamic>{
      'clips/${c.id}': null,
      'users/$_uid/clips': inc(-1),
    });
  }

  /// Item view counts for poster badges (one request, cached 2 min).
  static Map<String, int> _viewsByKey = <String, int>{};
  static DateTime _viewsAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<Map<String, int>> allViews() async {
    if (DateTime.now().difference(_viewsAt).inMinutes < 2) return _viewsByKey;
    try {
      final dynamic v = await CloudDb.I.get('items', query: <String, String>{
        'orderBy': '"views"',
        'limitToLast': '300',
      });
      final Map<String, int> m = <String, int>{};
      if (v is Map) {
        v.forEach((dynamic k, dynamic it) {
          if (it is Map) m[k.toString()] = (it['views'] as num?)?.toInt() ?? 0;
        });
      }
      _viewsByKey = m;
      _viewsAt = DateTime.now();
    } catch (_) {}
    return _viewsByKey;
  }
}

class ItemStats {
  const ItemStats(
      {this.views = 0, this.likes = 0, this.comments = 0, this.liked = false});
  final int views;
  final int likes;
  final int comments;
  final bool liked;

  static ItemStats fromJson(dynamic v, {bool liked = false}) {
    if (v is! Map) return ItemStats(liked: liked);
    int n(String k) => ((v[k] as num?)?.toInt() ?? 0).clamp(0, 1 << 31);
    return ItemStats(
        views: n('views'), likes: n('likes'), comments: n('comments'), liked: liked);
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.at,
    required this.likes,
  });
  final String id;
  final String uid;
  final String name;
  final String text;
  final DateTime at;
  final int likes;

  static Comment fromJson(String id, Map<dynamic, dynamic> j) => Comment(
        id: id,
        uid: (j['uid'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
        likes: ((j['likes'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31),
      );
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    this.followers = 0,
    this.following = 0,
    this.clips = 0,
    this.isFollowing = false,
    this.joined,
  });
  final String uid;
  final String name;
  final int followers;
  final int following;
  final int clips;
  final bool isFollowing;
  final DateTime? joined;

  static UserProfile fromJson(String uid, Map<dynamic, dynamic> j,
      {bool following = false}) {
    int n(String k) => ((j[k] as num?)?.toInt() ?? 0).clamp(0, 1 << 31);
    final num? joined = j['joined'] as num?;
    return UserProfile(
      uid: uid,
      name: (j['name'] ?? 'مستخدم').toString(),
      followers: n('followers'),
      following: n('following'),
      clips: n('clips'),
      isFollowing: following,
      joined: joined == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(joined.toInt()),
    );
  }
}

/// A ≤10 s clip: a reference to a window of a source video.
class VideoClip {
  const VideoClip({
    this.id = '',
    this.uid = '',
    this.name = '',
    required this.title,
    this.label = '',
    this.poster = '',
    required this.kind,
    required this.source,
    required this.ref,
    required this.startMs,
    required this.endMs,
    this.at,
    this.likes = 0,
    this.comments = 0,
    this.reposts = 0,
    this.views = 0,
  });

  final String id;
  final String uid;
  final String name;
  final String title;

  /// e.g. "الحلقة 4 · 12:30"
  final String label;
  final String poster;
  final String kind;

  /// `akwam` (ref.path = watch page) · `anime` (watchId, ep) · `hh` (slug, ep)
  final String source;
  final Map<String, String> ref;
  final int startMs;
  final int endMs;
  final DateTime? at;
  final int likes;
  final int comments;
  final int reposts;
  final int views;

  static const int maxMs = 10000;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'label': label,
        'poster': poster,
        'kind': kind,
        'source': source,
        'ref': ref,
        'startMs': startMs,
        'endMs': endMs,
      };

  static VideoClip fromJson(String id, Map<dynamic, dynamic> j) {
    int n(String k) => ((j[k] as num?)?.toInt() ?? 0).clamp(0, 1 << 31);
    return VideoClip(
      id: id,
      uid: (j['uid'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      poster: (j['poster'] ?? '').toString(),
      kind: (j['kind'] ?? '').toString(),
      source: (j['source'] ?? '').toString(),
      ref: (j['ref'] is Map)
          ? (j['ref'] as Map<dynamic, dynamic>)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
      startMs: n('startMs'),
      endMs: n('endMs'),
      at: DateTime.fromMillisecondsSinceEpoch(n('at')),
      likes: n('likes'),
      comments: n('comments'),
      reposts: n('reposts'),
      views: n('views'),
    );
  }
}

// =============================================================================
// Bingo challenge card
// =============================================================================

enum BingoGoal {
  watchAkwam('شاهد فيلمًا أو حلقة من أكوام', 'movie'),
  watchAnime('شاهد حلقة أنمي', 'anime'),
  watchCartoon('شاهد كرتونًا', 'cartoon'),
  readManga('اقرأ فصل مانغا', 'menu_book'),
  like('أعجب بعمل أو مقطع', 'favorite'),
  comment('اكتب تعليقًا', 'chat'),
  clip('اصنع مقطعًا (كليب)', 'content_cut'),
  follow('تابع مستخدمًا', 'person_add'),
  binge('شاهد 3 حلقات متتالية (ماراثون)', 'bolt');

  const BingoGoal(this.label, this.icon);
  final String label;
  final String icon;

  static BingoGoal forKind(String kind) => switch (kind) {
        'anime' => BingoGoal.watchAnime,
        'cartoon' || 'cinema' => BingoGoal.watchCartoon,
        'manga' => BingoGoal.readManga,
        _ => BingoGoal.watchAkwam,
      };
}

/// 3×3 card; a full row, column or diagonal = a "bingo" line.
class BingoStore extends ChangeNotifier {
  BingoStore._();
  static final BingoStore I = BingoStore._();

  final Set<BingoGoal> done = <BingoGoal>{};
  bool _loaded = false;

  static const List<List<int>> lines = <List<int>>[
    <int>[0, 1, 2], <int>[3, 4, 5], <int>[6, 7, 8],
    <int>[0, 3, 6], <int>[1, 4, 7], <int>[2, 5, 8],
    <int>[0, 4, 8], <int>[2, 4, 6],
  ];

  int get lineCount => lines
      .where((List<int> l) =>
          l.every((int i) => done.contains(BingoGoal.values[i])))
      .length;

  bool get full => done.length == BingoGoal.values.length;

  Future<void> load() async {
    final String uid = CloudAuth.I.user?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final dynamic v = await CloudDb.I.get('bingo/$uid/cells');
      done.clear();
      if (v is Map) {
        for (final BingoGoal g in BingoGoal.values) {
          if (v[g.name] == true) done.add(g);
        }
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  void record(BingoGoal g) {
    final String uid = CloudAuth.I.user?.uid ?? '';
    if (uid.isEmpty || done.contains(g)) return;
    final int before = lineCount;
    done.add(g);
    notifyListeners();
    unawaited(CloudDb.I.update(<String, dynamic>{
      'bingo/$uid/cells/${g.name}': true,
      if (lineCount > before) 'bingo/$uid/lines': lineCount,
    }).catchError((Object _) {}));
  }

  Future<void> reset() async {
    final String uid = CloudAuth.I.user?.uid ?? '';
    done.clear();
    notifyListeners();
    if (uid.isEmpty) return;
    try {
      await CloudDb.I.update(<String, dynamic>{
        'bingo/$uid/cells': null,
        'bingo/$uid/rounds': inc(),
      });
    } catch (_) {}
  }

  bool get loaded => _loaded;
}

// =============================================================================
// Binge (marathon) streak
// =============================================================================

class BingeStore extends ChangeNotifier {
  BingeStore._();
  static final BingeStore I = BingeStore._();

  /// Episodes finished back-to-back in the current session.
  int session = 0;

  void episodeFinished() {
    session++;
    if (session >= 3) BingoStore.I.record(BingoGoal.binge);
    notifyListeners();
    final String uid = CloudAuth.I.user?.uid ?? '';
    if (uid.isEmpty) return;
    unawaited(CloudDb.I.update(<String, dynamic>{
      'binge/$uid/episodes': inc(),
      'binge/$uid/last': serverTime,
    }).catchError((Object _) {}));
  }

  void reset() {
    session = 0;
    notifyListeners();
  }
}

/// Community view counts for poster badges (top items, refreshed ≤ 2 min).
class ViewCounts extends ChangeNotifier {
  ViewCounts._();
  static final ViewCounts I = ViewCounts._();

  Map<String, int> _m = <String, int>{};
  bool _loading = false;

  int of(String itemKey) {
    if (_m.isEmpty && !_loading) refresh();
    return _m[CloudDb.key(itemKey)] ?? 0;
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final Map<String, int> m = await Social.allViews();
      if (m.isNotEmpty) {
        _m = m;
        notifyListeners();
      }
    } finally {
      _loading = false;
    }
  }
}
