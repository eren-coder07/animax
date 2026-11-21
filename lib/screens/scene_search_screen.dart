import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_data.dart';
import '../core/app_theme.dart';
import '../core/scene_search.dart';
import '../widgets/mb_ui.dart' show kFont, GradientButton, NetImage;

/// «ابحث بالمشهد»: pick a screenshot → anime, episode and second → play
/// from exactly that moment.
class SceneSearchScreen extends StatefulWidget {
  const SceneSearchScreen({super.key});

  @override
  State<SceneSearchScreen> createState() => _SceneSearchScreenState();
}

class _SceneSearchScreenState extends State<SceneSearchScreen> {
  Uint8List? _image;
  List<SceneMatch>? _results;
  String? _error;
  bool _busy = false;
  String _opening = '';

  Future<void> _pick() async {
    final Uint8List? img = await SceneSearch.pickImage();
    if (img == null || !mounted) return;
    setState(() {
      _image = img;
      _results = null;
      _error = null;
      _busy = true;
    });
    try {
      final List<SceneMatch> r = await SceneSearch.search(img);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is SceneSearchException
              ? e.message
              : 'تعذّر الاتصال بخدمة البحث — تحقّق من الإنترنت.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _fmt(double s) {
    final int t = s.floor(), m = t ~/ 60, ss = t % 60, h = m ~/ 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m % 60)}:${two(ss)}' : '${two(m)}:${two(ss)}';
  }

  Future<void> _watch(SceneMatch m) async {
    setState(() => _opening = '${m.title}#${m.episode}');
    final ScaffoldMessengerState msg = ScaffoldMessenger.of(context);
    final NavigatorState nav = Navigator.of(context);
    try {
      final Anime? a = await SceneSearch.findInCatalog(m);
      if (a == null || a.watchId == null) {
        msg.showSnackBar(
          SnackBar(
            content: Text('«${m.title}» غير متوفر في مكتبة الأنمي لدينا.'),
          ),
        );
        return;
      }
      Episode? ep;
      try {
        final List<Episode> eps = await ApiService.I.fetchEpisodes(a.watchId!);
        for (final Episode e in eps) {
          if (e.number == m.episode) ep = e;
        }
      } catch (_) {}
      await nav.pushNamed(
        '/player',
        arguments: (a, ep, Duration(milliseconds: (m.from * 1000).round())),
      );
    } finally {
      if (mounted) setState(() => _opening = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('ابحث بالمشهد'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'التقط صورة شاشة من أي أنمي (أو اختر صورة من معرضك) وسنعرف اسم الأنمي والحلقة والثانية بالضبط — ثم نشغّله لك من تلك اللحظة.',
            style: TextStyle(
              fontFamily: kFont,
              fontSize: 14.5,
              height: 1.6,
              color: AppColors.sub,
            ),
          ),
          const SizedBox(height: 14),
          GradientButton(
            key: const Key('pickScene'),
            label: _image == null ? 'اختر لقطة شاشة' : 'اختر صورة أخرى',
            icon: Icons.image_search_rounded,
            height: 50,
            expand: true,
            onTap: _busy ? null : _pick,
          ),
          if (_image != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(_image!, height: 180, fit: BoxFit.cover),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: <Widget>[
                  CircularProgressIndicator(color: AppColors.brandGreen),
                  SizedBox(height: 10),
                  Text(
                    'نبحث في ملايين اللقطات…',
                    style: TextStyle(fontFamily: kFont, color: AppColors.sub),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: kFont,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            ),
          if (_results != null && _results!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'لم نجد هذا المشهد. جرّب لقطة أوضح بدون ترجمة كبيرة على الصورة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kFont, color: AppColors.sub),
              ),
            ),
          for (final SceneMatch m in _results ?? const <SceneMatch>[])
            Container(
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (m.preview.isNotEmpty)
                    SizedBox(height: 160, child: NetImage(m.preview)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          m.title,
                          style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (m.altTitle.isNotEmpty && m.altTitle != m.title)
                          Text(
                            m.altTitle,
                            style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 12.5,
                              color: AppColors.sub,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'الحلقة ${m.episode} · عند ${_fmt(m.from)} · تطابق ${(m.similarity * 100).toStringAsFixed(0)}%'
                          '${m.similarity < SceneSearch.sureSimilarity ? ' (غير مؤكد)' : ''}',
                          style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 13.5,
                            color: m.similarity >= SceneSearch.sureSimilarity
                                ? AppColors.brandGreen
                                : const Color(0xFFFFB020),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _opening.isNotEmpty
                              ? null
                              : () => _watch(m),
                          icon: _opening == '${m.title}#${m.episode}'
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'شاهد من هذه اللحظة',
                            style: TextStyle(fontFamily: kFont),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'تعمل مع الأنمي فقط. لا تُحفظ صورتك — تُرسل مصغّرة للبحث ثم تُنسى.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kFont,
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
