import 'package:flutter/material.dart';

import '../core/api_config.dart';
import '../core/api_service.dart';
import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';

/// Profile → API Backend.
///
/// Lets the user point the app at their REST backend without touching code:
/// base URL + optional auth, endpoint path overrides, connection test with
/// per-endpoint results, and a switch back to demo mode.
class BackendSettingsScreen extends StatefulWidget {
  const BackendSettingsScreen({super.key});

  @override
  State<BackendSettingsScreen> createState() => _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends State<BackendSettingsScreen> {
  late final TextEditingController _base =
      TextEditingController(text: ApiService.I.config.baseUrl);
  late final TextEditingController _token =
      TextEditingController(text: ApiService.I.config.authToken);
  late final TextEditingController _keyName =
      TextEditingController(text: ApiService.I.config.apiKeyHeader);
  late final TextEditingController _keyValue =
      TextEditingController(text: ApiService.I.config.apiKeyValue);
  late final TextEditingController _catalogPath =
      TextEditingController(text: ApiService.I.config.trendingPath);
  late final TextEditingController _calendarPath =
      TextEditingController(text: ApiService.I.config.episodesPath);
  late final TextEditingController _favoritesPath =
      TextEditingController(text: ApiService.I.config.serversPath);
  late final TextEditingController _loginPath =
      TextEditingController(text: ApiService.I.config.userPanelPath);
  late final TextEditingController _searchPath =
      TextEditingController(text: ApiService.I.config.searchPath);

  bool _busy = false;
  bool _showToken = false;
  bool _advanced = false;
  List<ProbeResult> _results = const <ProbeResult>[];

  AppState get state => AppState.I;

  @override
  void dispose() {
    _base.dispose();
    _token.dispose();
    _keyName.dispose();
    _keyValue.dispose();
    _catalogPath.dispose();
    _calendarPath.dispose();
    _favoritesPath.dispose();
    _loginPath.dispose();
    _searchPath.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    if (_busy) return;
    final String url = _base.text.trim();
    if (url.isEmpty) {
      _toast('Enter your backend base URL first');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _toast('URL must start with http:// or https://');
      return;
    }
    setState(() => _busy = true);

    final ApiConfig config = ApiConfig(
      baseUrl: url,
      authToken: _token.text.trim(),
      apiKeyHeader: _keyName.text.trim(),
      apiKeyValue: _keyValue.text.trim(),
      trendingPath: ApiConfig.normalizePath(_catalogPath.text),
      episodesPath: ApiConfig.normalizePath(_calendarPath.text),
      serversPath: ApiConfig.normalizePath(_favoritesPath.text),
      userPanelPath: ApiConfig.normalizePath(_loginPath.text),
      searchPath: ApiConfig.normalizePath(_searchPath.text),
    );
    ApiService.I.updateConfig(config);
    await config.save();

    final List<ProbeResult> results = await ApiService.I.probe();
    if (!mounted) return;
    setState(() {
      _results = results;
      _busy = false;
    });
    await state.refreshFromApi();
    if (!mounted) return;
    _toast(state.backendMessage);
  }

  Future<void> _reloadData() async {
    if (_busy) return;
    if (!ApiService.I.config.isConfigured) {
      _toast('Connect a backend first');
      return;
    }
    setState(() => _busy = true);
    await state.refreshFromApi(withSchedule: true);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(state.backendMessage);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (BuildContext context, _) => ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Row(
                children: [
                  IconBubble(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  const Text('API Backend', style: AppText.h3),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 20),

              // ----- Status card -----
              _StatusCard(
                mode: state.backendChip,
                message: state.backendMessage,
                lastSync: state.lastSyncAt,
              ),
              const SizedBox(height: 20),

              // ----- Connection fields -----
              _SectionLabel('Connection'),
              FieldBox(
                hint: 'Base URL  e.g. https://api.myserver.com',
                icon: Icons.dns_rounded,
                controller: _base,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              FieldBox(
                hint: 'Bearer token (optional)',
                icon: Icons.key_rounded,
                controller: _token,
                obscure: !_showToken,
                suffix: IconButton(
                  icon: Icon(
                    _showToken
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.muted,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FieldBox(
                      hint: 'API key header (optional)',
                      icon: Icons.badge_outlined,
                      controller: _keyName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FieldBox(
                      hint: 'API key value',
                      icon: Icons.vpn_key_outlined,
                      controller: _keyValue,
                      obscure: !_showToken,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ----- Advanced endpoint overrides -----
              GestureDetector(
                onTap: () => setState(() => _advanced = !_advanced),
                child: Row(
                  children: [
                    Icon(_advanced
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                        size: 20, color: AppColors.muted),
                    const SizedBox(width: 6),
                    const Text('Endpoint path overrides',
                        style: AppText.bodyBold),
                    const Spacer(),
                    Text('optional', style: AppText.label.copyWith(fontSize: 10.5)),
                  ],
                ),
              ),
              if (_advanced) ...[
                const SizedBox(height: 12),
                _PathField(
                    label: 'Trending', hint: '/ajax/v2/trending',
                    controller: _catalogPath),
                const SizedBox(height: 10),
                _PathField(
                    label: 'Episode list', hint: '/ajax/episode/list',
                    controller: _calendarPath),
                const SizedBox(height: 10),
                _PathField(
                    label: 'Server list', hint: '/ajax/server/list',
                    controller: _favoritesPath),
                const SizedBox(height: 10),
                _PathField(
                    label: 'User panel', hint: '/ajax/user/panel',
                    controller: _loginPath),
                const SizedBox(height: 10),
                _PathField(
                    label: 'Search', hint: '/filter?keyword=',
                    controller: _searchPath),
              ],
              const SizedBox(height: 22),

              // ----- Actions -----
              PrimaryButton(
                label: _busy ? 'Testing…' : 'Save & Test Connection',
                expanded: true,
                onTap: _busy ? null : _saveAndTest,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GhostChip(
                  label: 'Reload data',
                  active: false,
                  onTap: _busy ? null : _reloadData,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),

              // ----- Probe results -----
              if (_results.isNotEmpty) ...[
                const _SectionLabel('Connection test'),
                ..._results.map((ProbeResult r) => _ProbeTile(result: r)),
                const SizedBox(height: 24),
              ],

              // ----- JSON contract -----
              const _SectionLabel('Expected JSON shape'),
              const _ContractCard(),
              const SizedBox(height: 10),
              Text(
                'Field names are flexible — the app also accepts image / cover / '
                'thumbnail for posters, score / rating / vote_average for scores, '
                '{data: [...]} envelopes, weekday or date keys on the calendar, '
                'and relative image paths resolved against your base URL.',
                style: AppText.label.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: AppText.h3.copyWith(fontSize: 14)),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.mode, required this.message, this.lastSync});
  final String mode;
  final String message;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final bool live = mode == 'LIVE';
    final bool bad = mode == 'OFFLINE';
    final Color accent = live ? AppColors.green : (bad ? Colors.redAccent : AppColors.muted);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              live ? Icons.cloud_done_rounded : bad ? Icons.cloud_off_rounded : Icons.cloud_queue_rounded,
              color: accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode == 'SYNC…' ? 'Syncing' : (live ? 'Connected' : 'Offline'),
                    style: AppText.bodyBold.copyWith(fontSize: 14, color: accent)),
                const SizedBox(height: 2),
                Text(message, style: AppText.label.copyWith(fontSize: 11), maxLines: 2),
                if (lastSync != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Last sync ${lastSync!.hour.toString().padLeft(2, '0')}:${lastSync!.minute.toString().padLeft(2, '0')}',
                      style: AppText.label.copyWith(fontSize: 10, color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({required this.label, required this.hint, required this.controller});
  final String label;
  final String hint;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label, style: AppText.label.copyWith(fontSize: 11.5)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.muted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.stroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.green, width: 1.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProbeTile extends StatelessWidget {
  const _ProbeTile({required this.result});
  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            result.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: result.ok ? AppColors.green : Colors.redAccent,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(result.label,
                style: AppText.bodyBold.copyWith(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              result.ok ? '${result.path} — ${result.detail}' : result.detail,
              style: AppText.label.copyWith(fontSize: 10.5),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard();

  @override
  Widget build(BuildContext context) {
    const String code = 'Base  https://aniwaves.ru  (AJAX, JSON envelopes)\n'
        '\n'
        'GET /filter?keyword={query}        ← search (HTML cards)\n'
        'GET /ajax/v2/trending?mov_id={id}\n'
        '{ "status": 200, "html": "<a class=item href=…>" }\n'
        '\n'
        'GET /ajax/episode/list/{id}?vrf=\n'
        '{ "status": 200, "result": "<li data-num=1 …>" }\n'
        '\n'
        'GET /ajax/server/list?servers={id}&eps={ep}\n'
        '{ "status": 200, "result": "<li data-sv-id=…>Name</li>" }\n'
        '\n'
        'Playback  /ajax/sources?id={linkId}  → embed URL\n'
        '  → {embedBase}/getSources?id={token}\n'
        '  → {"sources": "https://…m3u8" | {"HD": [mp4]}}\n'
        '\n'
        'GET /ajax/schedule/date?date=YYYY-MM-DD\n'
        'GET /ajax/anime/views/{id}   /ajax/v2/recommendations\n'
        'Watch page  /watch/{slug}  → details scraped from HTML';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: const Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          height: 1.5,
          color: AppColors.sub,
        ),
      ),
    );
  }
}
