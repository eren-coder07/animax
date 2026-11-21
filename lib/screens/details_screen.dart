import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/social_bar.dart';
import '../core/api_html.dart';
import '../core/app_data.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/library_store.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/download_button.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  bool _expanded = false;
  String _season = 'الحلقات';

  late Anime _anime;
  Future<List<Episode>>? _episodesFuture;
  Future<List<Anime>>? _recsFuture;
  Future<Anime>? _detailsFuture;
  List<Anime> _recs = const <Anime>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Anime args = ModalRoute.of(context)!.settings.arguments as Anime;
    if (args.id != _anime.id) {
      _anime = args;
      _episodesFuture = AppState.I.episodesFor(_anime);
      _recsFuture = AppState.I.moreLikeAsync(_anime).then((List<Anime> list) {
        if (mounted) setState(() => _recs = list);
        return list;
      });
      _detailsFuture = AppState.I.loadDetails(_anime);
    }
  }

  @override
  void initState() {
    super.initState();
    _anime = const Anime(
        id: '',
        title: '',
        poster: '',
        score: 0,
        year: '',
        genres: <String>[],
        synopsis: '');
  }

  // ----- Downloads: the stream is resolved when the download starts -----

  String _dlKey(Episode ep) => 'anime:${_anime.watchId ?? ''}|${ep.number}';

  Future<void> _downloadEpisode(Episode ep) async {
    final String? wid = _anime.watchId;
    if (wid == null) return;
    await DownloadManager.I.addResolvable(
      source: 'anime',
      ref: <String, String>{'watchId': wid, 'ep': '${ep.number}'},
      title: _anime.title,
      subtitle: 'الحلقة ${ep.number}',
      poster: _anime.poster,
    );
  }

  Future<void> _downloadAll() async {
    final List<Episode> eps =
        await _episodesFuture ?? const <Episode>[];
    if (eps.isEmpty || !mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('تحميل كل الحلقات؟'),
        content: Text('سيتم تحميل ${eps.length} حلقة وحفظها في مجلد '
            'Download/Animax/Videos.'),
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
    for (final Episode ep in eps) {
      await _downloadEpisode(ep);
    }
    if (mounted) showDownloadQueuedSnack(context);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppState.I;

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              // ---------- Hero ----------
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Hero(
                  tag: 'poster-${_anime.id}',
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(anime: _anime, radius: 0),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroFade,
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              IconBubble(Icons.arrow_back_rounded,
                                  onTap: () => Navigator.pop(context)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---------- Content ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title, style: AppText.h2.copyWith(height: 1.25)),
                            const SizedBox(height: 6),
                            if (a.genres.isNotEmpty)
                              Text('${a.genreLine}.',
                                  style: AppText.label.copyWith(fontSize: 12)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: 'تشغيل',
                      playIcon: true,
                      height: 50,
                      expanded: true,
                      onTap: () async {
                        final List<Episode> eps =
                            await _episodesFuture ?? const <Episode>[];
                        if (!context.mounted) return;
                        Navigator.pushNamed(
                          context,
                          '/player',
                          arguments: eps.isNotEmpty
                              ? (_anime, eps.first)
                              : (_anime, null),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // ---------- Quick actions: list / rate / share ----------
                    _QuickActions(anime: _anime),
                    SocialBar(itemKey: 'anime:${_anime.id}', title: _anime.title),
                    const SizedBox(height: 18),
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Row(
                          children: [
                            Icon(Icons.star_rounded,
                                color: AppColors.accent, size: 20),
                            const SizedBox(width: 4),
                            Text(a.score.toStringAsFixed(1),
                                style: AppText.bodyBold.copyWith(fontSize: 15)),
                            const SizedBox(width: 16),
                            if (a.year.isNotEmpty)
                              Text(a.year, style: AppText.bodyBold),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: AppColors.stroke),
                              ),
                              child: Text(a.ageRating,
                                  style: AppText.label.copyWith(fontSize: 10)),
                            ),
                            const SizedBox(width: 12),
                            Text(
                                a.isMovie ? a.duration : '${a.episodeCount} حلقة',
                                style: AppText.label.copyWith(fontSize: 11)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<Anime>(
                      future: _detailsFuture,
                      builder: (BuildContext context, AsyncSnapshot<Anime> snap) {
                        final Anime a = snap.data ?? _anime;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.synopsis.isEmpty
                                  ? 'سيتم تحميل القصة من المصدر…'
                                  : a.synopsis,
                              style: AppText.body,
                              maxLines: _expanded ? 40 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (a.synopsis.isNotEmpty)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                child: Text(_expanded ? 'عرض أقل' : 'اقرأ المزيد',
                                    style: AppText.bodyBold.copyWith(
                                        color: AppColors.accent, fontSize: 12)),
                              ),
                            if (a.genres.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 20),
                              Text('التصنيف: ${a.genreLine}.',
                                  style: AppText.label.copyWith(fontSize: 11.5)),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // ---------- Episodes ----------
                    Row(
                      children: [
                        const Text('الحلقات', style: AppText.h3),
                        const Spacer(),
                        if (_anime.watchId != null)
                          IconButton(
                            tooltip: 'تحميل كل الحلقات',
                            icon: Icon(Icons.download_for_offline_rounded,
                                color: AppColors.accent, size: 24),
                            onPressed: _downloadAll,
                          ),
                        GestureDetector(
                          onTap: () => _pickSeason(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Text(_season,
                                    style: AppText.bodyBold.copyWith(fontSize: 12)),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    size: 17, color: AppColors.sub),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<List<Episode>>(
                      future: _episodesFuture,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Episode>> snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return SizedBox(
                            height: 98,
                            child: Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    color: AppColors.accent, strokeWidth: 2.5),
                              ),
                            ),
                          );
                        }
                        final List<Episode> episodes =
                            snap.data ?? const <Episode>[];
                        if (episodes.isEmpty) {
                          return Container(
                            height: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('الحلقات غير متاحة لهذا العنوان',
                                style: AppText.label.copyWith(fontSize: 12)),
                          );
                        }
                        return SizedBox(
                          height: 148,
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            itemCount: episodes.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 12),
                            itemBuilder: (BuildContext context, int i) {
                              final Episode ep = episodes[i];
                              return GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                    context, '/player',
                                    arguments: (_anime, ep)),
                                child: SizedBox(
                                  width: 172,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 98,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: <Widget>[
                                        PosterImage(
                                          anime: _anime,
                                          radius: 12,
                                          child: Center(
                                            child: Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.8),
                                              ),
                                              child: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 21),
                                            ),
                                          ),
                                        ),
                                        if (_anime.watchId != null)
                                          PositionedDirectional(
                                            top: 0,
                                            end: 0,
                                            child: Container(
                                              margin: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.55),
                                                shape: BoxShape.circle,
                                              ),
                                              child: DownloadIconButton(
                                                downloadKey: _dlKey(ep),
                                                size: 18,
                                                onStart: () =>
                                                    _downloadEpisode(ep),
                                              ),
                                            ),
                                          ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('الحلقة ${ep.number}',
                                          style: AppText.bodyBold
                                              .copyWith(fontSize: 12)),
                                      Text(
                                          ep.duration.isEmpty
                                              ? (ep.hasDub ? 'مترجم • مدبلج' : 'مترجم')
                                              : ep.duration,
                                          style: AppText.label),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    // ---------- More Like This ----------
                    SectionHeader(
                      title: 'أعمال مشابهة',
                      onSeeAll: () => Navigator.pushNamed(context, '/catalog',
                          arguments: (
                            'أعمال مشابهة',
                            _recs.isNotEmpty ? _recs : state.moreLike(_anime.id),
                          )),
                    ),
                    FutureBuilder<List<Anime>>(
                      future: _recsFuture,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Anime>> snap) {
                        final List<Anime> recs =
                            snap.data ?? state.moreLike(_anime.id);
                        if (recs.isEmpty) {
                          return Container(
                            height: 64,
                            alignment: Alignment.center,
                            child: Text('لا شيء هنا بعد',
                                style: AppText.label.copyWith(fontSize: 12)),
                          );
                        }
                        return SizedBox(
                          height: 226,
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            itemCount: recs.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 14),
                            itemBuilder: (BuildContext context, int i) {
                              final Anime other = recs[i];
                              return PosterCard(
                                anime: other,
                                width: 136,
                                height: 190,
                                subtitle:
                                    '★ ${other.score.toStringAsFixed(1)} • ${other.year}',
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pickSeason(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('الحلقات', style: AppText.h3),
        children: <String>['الحلقات', 'مترجم فقط', 'مدبلج فقط']
            .map((String s) => SimpleDialogOption(
                  onPressed: () {
                    setState(() => _season = s);
                    Navigator.pop(ctx);
                  },
                  child: Text(s,
                      style: AppText.bodyBold.copyWith(
                          color: _season == s ? AppColors.accent : AppColors.text)),
                ))
            .toList(),
      ),
    );
  }
}


/// Quick action strip under the Play button: My List status, 10-point
/// rating and share.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.anime});

  final Anime anime;

  String get _key => 'anime:${anime.id}';

  Future<void> _pickStatus(BuildContext context) async {
    final LibraryStore lib = LibraryStore.I;
    final LibStatus? current = lib.entryOf(_key)?.status;
    final LibStatus? picked = await showModalBottomSheet<LibStatus>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('حفظ في…',
                        style: TextStyle(
                            fontFamily: 'Plex',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)))),
            for (final LibStatus s in LibStatus.values)
              ListTile(
                leading: Icon(
                    switch (s) {
                      LibStatus.watching => Icons.visibility_rounded,
                      LibStatus.plan => Icons.bookmark_rounded,
                      LibStatus.done => Icons.check_circle_rounded,
                      LibStatus.hold => Icons.pause_circle_rounded,
                      LibStatus.drop => Icons.remove_circle_outline_rounded,
                    },
                    color:
                        s == current ? AppColors.accent : AppColors.muted),
                title: Text(s.label,
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        color: s == current
                            ? AppColors.accent
                            : AppColors.text)),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger, size: 20),
                title: const Text('إزالة من قائمتي',
                    style: TextStyle(
                        fontFamily: 'Plex',
                        fontSize: 13.5,
                        color: AppColors.danger)),
                onTap: () {
                  lib.removeListEntry(_key);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (picked != null) {
      lib.setListStatus(
        key: _key,
        title: anime.title,
        poster: anime.poster,
        kind: 'anime',
        status: picked,
        meta: '${anime.year.isEmpty ? 'أنمي' : anime.year}'
            '${anime.type.isEmpty ? '' : ' · ${anime.type}'}',
      );
    }
  }

  Future<void> _pickRating(BuildContext context) async {
    final LibraryStore lib = LibraryStore.I;
    int current = lib.ratingOf(_key);
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext bctx, void Function(void Function()) setM) =>
            AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('قيّم هذا العمل',
              style: TextStyle(
                  fontFamily: 'Plex',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                current == 0 ? 'لم يُقيَّم بعد' : '$current / 10',
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 13,
                    color: AppColors.sub),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 280,
                child: Slider(
                  value: current.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$current',
                  activeColor: AppColors.accent,
                  onChanged: (double v) => setM(() => current = v.round()),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 12.5,
                      color: AppColors.sub)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent),
              onPressed: () => Navigator.of(ctx).pop(current),
              child: Text('حفظ',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ),
          ],
        ),
      ),
    );
    if (picked != null) lib.rate(_key, picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LibraryStore.I,
      builder: (BuildContext context, _) {
        final bool listed = LibraryStore.I.isListed(_key);
        final int rating = LibraryStore.I.ratingOf(_key);
        return Row(
          children: <Widget>[
            Expanded(
              child: _QuickAction(
                icon: listed
                    ? Icons.bookmark_added_rounded
                    : Icons.bookmark_add_outlined,
                label: listed ? 'في قائمتي' : 'قائمتي',
                onTap: () => _pickStatus(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: rating > 0
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                label: rating > 0 ? '$rating/10' : 'تقييم',
                onTap: () => _pickRating(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.ios_share_rounded,
                label: 'مشاركة',
                onTap: () async {
                  final String text =
                      'أشاهد ${anime.title} على أنيماكس — تطبيق مجاني للأنمي والأفلام';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'تم نسخ نص المشاركة — الصقه أينما تريد')));
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 19, color: AppColors.accent),
              const SizedBox(height: 5),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sub)),
            ],
          ),
        ),
      ),
    );
  }
}
