import 'package:animax/core/download_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('animax/app'),
            (MethodCall c) async {
      calls.add(c);
      return true;
    });
  });

  test('finished download: the file is shared right away', () async {
    final DownloadItem done = DownloadItem(
      id: 'd1',
      kind: DownloadKind.video,
      title: 'الهيبة',
      subtitle: 'الحلقة 4',
      source: 'akwam',
      ref: const <String, String>{'path': '/episode/1/x'},
      key: 'akwam:/episode/1/x',
      status: DownloadStatus.done,
      resultUri: 'content://media/external/downloads/42',
      mime: 'video/mp4',
    );
    DownloadManager.I.debugSeed(<DownloadItem>[done]);
    final bool opened = await DownloadManager.I.quickShareFile(
        source: 'akwam',
        ref: const <String, String>{'path': '/episode/1/x'},
        title: 'الهيبة');
    expect(opened, isTrue);
    final MethodCall share =
        calls.firstWhere((MethodCall c) => c.method == 'dlShareFile');
    expect((share.arguments as Map<dynamic, dynamic>)['uri'],
        'content://media/external/downloads/42');
    expect((share.arguments as Map<dynamic, dynamic>)['text'],
        contains('الهيبة — الحلقة 4'));
  });

  test('download in progress: flagged to share when it finishes', () async {
    final DownloadItem running = DownloadItem(
      id: 'r1',
      kind: DownloadKind.video,
      title: 'Steps',
      source: 'akwam',
      ref: const <String, String>{'path': '/movie/11708/steps'},
      key: 'akwam:/movie/11708/steps',
      status: DownloadStatus.running,
    );
    DownloadManager.I.debugSeed(<DownloadItem>[running]);
    final bool opened = await DownloadManager.I.quickShareFile(
        source: 'akwam',
        ref: const <String, String>{'path': '/movie/11708/steps'},
        title: 'Steps');
    expect(opened, isFalse);
    expect(running.shareWhenDone, isTrue);
    expect(calls.where((MethodCall c) => c.method == 'dlShareFile'), isEmpty);
  });

  test('shareWhenDone survives a restart (JSON)', () {
    final DownloadItem it = DownloadItem(
        id: 'x', kind: DownloadKind.video, title: 't', url: 'u', shareWhenDone: true);
    expect(DownloadItem.fromJson(it.toJson()).shareWhenDone, isTrue);
  });
}
