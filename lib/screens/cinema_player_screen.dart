import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/cinema_api.dart';
import '../core/cinema_providers.dart';
import '../core/library_store.dart';

/// Fullscreen WebView player for the Cinema section — multi-server edition.
///
/// One title plays through up to 7 independent embed servers. If a server
/// serves a bot-verification page ("Verification failed"), an error page or
/// simply never renders a video, the player detects it and silently falls
/// back to the next server; a manual server picker is always available too.
///
/// The `animaxBridge` JS channel receives:
///  * probe results (`bad` / `video` / `iframe`) for server health,
///  * provider `postMessage` events (`ended`) for auto-next-episode.
class CinemaPlayerScreen extends StatefulWidget {
  const CinemaPlayerScreen({
    super.key,
    required this.meta,
    this.season = 0,
    this.episode = 0,
    this.episodeName = '',
  })  : _directUrl = null,
        _directTitle = null;

  /// Opens an arbitrary URL (used for YouTube trailers).
  const CinemaPlayerScreen.direct({
    super.key,
    required String url,
    required String title,
  })  : meta = null,
        season = 0,
        episode = 0,
        episodeName = '',
        _directUrl = url,
        _directTitle = title;

  final CinemaMeta? meta;
  final int season;
  final int episode;
  final String episodeName;

  final String? _directUrl;
  final String? _directTitle;

  @override
  State<CinemaPlayerScreen> createState() => _CinemaPlayerScreenState();
}

class _CinemaPlayerScreenState extends State<CinemaPlayerScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  Timer? _probeTimer;
  Timer? _graceTimer;
  Timer? _nextTimer;

  bool _loading = true;
  bool _failed = false;
  bool _playing = false; // probe saw a real <video>
  int _loadPct = 0;
  int _attempts = 0; // servers tried this session
  int _providerIdx = 0;
  String? _probeText;

  bool get _isTrailer => widget._directUrl != null;

  String get _key {
    final CinemaMeta? m = widget.meta;
    return m == null ? '' : 'cinema:${m.id}';
  }

  String get _title {
    final String? direct = widget._directTitle;
    if (direct != null) return direct;
    final CinemaMeta? m = widget.meta;
    if (m == null) return 'سينما';
    if (widget.episode > 0) {
      final String ep = widget.episodeName.isEmpty
          ? 'الحلقة ${widget.episode}'
          : widget.episodeName;
      return '${m.name} — S${widget.season} · $ep';
    }
    return m.name;
  }

  CinemaProvider get _provider => cinemaProviders[_providerIdx];

  String _urlFor(CinemaProvider p) {
    final CinemaMeta? m = widget.meta;
    if (_isTrailer || m == null) return widget._directUrl ?? 'about:blank';
    if (widget.episode > 0) {
      return p.buildTv(
            imdbId: m.id,
            tmdbId: m.tmdbId.isEmpty ? null : m.tmdbId,
            season: widget.season,
            episode: widget.episode,
          ) ??
          cinemaProviders[0].buildTv(
              imdbId: m.id,
              season: widget.season,
              episode: widget.episode)!;
    }
    return p.buildMovie(m.id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _setKeepScreenOn(true);

    // Start from the user's preferred server (Settings → Player), then fall
    // back in the verified order.
    final String preferred = AppPrefs.I.cinemaProvider;
    int idx = 0;
    if (preferred.isNotEmpty) {
      for (int i = 0; i < cinemaProviders.length; i++) {
        if (cinemaProviders[i].id == preferred) {
          idx = i;
          break;
        }
      }
    }
    _providerIdx = idx;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(CinemaPlayback.ua)
      ..addJavaScriptChannel('animaxBridge',
          onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (NavigationRequest req) {
          final Uri? uri = Uri.tryParse(req.url);
          if (uri == null || !uri.hasScheme) return NavigationDecision.prevent;
          if (uri.scheme == 'http' ||
              uri.scheme == 'https' && !isCinemaAllowedHost(uri.host)) {
            // Popunders / ad redirects — never leave the player.
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onProgress: (int p) {
          if (!mounted) return;
          setState(() => _loadPct = p);
          if (p >= 100) {
            _injectPump();
            _armProbes();
          }
        },
        onPageFinished: (_) {
          _injectPump();
          _armProbes();
        },
        onWebResourceError: (_) => _armProbes(),
      ))
      ..loadRequest(Uri.parse(_urlFor(_provider)));
    _armGrace();
  }

  void _onBridgeMessage(JavaScriptMessage msg) {
    final String raw = msg.message;
    if (raw.isEmpty) return;
    try {
      final Map<String, dynamic> d =
          Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>);
      if (d['event'] == 'ended') {
        _handleEnded();
        return;
      }
      final bool bad = d['bad'] == true;
      final bool video = d['video'] == true;
      final String text = (d['text'] ?? '').toString();
      if (!mounted) return;
      if (video && !_playing) {
        // A real video element is up — this server works.
        setState(() {
          _playing = true;
          _loading = false;
          _failed = false;
        });
        _stopProbes();
        _recordStart();
        return;
      }
      if (bad) {
        _probeText = text.isEmpty ? 'فشل التحقق من السيرفر' : text;
        _switchServer(reason: 'فشل التحقق');
      }
    } catch (_) {
      // Non-JSON messages from the page are ignored.
    }
  }

  void _injectPump() {
    _controller.runJavaScript(messagePumpJs).catchError((Object e) => '');
    _controller.runJavaScript(verificationProbeJs).catchError((Object e) => '');
  }

  void _armProbes() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final Object? r =
            await _controller.runJavaScriptReturningResult(verificationProbeJs);
        final String s = r.toString();
        final Map<String, dynamic> d =
            Map<String, dynamic>.from(jsonDecode(s) as Map<String, dynamic>);
        if (!mounted) return;
        final bool video = d['video'] == true;
        final bool iframe = d['iframe'] == true;
        final bool bad = d['bad'] == true;
        if (video && !_playing) {
          setState(() {
            _playing = true;
            _loading = false;
            _failed = false;
          });
          _stopProbes();
          _recordStart();
        } else if (bad && !_playing) {
          _probeText = (d['text'] ?? '').toString();
          _switchServer(reason: 'فشل التحقق');
        } else if (!video && !iframe && !_playing && !_loading) {
          // Page settled into an empty shell — treat as dead server.
          _switchServer(reason: 'المشغّل فارغ');
        }
      } catch (_) {
        // Probe races with navigation; ignore.
      }
    });
  }

  void _armGrace() {
    _graceTimer?.cancel();
    _graceTimer = Timer(const Duration(seconds: 14), () {
      if (!mounted || _playing) return;
      _switchServer(reason: 'لا توجد إشارة فيديو');
    });
  }

  void _stopProbes() {
    _probeTimer?.cancel();
    _graceTimer?.cancel();
  }

  void _switchServer({String reason = 'خطأ في السيرفر'}) {
    if (!mounted || _isTrailer) return;
    _stopProbes();
    _attempts++;
    if (_attempts >= cinemaProviders.length) {
      // Every server failed this session.
      setState(() {
        _loading = false;
        _failed = true;
        _playing = false;
      });
      return;
    }
    _providerIdx = (_providerIdx + 1) % cinemaProviders.length;
    // Skip providers whose TV template needs a TMDB id we don't have.
    if (widget.episode > 0 && _provider.needsTmdbForTv && _noTmdb) {
      _providerIdx = (_providerIdx + 1) % cinemaProviders.length;
    }
    setState(() {
      _loading = true;
      _loadPct = 0;
      _playing = false;
    });
    _controller.loadRequest(Uri.parse(_urlFor(_provider)));
    _armGrace();
  }

  bool get _noTmdb {
    final CinemaMeta? m = widget.meta;
    return m == null || m.tmdbId.isEmpty;
  }

  void _useServer(int idx) {
    if (!mounted) return;
    Navigator.of(context).pop(); // close the sheet if open
    _stopProbes();
    _attempts = 0;
    _providerIdx = idx;
    AppPrefs.I.set('cinemaProvider', _provider.id);
    setState(() {
      _loading = true;
      _loadPct = 0;
      _playing = false;
      _failed = false;
    });
    _controller.loadRequest(Uri.parse(_urlFor(_provider)));
    _armGrace();
  }

  // ------------------------------------------------------------- progress

  void _recordStart() {
    if (_key.isEmpty) return;
    final CinemaMeta? m = widget.meta;
    LibraryStore.I.pushHistory(
      key: _key,
      title: m?.name ?? widget._directTitle ?? 'سينما',
      poster: m?.poster ?? '',
      kind: m?.isSeries == true ? 'cinema' : 'cinema',
      sub: widget.episode > 0 ? 'S${widget.season}E${widget.episode}' : 'movie',
      label: widget.episode > 0
          ? 'S${widget.season} · E${widget.episode}'
          : 'فيلم',
    );
  }

  void _handleEnded() {
    if (_key.isEmpty) return;
    LibraryStore.I.markWatched(_key,
        widget.episode > 0 ? 'S${widget.season}E${widget.episode}' : 'movie',
        watched: true);
    _maybeAutoNext();
  }

  void _maybeAutoNext() {
    final CinemaMeta? m = widget.meta;
    if (m == null || widget.episode == 0 || !AppPrefs.I.autoPlayNext) return;
    // Find the next episode within the same season.
    CinemaEpisode target = m.episodes.firstWhere(
      (CinemaEpisode e) =>
          e.season == widget.season && e.number == widget.episode + 1,
      orElse: () => m.episodes.isEmpty
          ? CinemaEpisode(
              season: 0, number: 0, name: '', overview: '', thumbnail: '',
              released: '')
          : m.episodes.first,
    );
    if (target.number != widget.episode + 1) return;
    _nextTimer?.cancel();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _NextEpisodeDialog(
        title: target.name.isEmpty ? 'الحلقة ${target.number}' : target.name,
        seconds: 10,
        onPlay: () {
          _nextTimer?.cancel();
          Navigator.of(ctx).pop();
          _loadEpisode(widget.season, widget.episode + 1,
              name: target.name);
        },
        onCancel: () {
          _nextTimer?.cancel();
          Navigator.of(ctx).pop();
        },
      ),
    );
    _nextTimer = Timer(const Duration(seconds: 10), () {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      _loadEpisode(widget.season, widget.episode + 1, name: target.name);
    });
  }

  void _loadEpisode(int season, int episode, {String name = ''}) {
    _stopProbes();
    _attempts = 0;
    setState(() {
      _loading = true;
      _loadPct = 0;
      _playing = false;
      _failed = false;
    });
    final String url = _provider.buildTv(
          imdbId: widget.meta!.id,
          tmdbId: _noTmdb ? null : widget.meta!.tmdbId,
          season: season,
          episode: episode,
        ) ??
        cinemaProviders[0]
            .buildTv(imdbId: widget.meta!.id, season: season, episode: episode)!;
    _controller.loadRequest(Uri.parse(url));
    _armGrace();
  }

  // ------------------------------------------------------------ lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause embed media when backgrounded (WebView keeps playing otherwise).
    if (state == AppLifecycleState.paused &&
        AppPrefs.I.pauseOnBackground) {
      _controller.runJavaScript(
          'document.querySelectorAll("video,audio").forEach(v=>v.pause());')
          .catchError((Object e) => '');
    }
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    _graceTimer?.cancel();
    _nextTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _setKeepScreenOn(false);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _setKeepScreenOn(bool keep) {
    const MethodChannel ch = MethodChannel('animax/app');
    ch.invokeMethod<bool>('setKeepScreenOn', <String, dynamic>{'keep': keep})
        .catchError((Object e) => false);
  }

  void _reload() {
    setState(() {
      _failed = false;
      _loading = true;
      _loadPct = 0;
      _playing = false;
      _attempts = 0;
    });
    _controller.loadRequest(Uri.parse(_urlFor(_provider)));
    _armGrace();
  }

  void _openServerSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('سيرفرات البث',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'اختر سيرفرًا إذا توقّف التشغيل. ينتقل المشغّل '
                'تلقائيًا إلى سيرفر آخر عند الفشل.',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 11.5, color: AppColors.sub),
              ),
            ),
            for (int i = 0; i < cinemaProviders.length; i++)
              ListTile(
                leading: Icon(
                  i == _providerIdx
                      ? Icons.play_circle_fill_rounded
                      : Icons.play_circle_outline_rounded,
                  color: i == _providerIdx
                      ? AppColors.accent
                      : AppColors.muted,
                ),
                title: Text(cinemaProviders[i].name,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                subtitle: Text(cinemaProviders[i].home,
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 11, color: AppColors.muted)),
                trailing: i == _providerIdx
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => _useServer(i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openEpisodeSheet() {
    final CinemaMeta? m = widget.meta;
    if (m == null || m.episodes.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (BuildContext bctx, ScrollController sc) => Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('الحلقات',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: m.episodes.length,
                itemBuilder: (BuildContext c, int i) {
                  final CinemaEpisode e = m.episodes[i];
                  final bool current =
                      e.season == widget.season && e.number == widget.episode;
                  return ListTile(
                    dense: true,
                    leading: Text(e.label,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: current
                                ? AppColors.accent
                                : AppColors.muted)),
                    title: Text(
                        e.name.isEmpty ? 'الحلقة ${e.number}' : e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: current
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: current ? AppColors.accent : AppColors.text)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _loadEpisode(e.season, e.number, name: e.name);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            WebViewWidget(controller: _controller),
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 26),
                child: Row(
                  children: <Widget>[
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                    if (!_isTrailer && widget.meta?.isSeries == true)
                      IconButton(
                        onPressed: _openEpisodeSheet,
                        icon: const Icon(Icons.playlist_play_rounded,
                            color: Colors.white70, size: 22),
                      ),
                    if (!_isTrailer)
                      TextButton(
                        onPressed: _openServerSheet,
                        child: Text(_provider.name.split('·').last.trim(),
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white70, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            // Loading / switching overlay
            if (_loading && !_failed && !_playing)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _attempts == 0
                              ? (_loadPct > 0 && _loadPct < 100
                                  ? 'جارٍ تحميل المشغّل $_loadPct%'
                                  : 'جارٍ التحميل…')
                              : 'جارٍ تبديل السيرفر…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Error card — every server failed.
            if (_failed)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(26),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.stroke),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.danger, size: 40),
                      const SizedBox(height: 12),
                      const Text('فشلت جميع السيرفرات',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      const SizedBox(height: 6),
                      Text(
                        _probeText?.isEmpty ?? true
                            ? 'تعذّر الوصول إلى مزوّدي البث '
                                'حاليًا. تحقّق من اتصالك أو أعد المحاولة لاحقًا.'
                            : 'رسالة آخر سيرفر: «$_probeText».',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.sub),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded,
                                size: 18, color: AppColors.text),
                            label: const Text('إعادة المحاولة للكل',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12.5,
                                    color: AppColors.text)),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _failed = false;
                                _attempts = 0;
                                _providerIdx = 0;
                              });
                              _openServerSheet();
                            },
                            icon: const Icon(Icons.dns_rounded,
                                size: 18, color: AppColors.sub),
                            label: const Text('اختر سيرفرًا',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12.5,
                                    color: AppColors.sub)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Auto-next countdown dialog shown when the embed reports `ended`.
class _NextEpisodeDialog extends StatefulWidget {
  const _NextEpisodeDialog({
    required this.title,
    required this.seconds,
    required this.onPlay,
    required this.onCancel,
  });

  final String title;
  final int seconds;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  State<_NextEpisodeDialog> createState() => _NextEpisodeDialogState();
}

class _NextEpisodeDialogState extends State<_NextEpisodeDialog> {
  late int _left = widget.seconds;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() async {
    while (_left > 0 && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _left--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('التالي',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text)),
      content: Text('${widget.title} — يبدأ خلال $_left ث',
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, color: AppColors.sub)),
      actions: <Widget>[
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('إلغاء',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  color: AppColors.sub)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: widget.onPlay,
          child: Text('شغّل الآن',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
        ),
      ],
    );
  }
}
