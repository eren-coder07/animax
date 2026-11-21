import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/library_store.dart';
import '../widgets/download_button.dart';
import '../widgets/mb_ui.dart';
import '../widgets/quick_share.dart';

/// Akwam details: hero backdrop, meta row, synopsis, and either the
/// episode list (series / shows) or the quality list (movies).
class AkwamDetailsScreen extends StatefulWidget {
  const AkwamDetailsScreen({super.key});

  @override
  State<AkwamDetailsScreen> createState() => _AkwamDetailsScreenState();
}

class _AkwamDetailsScreenState extends State<AkwamDetailsScreen> {
  late AkwamItem _item;
  List<AkwamEpisode>? _episodes;
  List<AkwamSource>? _sources;
  String? _error;
  bool _busy = false;
  int _quality = 0; // selected source (movies)
  int _tab = 0;
  Future<List<AkwamItem>>? _suggest;

  @override
  void initState() {
    super.initState();
    _item = AkwamItem(id: '', path: '', kind: AkwamKind.movie, title: '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Object? args = ModalRoute.of(context)!.settings.arguments;
    if (args is AkwamItem && args.path != _item.path) {
      _item = args;
      _episodes = null;
      _sources = null;
      _error = null;
      _quality = 0;
      _tab = 0;
      _suggest = AkwamApi.I.recent().catchError((Object _) => <AkwamItem>[]);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final AkwamItem rich = await AkwamApi.I.details(_item);
      if (!mounted) return;
      setState(() {
        _item = rich;
        if (rich.isSeries) {
          _episodes = rich.episodes;
        } else {
          _sources = null;
        }
        _busy = false;
      });
      if (!rich.isSeries) {
        final List<AkwamSource> sources = await AkwamApi.I.sourcesFor(_item);
        if (!mounted) return;
        setState(() => _sources = sources);
      }
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل هذا العنوان.';
        _busy = false;
      });
    }
  }

  void _play({AkwamEpisode? episode}) {
    Navigator.pushNamed(
      context,
      '/akwam-player',
      arguments: (item: _item, episode: episode),
    );
  }

  // ----- Downloads (resolved to a direct file when the download starts) -----

  String _keyFor(String path) => 'akwam:$path';

  Future<void> _downloadPath(String path, String subtitle) async {
    await DownloadManager.I.addResolvable(
      source: 'akwam',
      ref: <String, String>{'path': path},
      title: _item.title,
      subtitle: subtitle,
      poster: _item.poster,
    );
  }

  /// Movie: best quality. Series: asks, then queues every episode.
  Future<void> _downloadMain() async {
    if (!_item.isSeries) {
      await _downloadPath(_item.path, '');
      if (mounted) showDownloadQueuedSnack(context);
      return;
    }
    final List<AkwamEpisode> eps =
        List<AkwamEpisode>.of(_episodes ?? const <AkwamEpisode>[])
          ..sort((AkwamEpisode a, AkwamEpisode b) => a.number - b.number);
    if (eps.isEmpty) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تحميل كل الحلقات؟'),
        content: Text('سيتم تحميل ${eps.length} حلقة بأعلى جودة متاحة '
            'وحفظها في مجلد Download/Animax/Videos.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('تحميل')),
        ],
      ),
    );
    if (ok != true) return;
    for (final AkwamEpisode ep in eps) {
      await _downloadPath(ep.path, 'الحلقة ${ep.number}');
    }
    if (mounted) showDownloadQueuedSnack(context);
  }

  void _playFirst() {
    if (_item.isSeries) {
      final List<AkwamEpisode> eps = _episodes ?? const <AkwamEpisode>[];
      _play(episode: eps.isNotEmpty ? eps.first : null);
    } else {
      _play();
    }
  }

  String get _libKey => 'akwam:${_item.path}';

  void _toggleList() {
    final LibraryStore lib = LibraryStore.I;
    if (lib.isListed(_libKey)) {
      lib.removeListEntry(_libKey);
      _snack('أُزيل ${_item.title} من قائمتي');
    } else {
      lib.setListStatus(
        key: _libKey,
        title: _item.title,
        poster: _item.poster,
        kind: 'akwam',
        status: LibStatus.plan,
        meta: <String>[_item.year, _item.kind.label]
            .where((String x) => x.isNotEmpty)
            .join(' · '),
      );
      _snack('حُفظ ${_item.title} في قائمتي');
    }
  }

  /// Quick share: movie → selected quality; series → first episode.
  void _share() {
    final List<AkwamSource> src = _sources ?? const <AkwamSource>[];
    final List<AkwamEpisode> eps =
        List<AkwamEpisode>.of(_episodes ?? const <AkwamEpisode>[])
          ..sort((AkwamEpisode a, AkwamEpisode b) => a.number - b.number);
    if (_item.isSeries && eps.isNotEmpty) {
      _shareEpisode(eps.first);
      return;
    }
    final AkwamSource? s =
        src.isEmpty ? null : src[_quality.clamp(0, src.length - 1)];
    showQuickShare(
      context,
      title: _item.title,
      subtitle: s?.quality ?? '',
      poster: _item.poster,
      source: 'akwam',
      ref: <String, String>{'path': s?.watchPath ?? _item.path},
    );
  }

  void _shareEpisode(AkwamEpisode ep) => showQuickShare(
        context,
        title: _item.title,
        subtitle: 'الحلقة ${ep.number}',
        poster: _item.poster,
        source: 'akwam',
        ref: <String, String>{'path': ep.path},
      );

  void _snack(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t)));

  void _showInfo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (BuildContext c, ScrollController sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: <Widget>[
            Text(_item.title, style: _h(20)),
            const SizedBox(height: 8),
            MetaLine(rating: _item.rating, parts: _metaParts()),
            const SizedBox(height: 14),
            Text(_item.synopsis.isEmpty ? 'لا يوجد وصف لهذا العمل.' : _item.synopsis,
                style: const TextStyle(
                    fontFamily: kFont,
                    fontSize: 15,
                    height: 1.7,
                    color: Color(0xFFD5D6DA))),
          ],
        ),
      ),
    );
  }

  List<String> _metaParts() => <String>[
        _item.year,
        _item.kind.label,
        ..._item.genres.take(2),
      ];

  static TextStyle _h(double size) => TextStyle(
      fontFamily: kFont,
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: Colors.white);

  /// Primary download: selected quality (movie) or every episode (series).
  Future<void> _downloadPrimary() async {
    final List<AkwamSource> src = _sources ?? const <AkwamSource>[];
    if (!_item.isSeries && src.isNotEmpty) {
      final AkwamSource s = src[_quality.clamp(0, src.length - 1)];
      await _downloadPath(s.watchPath, s.quality);
      if (mounted) showDownloadQueuedSnack(context);
      return;
    }
    await _downloadMain();
  }

  @override
  Widget build(BuildContext context) {
    final double topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: <Widget>[
          ListView(
            padding: EdgeInsets.only(top: topPad, bottom: 110),
            children: <Widget>[
              _playerArea(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Flexible(
                      child: Text(_item.title.isEmpty ? '…' : _item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _h(22)),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _showInfo,
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('معلومات',
                                style: TextStyle(
                                    fontFamily: kFont,
                                    fontSize: 15,
                                    color: AppColors.sub)),
                            Icon(Icons.chevron_right_rounded,
                                color: AppColors.sub, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: MetaLine(rating: _item.rating, parts: _metaParts()),
              ),
              const SizedBox(height: 14),
              _actions(),
              _resources(),
              const SizedBox(height: 14),
              _tabs(),
              _tabBody(),
            ],
          ),
          // Floating download button.
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: Center(
              child: SizedBox(
                width: 210,
                child: GradientButton(
                  label: _item.isSeries ? 'تحميل الحلقات' : 'تحميل',
                  icon: Icons.download_rounded,
                  height: 54,
                  expand: true,
                  onTap: _busy ? null : _downloadPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerArea() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: Colors.black, child: NetImage(_item.poster)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x99000000), Color(0x55000000), Color(0xCC000000)],
              ),
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _playFirst,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.45),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4))
                    : const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 40),
              ),
            ),
          ),
          PositionedDirectional(
            top: 4,
            start: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          PositionedDirectional(
            top: 8,
            end: 12,
            child: GestureDetector(
              onTap: _showInfo,
              child: const Column(
                children: <Widget>[
                  Icon(Icons.help_outline_rounded, color: Colors.white, size: 26),
                  Text('تفاصيل',
                      style: TextStyle(
                          fontFamily: kFont, fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          ),
          if (_error != null)
            PositionedDirectional(
              bottom: 10,
              start: 14,
              end: 14,
              child: Text(_error!,
                  style: const TextStyle(
                      fontFamily: kFont, fontSize: 13, color: AppColors.badge)),
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[LibraryStore.I, DownloadManager.I]),
      builder: (BuildContext c, _) {
        final bool listed = LibraryStore.I.isListed(_libKey);
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              PillButton(
                icon: listed ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded,
                label: listed ? 'في قائمتي' : 'أضف للقائمة',
                active: listed,
                onTap: _toggleList,
              ),
              const SizedBox(width: 10),
              PillButton(icon: Icons.ios_share_rounded, label: 'مشاركة', onTap: _share),
              const SizedBox(width: 10),
              PillButton(
                icon: Icons.download_rounded,
                label: 'تحميل',
                onTap: _busy ? null : _downloadPrimary,
              ),
              const SizedBox(width: 10),
              PillButton(
                icon: Icons.video_library_outlined,
                label: 'عرض التحميلات',
                onTap: () => Navigator.pushNamed(context, '/downloads'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resources() {
    final List<AkwamSource> src = _sources ?? const <AkwamSource>[];
    final List<AkwamEpisode> eps = _episodes ?? const <AkwamEpisode>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('المصادر', style: _h(19)),
              const SizedBox(width: 8),
              const Text('عبر أكوام',
                  style: TextStyle(
                      fontFamily: kFont, fontSize: 14, color: AppColors.sub)),
              const SizedBox(width: 6),
              const Icon(Icons.help_outline_rounded,
                  color: AppColors.sub, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          if (!_item.isSeries && src.length > 1)
            _QualityDropdown(
              sources: src,
              index: _quality.clamp(0, src.length - 1),
              onChanged: (int i) => setState(() => _quality = i),
            ),
          if (!_item.isSeries && src.length > 1) const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              soft: true,
              height: 58,
              expand: true,
              label: _item.isSeries
                  ? (eps.isEmpty
                      ? (_busy ? 'جارٍ تحميل الحلقات…' : _item.title)
                      : 'الحلقة ${eps.map((AkwamEpisode e) => e.number).reduce((int a, int b) => a < b ? a : b)} · ${_item.title}')
                  : (src.isEmpty
                      ? (_busy || _sources == null ? 'جارٍ تحميل الجودات…' : _item.title)
                      : '${_item.title} · ${src[_quality.clamp(0, src.length - 1)].quality}'),
              onTap: _busy ? null : _playFirst,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    final List<String> labels = <String>[
      if (_item.isSeries) 'الحلقات',
      'لك',
      'عن العمل',
    ];
    final int sel = _tab.clamp(0, labels.length - 1);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => setState(() => _tab = i),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Text(labels[i],
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: i == sel ? 19 : 17,
                            fontWeight:
                                i == sel ? FontWeight.w700 : FontWeight.w500,
                            color: i == sel ? Colors.white : AppColors.sub)),
                    const SizedBox(height: 6),
                    Container(
                      height: 3.5,
                      width: 42,
                      decoration: BoxDecoration(
                        color: i == sel ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBody() {
    final int offset = _item.isSeries ? 0 : 1;
    final int t = _tab + offset; // 0 episodes, 1 for you, 2 about
    if (t == 0) {
      return ListenableBuilder(
          listenable: LibraryStore.I, builder: (_, _) => _episodesGrid());
    }
    if (t == 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
            _item.synopsis.isEmpty ? 'لا يوجد وصف لهذا العمل.' : _item.synopsis,
            style: const TextStyle(
                fontFamily: kFont,
                fontSize: 15,
                height: 1.7,
                color: Color(0xFFD5D6DA))),
      );
    }
    return FutureBuilder<List<AkwamItem>>(
      future: _suggest,
      builder: (BuildContext c, AsyncSnapshot<List<AkwamItem>> snap) {
        final List<AkwamItem> items = (snap.data ?? const <AkwamItem>[])
            .where((AkwamItem x) => x.path != _item.path)
            .take(12)
            .toList();
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.brandGreen, strokeWidth: 2.4)),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 8,
            childAspectRatio: 0.56,
            children: <Widget>[
              for (final AkwamItem it in items)
                PosterTile(
                  title: it.title,
                  image: it.poster,
                  badge: it.qualityLabel,
                  rating: it.rating,
                  onTap: () => Navigator.pushReplacementNamed(
                      context, '/akwam-details',
                      arguments: it),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _episodesGrid() {
    final List<AkwamEpisode> eps =
        List<AkwamEpisode>.of(_episodes ?? const <AkwamEpisode>[])
          ..sort((AkwamEpisode a, AkwamEpisode b) => a.number - b.number);
    if (_episodes == null) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brandGreen, strokeWidth: 2.4)),
      );
    }
    if (eps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('لا توجد حلقات على أكوام لهذا العنوان بعد.',
            style: TextStyle(fontFamily: kFont, fontSize: 14, color: AppColors.sub)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: <Widget>[
          for (final AkwamEpisode ep in eps)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _play(episode: ep),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHi,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${ep.number}', style: _h(17)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text('الحلقة ${ep.number}',
                                    style: const TextStyle(
                                        fontFamily: kFont,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                                ...() {
                                  final ProgressEntry? p = LibraryStore.I
                                      .progressOf(_libKey, '${ep.number}');
                                  if (p == null) return const <Widget>[];
                                  return <Widget>[
                                    const SizedBox(width: 8),
                                    Icon(
                                        p.watched
                                            ? Icons.check_circle_rounded
                                            : Icons.timelapse_rounded,
                                        size: 16,
                                        color: p.watched
                                            ? AppColors.brandGreen
                                            : AppColors.star),
                                    const SizedBox(width: 3),
                                    Text(
                                        p.watched
                                            ? 'شوهدت'
                                            : 'توقفت عند ${p.positionSec ~/ 60} د',
                                        style: const TextStyle(
                                            fontFamily: kFont,
                                            fontSize: 12,
                                            color: AppColors.sub)),
                                  ];
                                }(),
                              ],
                            ),
                            if (ep.date.isNotEmpty)
                              Text(ep.date,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: kFont,
                                      fontSize: 12.5,
                                      color: AppColors.sub)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'مشاركة سريعة',
                        icon: const Icon(Icons.share_rounded,
                            color: AppColors.sub, size: 21),
                        onPressed: () => _shareEpisode(ep),
                      ),
                      DownloadIconButton(
                        downloadKey: _keyFor(ep.path),
                        color: AppColors.sub,
                        onStart: () =>
                            _downloadPath(ep.path, 'الحلقة ${ep.number}'),
                      ),
                      const Icon(Icons.play_circle_outline_rounded,
                          color: AppColors.brandGreen, size: 28),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Outlined quality picker ("Original Audio ⌄" style).
class _QualityDropdown extends StatelessWidget {
  const _QualityDropdown(
      {required this.sources, required this.index, required this.onChanged});
  final List<AkwamSource> sources;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      color: AppColors.surfaceHi,
      onSelected: onChanged,
      itemBuilder: (_) => <PopupMenuEntry<int>>[
        for (int i = 0; i < sources.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
                '${sources[i].quality}${sources[i].size.isEmpty ? '' : ' · ${sources[i].size}'}',
                style: const TextStyle(fontFamily: kFont, fontSize: 14.5)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF55565C)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
                '${sources[index].quality}${sources[index].size.isEmpty ? '' : ' · ${sources[index].size}'}',
                style: const TextStyle(
                    fontFamily: kFont, fontSize: 16, color: Colors.white)),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 24),
          ],
        ),
      ),
    );
  }
}
