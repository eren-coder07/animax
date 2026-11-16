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
        title: const Text('Settings'),
        backgroundColor: AppColors.bg,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          _section('Appearance'),
          // Accent color picker
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('Accent color',
                style: const TextStyle(
                    fontFamily: 'Poppins',
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
            title: const Text('AMOLED black theme',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('True black backgrounds — saves battery on '
                'OLED screens',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.navBadges,
            onChanged: (bool v) => p.set('navBadges', v),
            title: const Text('New-episode badge on Calendar',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
          ),

          _section('Player'),
          _dropdown('Default quality', <String, String>{
            'auto': 'Auto (network speed)',
            '1080': '1080p',
            '720': '720p',
            '480': '480p',
            '360': '360p',
          }, p.defaultQuality, (String v) => p.set('defaultQuality', v)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.autoPlayNext,
            onChanged: (bool v) => p.set('autoPlayNext', v),
            title: const Text('Auto-play next episode',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.autoSkipIntro,
            onChanged: (bool v) => p.set('autoSkipIntro', v),
            title: const Text('Auto-skip intro',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('Skips the first seconds automatically',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Intro length',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: Slider(
              value: p.skipIntroSeconds.toDouble(),
              min: 30,
              max: 120,
              divisions: 18,
              label: '${p.skipIntroSeconds}s',
              activeColor: AppColors.accent,
              onChanged: (double v) =>
                  p.set('skipIntroSec', v.round()),
            ),
            trailing: Text('${p.skipIntroSeconds}s',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.pauseOnBackground,
            onChanged: (bool v) => p.set('pauseOnBackground', v),
            title: const Text('Pause when app is in background',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          _dropdown('Cinema default server', <String, String>{
            '': 'Auto (fallback order)',
            'vidsrc': 'Server 1 · VidSrc',
            'vidfast': 'Server 2 · VidFast',
            'vidlink': 'Server 3 · VidLink',
            'vidsrccc': 'Server 4 · VidSrc CC',
            'twoembed': 'Server 5 · 2Embed',
            'multiembed': 'Server 6 · MultiEmbed',
            'vidsrcxyz': 'Server 7 · VidSrc X',
          }, p.cinemaProvider, (String v) => p.set('cinemaProvider', v)),

          _section('Comics'),
          _dropdown('Reader language', <String, String>{
            'en': 'English',
            'ar': 'Arabic',
            'es': 'Spanish',
            'fr': 'French',
            'pt-br': 'Portuguese (BR)',
            'ru': 'Russian',
            'ja': 'Japanese',
          }, p.mangaLanguage, (String v) => p.set('mangaLanguage', v)),
          _dropdown('Reader layout', <String, String>{
            'vertical': 'Vertical scroll',
            'paged': 'Paged',
          }, p.readerMode, (String v) => p.set('readerMode', v)),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.readerRtl,
            onChanged: (bool v) => p.set('readerRtl', v),
            title: const Text('Right-to-left pages (manga style)',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.readerDataSaver,
            onChanged: (bool v) => p.set('readerDataSaver', v),
            title: const Text('Reader data saver',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('Loads smaller compressed page images',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: p.dataSaver,
            onChanged: (bool v) => p.set('dataSaver', v),
            title: const Text('Global data saver',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('Prefers lower quality on metered networks',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
          ),

          _section('Data'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.ios_share_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('Export library',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('Copies a JSON backup to the clipboard',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
            onTap: () async {
              final String json = jsonEncode(LibraryStore.I.exportJson());
              await Clipboard.setData(ClipboardData(text: json));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Library backup copied to clipboard')));
              }
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.paste_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('Import library',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: const Text('Paste a JSON backup from the clipboard',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted)),
            onTap: () async {
              final ClipboardData? data =
                  await Clipboard.getData(Clipboard.kTextPlain);
              final String? text = data?.text;
              if (text == null || text.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Clipboard is empty')));
                }
                return;
              }
              try {
                final Map<String, dynamic> decoded =
                    jsonDecode(text) as Map<String, dynamic>;
                LibraryStore.I.importJson(decoded);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Library imported')));
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('That does not look like an Animax backup')));
                }
              }
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.delete_sweep_rounded,
                size: 21, color: AppColors.danger),
            title: const Text('Clear watch history',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            onTap: () {
              LibraryStore.I.clearHistory();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Watch history cleared')));
              }
            },
          ),

          _section('About'),
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
            title: const Text('Check for updates',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            subtitle: Text(
                _updateMessage.isEmpty
                    ? 'Compares this build against the latest GitHub release'
                    : _updateMessage,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: _updateMessage.startsWith('Update available')
                        ? AppColors.accent
                        : AppColors.muted)),
            onTap: _checkForUpdate,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.build_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('API backend',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            trailing: const Icon(Icons.chevron_right_rounded,
                size: 22, color: AppColors.muted),
            onTap: () => Navigator.pushNamed(context, '/backend'),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.help_outline_rounded,
                size: 21, color: AppColors.accent),
            title: const Text('Help center',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: AppColors.text)),
            trailing: const Icon(Icons.chevron_right_rounded,
                size: 22, color: AppColors.muted),
            onTap: () => Navigator.pushNamed(context, '/help'),
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text('Animax v1.9.0 (10) · built for the love of anime',
                  style: TextStyle(
                      fontFamily: 'Poppins',
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
                fontFamily: 'Poppins',
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
              fontFamily: 'Poppins', fontSize: 14, color: AppColors.text)),
      trailing: DropdownButton<String>(
        value: current,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.surface,
        style: TextStyle(
            fontFamily: 'Poppins',
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
      _updateMessage = 'Checking…';
    });
    try {
      final http.Response res = await createHttpClient()
          .get(Uri.parse('https://api.github.com/repos/eren-coder07/animax/releases/latest'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final String tag =
          ((jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['tag_name'] ?? '')
              .toString();
      final String current = 'v1.9.0';
      final bool newer = _isNewer(tag, current);
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
          _updateMessage = newer
              ? 'Update available: $tag (installed $current)'
              : 'You are on the latest version ($current)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
          _updateMessage = 'Could not check — $e';
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
