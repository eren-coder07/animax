import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/library_store.dart';
import '../widgets/common.dart';

/// Personal library — My List (status buckets), watch history and stats.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('مكتبتي'),
        backgroundColor: AppColors.bg,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.text,
          unselectedLabelColor: AppColors.muted,
          labelStyle:
              const TextStyle(fontFamily: 'Plex', fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: const <Tab>[
            Tab(text: 'قائمتي'),
            Tab(text: 'السجل'),
            Tab(text: 'الإحصاءات'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: LibraryStore.I,
        builder: (BuildContext context, _) => TabBarView(
          controller: _tabs,
          children: <Widget>[
            _buildMyList(),
            _buildHistory(),
            _buildStats(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ list

  Widget _buildMyList() {
    final List<LibEntry> entries = LibraryStore.I.allEntries
        .where((LibEntry e) => e.inList)
        .toList();
    if (entries.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.bookmark_border_rounded,
          title: 'قائمتك فارغة',
          message:
              'اضغط على أيقونة الحفظ في أي فيلم أو مسلسل أو مانغا '
              'لمتابعته هنا.',
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.58,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14),
      itemCount: entries.length,
      itemBuilder: (BuildContext c, int i) {
        final LibEntry e = entries[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: e.poster.startsWith('http')
                        ? Image.network(e.poster,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                                color: AppColors.surfaceHi))
                        : ColoredBox(color: AppColors.surfaceHi),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () {
                        LibraryStore.I.removeListEntry(e.key);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                  if (e.status != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 3, horizontal: 6),
                        color: Colors.black.withValues(alpha: 0.65),
                        child: Text(
                          e.status!.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Plex',
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            if (e.rating > 0)
              Row(
                children: <Widget>[
                  const Icon(Icons.star_rounded,
                      size: 11, color: AppColors.amber),
                  const SizedBox(width: 2),
                  Text('${e.rating}/10',
                      style: const TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 10,
                          color: AppColors.muted)),
                ],
              ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- history

  Widget _buildHistory() {
    final List<HistoryRow> rows = LibraryStore.I.history;
    if (rows.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.history_rounded,
          title: 'لا يوجد سجل بعد',
          message: 'كل ما تشاهده أو تقرأه يظهر هنا لتعود إليه '
              'فورًا.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext c, int i) {
        final HistoryRow r = rows[i];
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 42,
                      height: 58,
                      child: r.poster.startsWith('http')
                          ? Image.network(r.poster,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  ColoredBox(color: AppColors.surfaceHi))
                          : ColoredBox(color: AppColors.surfaceHi),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Plex',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text)),
                        const SizedBox(height: 3),
                        Text('${r.label} · ${_ago(r.at)}',
                            style: const TextStyle(
                                fontFamily: 'Plex',
                                fontSize: 10.5,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(_kindLabel(r.kind),
                      style: TextStyle(
                          fontFamily: 'Plex',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------------- stats

  Widget _buildStats() {
    final ({int episodesWatched, int chaptersRead, int titlesTracked,
            double hoursWatched, int activeDays}) s =
        LibraryStore.I.stats();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            _statCard('حلقات\nمُشاهدة', s.episodesWatched.toString(),
                Icons.play_circle_outline_rounded),
            const SizedBox(width: 12),
            _statCard('فصول\nمقروءة', s.chaptersRead.toString(),
                Icons.menu_book_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _statCard('أعمال\nمتابَعة', s.titlesTracked.toString(),
                Icons.bookmark_rounded),
            const SizedBox(width: 12),
            _statCard('ساعات\nمشاهدة', s.hoursWatched.toStringAsFixed(1),
                Icons.schedule_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _statCard('أيام\nنشاط', s.activeDays.toString(),
                Icons.local_fire_department_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.insights_rounded,
                        size: 22, color: AppColors.accent),
                    const SizedBox(height: 8),
                    Text('واصل المشاهدة!',
                        style: const TextStyle(
                            fontFamily: 'Plex',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text)),
                    const SizedBox(height: 4),
                    Text(
                        s.hoursWatched > 24
                            ? 'هذا أكثر من يوم كامل من المشاهدة.'
                            : 'إحصاءاتك تنمو مع كل حلقة.',
                        style: const TextStyle(
                            fontFamily: 'Plex',
                            fontSize: 10.5,
                            color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 22, color: AppColors.accent),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 10.5,
                    height: 1.3,
                    color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
        'manga' => 'مانغا',
        'cinema' => 'سينما',
        'cartoon' => 'كرتون',
        'akwam' => 'أكوام',
        _ => 'أنمي',
      };

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} د';
    if (d.inHours < 24) return 'منذ ${d.inHours} س';
    if (d.inDays < 30) return 'منذ ${d.inDays} يوم';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}'
        '-${at.day.toString().padLeft(2, '0')}';
  }
}
