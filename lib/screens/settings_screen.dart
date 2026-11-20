import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/app_http.dart';
import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/library_store.dart';

/// Settings hub — Appearance / Player / Comics / Data / About.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingUpdate = false;
  String _updateMessage = '';

  @override
  Widget build(BuildContext context) {
    final AppPrefs p = AppPrefs.I;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: AppColors.bg,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          _section('المظهر'),
          // Accent color picker
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('لون التمييز',
                style: const TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 12.5,
                    color: AppColors.sub)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                for (final AccentTheme a in AccentTheme.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => p.set('accent', a.key),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: a.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: p.accentKey == a.key
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3),
                        ),
                        child: p.accentKey == a.key
                            ? Icon(Icons.check_rounded,
                                color: a.ink, size: 20)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.amoled,
            onChanged: (bool v) => p.set('amoled', v),
            title: const Text('الوضع الأسود AMOLED',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('خلفيات سوداء بالكامل — توفّر البطارية في '
                'شاشات OLED',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.navBadges,
            onChanged: (bool v) => p.set('navBadges', v),
            title: const Text('شارة الحلقات الجديدة على التقويم',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
          ),

          _section('المشغّل'),
          _dropdown('الجودة الافتراضية', <String, String>{
            'auto': 'تلقائي (حسب سرعة الشبكة)',
            '1080': '1080p',
            '720': '720p',
            '480': '480p',
            '360': '360p',
          }, p.defaultQuality, (String v) => p.set('defaultQuality', v)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.autoPlayNext,
            onChanged: (bool v) => p.set('autoPlayNext', v),
            title: const Text('تشغيل الحلقة التالية تلقائيًا',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.autoSkipIntro,
            onChanged: (bool v) => p.set('autoSkipIntro', v),
            title: const Text('تخطّي المقدمة تلقائيًا',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('يتخطى الثواني الأولى تلقائيًا',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('مدة المقدمة',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: Slider(
              value: p.skipIntroSeconds.toDouble(),
              min: 30,
              max: 120,
              divisions: 18,
              label: '${p.skipIntroSeconds} ث',
              activeColor: AppColors.accent,
              onChanged: (double v) =>
                  p.set('skipIntroSec', v.round()),
            ),
            trailing: Text('${p.skipIntroSeconds} ث',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.pauseOnBackground,
            onChanged: (bool v) => p.set('pauseOnBackground', v),
            title: const Text('إيقاف مؤقت عند الخروج من التطبيق',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          _dropdown('سيرفر السينما الافتراضي', <String, String>{
            '': 'تلقائي (بالترتيب)',
            'vidsrc': 'سيرفر 1 · VidSrc',
            'vidfast': 'سيرفر 2 · VidFast',
            'vidlink': 'سيرفر 3 · VidLink',
            'vidsrccc': 'سيرفر 4 · VidSrc CC',
            'twoembed': 'سيرفر 5 · 2Embed',
            'multiembed': 'سيرفر 6 · MultiEmbed',
            'vidsrcxyz': 'سيرفر 7 · VidSrc X',
          }, p.cinemaProvider, (String v) => p.set('cinemaProvider', v)),

          _section('مانغا'),
          _dropdown('لغة القراءة', <String, String>{
            'en': 'الإنجليزية',
            'ar': 'العربية',
            'es': 'الإسبانية',
            'fr': 'الفرنسية',
            'pt-br': 'البرتغالية (البرازيل)',
            'ru': 'الروسية',
            'ja': 'اليابانية',
          }, p.mangaLanguage, (String v) => p.set('mangaLanguage', v)),
          _dropdown('تخطيط القارئ', <String, String>{
            'vertical': 'تمرير عمودي',
            'paged': 'صفحات',
          }, p.readerMode, (String v) => p.set('readerMode', v)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.readerRtl,
            onChanged: (bool v) => p.set('readerRtl', v),
            title: const Text('صفحات من اليمين لليسار (أسلوب المانغا)',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.readerDataSaver,
            onChanged: (bool v) => p.set('readerDataSaver', v),
            title: const Text('توفير بيانات القارئ',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('يحمّل صورًا مضغوطة أصغر للصفحات',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.dataSaver,
            onChanged: (bool v) => p.set('dataSaver', v),
            title: const Text('توفير البيانات العام',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('يفضّل جودة أقل على الشبكات المحدودة',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
          ),

          _section('البيانات'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.ios_share_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('تصدير المكتبة',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('ينسخ نسخة احتياطية JSON إلى الحافظة',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
            onTap: () async {
              final String json = jsonEncode(LibraryStore.I.exportJson());
              await Clipboard.setData(ClipboardData(text: json));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم نسخ النسخة الاحتياطية إلى الحافظة')));
              }
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.paste_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('استيراد المكتبة',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('الصق نسخة احتياطية JSON من الحافظة',
                style: TextStyle(
                    fontFamily: 'Plex', fontSize: 11.5, color: AppColors.muted)),
            onTap: () async {
              final ClipboardData? data =
                  await Clipboard.getData(Clipboard.kTextPlain);
              final String? text = data?.text;
              if (text == null || text.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('الحافظة فارغة')));
                }
                return;
              }
              try {
                final Map<String, dynamic> decoded =
                    jsonDecode(text) as Map<String, dynamic>;
                LibraryStore.I.importJson(decoded);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تم استيراد المكتبة')));
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('هذه ليست نسخة احتياطية من أنيماكس')));
                }
              }
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.delete_sweep_rounded,
                size: 21, color: AppColors.danger),
            title: const Text('مسح سجل المشاهدة',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            onTap: () {
              LibraryStore.I.clearHistory();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم مسح سجل المشاهدة')));
              }
            },
          ),

          _section('حول التطبيق'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: _checkingUpdate
                ? SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.accent))
                : Icon(Icons.system_update_rounded,
                    size: 21, color: AppColors.accent),
            title: const Text('التحقق من التحديثات',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: Text(
                _updateMessage.isEmpty
                    ? 'يقارن هذا الإصدار بآخر إصدار منشور'
                    : _updateMessage,
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 11.5,
                    color: _updateMessage.startsWith('يتوفر تحديث')
                        ? AppColors.accent
                        : AppColors.muted)),
            onTap: _checkForUpdate,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.help_outline_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('مركز المساعدة',
                style: TextStyle(
                    fontFamily: 'Plex',
                    fontSize: 14,
                    color: AppColors.text)),
            trailing: const Icon(Icons.chevron_right_rounded,
                size: 22, color: AppColors.muted),
            onTap: () => Navigator.pushNamed(context, '/help'),
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text('أنيماكس الإصدار 2.0.0 · صُنع بحب للمشاهدين العرب',
                  style: TextStyle(
                      fontFamily: 'Plex',
                      fontSize: 11,
                      color: AppColors.muted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontFamily: 'Plex',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.accent)),
      );

  Widget _dropdown(String label, Map<String, String> options, String current,
      ValueChanged<String> onChanged) {
    // Ensure the current value exists in the option list.
    final Map<String, String> opts = options.containsKey(current)
        ? options
        : <String, String>{current: current, ...options};
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(label,
          style: const TextStyle(
              fontFamily: 'Plex', fontSize: 14, color: AppColors.text)),
      trailing: DropdownButton<String>(
        value: current,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.surface,
        style: TextStyle(
            fontFamily: 'Plex',
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.accent),
        items: opts.entries
            .map((MapEntry<String, String> e) => DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value),
                ))
            .toList(),
        onChanged: (String? v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateMessage = 'جارٍ التحقق…';
    });
    try {
      final http.Response res = await createHttpClient()
          .get(Uri.parse('https://api.github.com/repos/eren-coder07/animax/releases/latest'))
          .timeout(const Duration(seconds: 15));
      // A private repository answers 404 to unauthenticated API calls.
      if (res.statusCode == 404) {
        if (mounted) {
          setState(() {
            _checkingUpdate = false;
            _updateMessage = 'التحقق من التحديثات غير متاح لهذا الإصدار.';
          });
        }
        return;
      }
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final String tag =
          ((jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['tag_name'] ?? '')
              .toString();
      final String current = 'v2.0.0';
      final bool newer = _isNewer(tag, current);
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
          _updateMessage = newer
              ? 'يتوفر تحديث: $tag (المثبّت $current)'
              : 'لديك أحدث إصدار ($current)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
          _updateMessage = 'تعذّر التحقق من التحديثات — تحقّق من اتصالك.';
        });
      }
    }
  }

  static bool _isNewer(String tag, String current) {
    final List<int> a = tag
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((String s) => int.tryParse(s) ?? 0)
        .toList();
    final List<int> b = current
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((String s) => int.tryParse(s) ?? 0)
        .toList();
    for (int i = 0; i < 3; i++) {
      final int x = i < a.length ? a[i] : 0;
      final int y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
