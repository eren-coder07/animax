import 'package:animax/core/app_prefs.dart';
import 'package:animax/core/audio_mode.dart';
import 'package:animax/core/data_budget.dart';
import 'package:animax/core/library_store.dart';
import 'package:animax/core/moments.dart';
import 'package:animax/core/panels.dart';
import 'package:animax/core/social.dart';
import 'package:animax/core/spoilers.dart';
import 'package:animax/widgets/player_social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

VideoClip clip({
  String source = 'anime',
  Map<String, String> ref = const <String, String>{},
  String label = '',
  String uid = 'someone',
}) => VideoClip(
  id: 'c1',
  uid: uid,
  title: 't',
  label: label,
  kind: source,
  source: source,
  ref: ref,
  startMs: 0,
  endMs: 5000,
);

void main() {
  group('episode keys', () {
    test('akwam uses the episode / movie id, not the file id', () {
      expect(
        Moments.episodeKey('akwam', <String, String>{
          'path': '/watch/185190/11708/steps',
        }),
        'akwam:11708',
      );
      expect(
        Moments.episodeKey('akwam', <String, String>{
          'path': '/watch/181287/102324/x/y',
        }),
        'akwam:102324',
      );
      expect(
        Moments.episodeKey('akwam', <String, String>{'path': '/movie/1/x'}),
        '',
      );
    });
    test('anime / hh', () {
      expect(
        Moments.episodeKey('anime', <String, String>{
          'watchId': '82750',
          'ep': '3',
        }),
        'anime:82750:3',
      );
      expect(
        Moments.episodeKey('hh', <String, String>{'slug': 'abc', 'ep': '2'}),
        'hh:abc:2',
      );
      expect(
        Moments.episodeKey('manga', <String, String>{'chapterId': 'x'}),
        '',
      );
    });
  });

  group('hot moments', () {
    test('heat peaks where clips cluster and is normalized', () {
      final List<double> h = Moments.heat(
        <int>[600, 605, 610, 1200],
        1440,
        bins: 48,
      );
      final double mx = h.reduce((double a, double b) => a > b ? a : b);
      expect(mx, 1.0);
      final int hot = h.indexOf(mx);
      // 600-615 s of 1440 s → bin ≈ 20-21.
      expect(hot, inInclusiveRange(19, 22));
      expect(h.first, 0);
    });
    test('peak picks the densest window; empty → null', () {
      expect(
        Moments.peak(<int>[100, 600, 605, 612, 1200], 1440),
        inInclusiveRange(600, 612),
      );
      expect(Moments.peak(<int>[], 100), isNull);
      expect(Moments.heat(<int>[], 100).every((double v) => v == 0), isTrue);
    });
  });

  group('audio only', () {
    const String base = 'https://cdn.x/hls/master.m3u8';
    test('prefers the audio rendition of a master playlist', () {
      const String m =
          '#EXTM3U\n'
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="ar",URI="audio/ar.m3u8"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,AUDIO="a"\n'
          'v720.m3u8\n';
      expect(
        AudioMode.pickLightest(base, m),
        'https://cdn.x/hls/audio/ar.m3u8',
      );
    });
    test('falls back to the lowest-bandwidth variant', () {
      const String m =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nv720.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=426x240\nv240.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480\nv480.m3u8\n';
      expect(AudioMode.pickLightest(base, m), 'https://cdn.x/hls/v240.m3u8');
    });
    test('media playlists pass through', () {
      expect(
        AudioMode.pickLightest(base, '#EXTM3U\n#EXTINF:4,\nseg0.ts\n'),
        base,
      );
    });
  });

  group('data budget accounting', () {
    final DateTime nov = DateTime(2026, 11, 21);
    test('bills deltas only on cellular', () {
      var r = DataBudget.account(
        month: '2026-11',
        used: 0,
        last: 1000,
        total: 6000,
        cellular: true,
        now: nov,
      );
      expect(r.used, 5000);
      r = DataBudget.account(
        month: r.month,
        used: r.used,
        last: r.last,
        total: 9000,
        cellular: false,
        now: nov,
      );
      expect(r.used, 5000);
      expect(r.last, 9000);
    });
    test(
      'first sample only sets the baseline; reboot counts the new total',
      () {
        var r = DataBudget.account(
          month: '',
          used: 0,
          last: -1,
          total: 50000,
          cellular: true,
          now: nov,
        );
        expect(r.used, 0);
        r = DataBudget.account(
          month: r.month,
          used: 100,
          last: 50000,
          total: 300,
          cellular: true,
          now: nov,
        );
        expect(r.used, 400);
      },
    );
    test('a new month resets usage', () {
      final r = DataBudget.account(
        month: '2026-10',
        used: 999999,
        last: 10,
        total: 20,
        cellular: true,
        now: nov,
      );
      expect(r.month, '2026-11');
      expect(r.used, 10);
    });
  });

  group('panels', () {
    test('ref round-trip and clamping', () {
      final Map<String, String> ref = Panels.refFor(
        mangaId: 'm',
        chapterId: 'c',
        page: 3,
        r: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.3),
      );
      expect(ref['page'], '3');
      final Rect r = Panels.rectOf(ref);
      expect(r.left, closeTo(0.1, 1e-4));
      expect(r.height, closeTo(0.3, 1e-4));
      final Rect bad = Panels.rectOf(<String, String>{'x': '0.9', 'w': '0.5'});
      expect(bad.right, lessThanOrEqualTo(1.0));
    });
    test('pixel rect', () {
      final Rect px = Panels.pixelRect(
        const Rect.fromLTWH(0.5, 0.25, 0.5, 0.5),
        const Size(800, 1200),
      );
      expect(px, const Rect.fromLTWH(400, 300, 400, 600));
    });
  });

  group('league', () {
    test('week id is the Monday of the week', () {
      expect(
        BingoStore.weekId(DateTime.utc(2026, 11, 21)),
        'w20261116',
      ); // Saturday
      expect(
        BingoStore.weekId(DateTime.utc(2026, 11, 16)),
        'w20261116',
      ); // Monday
      expect(
        BingoStore.weekId(DateTime.utc(2026, 11, 22, 23)),
        'w20261116',
      ); // Sunday
      expect(BingoStore.weekId(DateTime.utc(2026, 11, 23)), 'w20261123');
      expect(
        BingoStore.weekEnds(DateTime.utc(2026, 11, 21, 10)),
        DateTime.utc(2026, 11, 23),
      );
    });
    test('score: goal 1, line 3, full card 5', () {
      expect(BingoStore.scoreOf(0, 0, false), 0);
      expect(BingoStore.scoreOf(3, 1, false), 6);
      expect(BingoStore.scoreOf(9, 8, true), 38);
    });
  });

  group('spoiler shield', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppPrefs.I.load();
      await LibraryStore.I.load();
    });

    test('episode number from ref or label', () {
      expect(clip(ref: <String, String>{'ep': '7'}).episode, 7);
      expect(clip(label: 'الحلقة 12 · 03:10').episode, 12);
      expect(clip(label: '39:49').episode, 0);
    });

    test('hides episodes beyond your progress, shows the next one', () {
      final VideoClip ep5 = clip(
        ref: <String, String>{'watchId': '82750', 'ep': '5'},
      );
      final VideoClip ep1 = clip(
        ref: <String, String>{'watchId': '82750', 'ep': '1'},
      );
      expect(Spoilers.hides(ep1), isFalse);
      expect(Spoilers.hides(ep5), isTrue);
      LibraryStore.I.saveProgress(
        key: 'anime:some-show-82750',
        sub: '4',
        positionSec: 30,
        durationSec: 1400,
      );
      expect(Spoilers.furthestEpisode(ep5), 4);
      expect(Spoilers.hides(ep5), isFalse); // next episode is fine
      final VideoClip ep7 = clip(
        ref: <String, String>{'watchId': '82750', 'ep': '7'},
      );
      expect(Spoilers.hides(ep7), isTrue);
      Spoilers.reveal('c1');
      expect(Spoilers.hides(ep7), isFalse);
    });

    test('akwam series matched by slug for old clips; switch turns it off', () {
      final VideoClip c = clip(
        source: 'akwam',
        ref: <String, String>{
          'path': '/watch/1/2/%D9%85%D8%B3%D9%84%D8%B3%D9%84/ep-9',
        },
        label: 'الحلقة 9 · 10:00',
      );
      c.toJson(); // sanity
      final VideoClip fresh = VideoClip(
        id: 'x9',
        uid: 'u',
        title: 't',
        label: c.label,
        kind: 'akwam',
        source: 'akwam',
        ref: c.ref,
        startMs: 0,
        endMs: 1,
      );
      expect(Spoilers.hides(fresh), isTrue);
      LibraryStore.I.saveProgress(
        key: 'akwam:/series/77/مسلسل',
        sub: '8',
        positionSec: 10,
        durationSec: 100,
      );
      expect(Spoilers.furthestEpisode(fresh), 8);
      expect(Spoilers.hides(fresh), isFalse);
      AppPrefs.I.set('spoilerShield', false);
      final VideoClip far = VideoClip(
        id: 'x20',
        uid: 'u',
        title: 't',
        label: 'الحلقة 20',
        kind: 'akwam',
        source: 'akwam',
        ref: c.ref,
        startMs: 0,
        endMs: 1,
      );
      expect(Spoilers.hides(far), isFalse);
      AppPrefs.I.set('spoilerShield', true);
    });
  });

  group('timed comments', () {
    test('activeAt window', () {
      final EpisodeSocial s = EpisodeSocial('');
      s.comments = const <TimedComment>[
        TimedComment(id: 'a', uid: 'u', name: 'n', text: 'x', t: 10),
        TimedComment(id: 'b', uid: 'u', name: 'n', text: 'y', t: 30),
      ];
      expect(s.activeAt(9).length, 0);
      expect(s.activeAt(12).map((TimedComment c) => c.id), <String>['a']);
      expect(s.activeAt(18, window: 7).length, 0);
      s.dispose();
    });
  });

  testWidgets('heat strip draws and seeks on tap', (WidgetTester t) async {
    final EpisodeSocial s = EpisodeSocial('');
    s.moments = <int>[600, 605, 610];
    Duration? sought;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: HeatStrip(
                social: s,
                duration: const Duration(seconds: 1440),
                onSeek: (Duration d) => sought = d,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('heatStrip')), findsOneWidget);
    await t.tapAt(
      t.getTopLeft(find.byKey(const Key('heatStrip'))) + const Offset(200, 5),
    );
    expect(sought, isNotNull);
    expect(sought!.inSeconds, inInclusiveRange(715, 725)); // half of 1440 s
    s.dispose();
  });

  group('v2.5', () {
    test('inbox sentences', () {
      InboxItem it(String type, {String title = '', String text = ''}) =>
          InboxItem(id: 'i', type: type, from: 'u', name: 'سارة', title: title, text: text);
      String strip(String v) => v.replaceAll(RegExp('[\u2068\u2069]'), '');
      expect(strip(it('clipLike', title: 'Steps').sentence), 'أعجب بمقطعك «Steps»');
      expect(it('clipLike', title: 'Steps').sentence, contains('\u2068Steps\u2069'));
      expect(strip(it('comment', text: 'رائع').sentence), 'علّق على مقطعك: رائع');
      expect(it('follow').sentence, 'بدأ بمتابعتك');
      expect(it('reply').sentence, 'ردّ على مقطعك بمقطع');
      expect(strip(it('repost', title: 'X').sentence), 'أعاد نشر مقطعك «X»');
      expect(strip(it('commentLike', text: 'ها').sentence), 'أعجب بتعليقك: ها');
      expect(it('weird').sentence, 'نشاط جديد');
    });

    test('inbox item json + unread count', () {
      final InboxItem a = InboxItem.fromJson('a', <String, dynamic>{
        'type': 'follow', 'from': 'u1', 'name': 'أحمد', 'at': 2000,
      });
      expect(a.at!.millisecondsSinceEpoch, 2000);
      Inbox.I.items = <InboxItem>[a, InboxItem.fromJson('b', <String, dynamic>{'type': 'follow', 'from': 'u2', 'at': 1000})];
      Inbox.I.seenAt = 1500;
      expect(Inbox.I.unread, 1);
      Inbox.I.items = const <InboxItem>[];
    });

    test('clip caption round-trips; empty caption is not stored', () {
      const VideoClip c = VideoClip(
          title: 't', kind: 'akwam', source: 'akwam', ref: <String, String>{},
          startMs: 0, endMs: 1000, caption: 'مشهد أسطوري');
      expect(c.toJson()['caption'], 'مشهد أسطوري');
      expect(VideoClip.fromJson('x', c.toJson()).caption, 'مشهد أسطوري');
      const VideoClip d = VideoClip(
          title: 't', kind: 'akwam', source: 'akwam', ref: <String, String>{}, startMs: 0, endMs: 1);
      expect(d.toJson().containsKey('caption'), isFalse);
    });

    test('profile bio parsed', () {
      final UserProfile p = UserProfile.fromJson('u', <String, dynamic>{'name': 'n', 'bio': 'محب للأنمي'});
      expect(p.bio, 'محب للأنمي');
    });
  });
}
