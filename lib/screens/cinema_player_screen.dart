import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_theme.dart';
import '../core/cinema_api.dart';

/// Fullscreen WebView player for the Cinema section.
///
/// Hosts the vidsrc.sh multi-server embed player:
///  * the embed resolves 3+ servers per title (auto-fallback on failure),
///  * it ships its own subtitle system (OpenSubtitles auto-match, CC menu),
///  * playback is bandwidth-adaptive (hls.js ABR picks the quality that the
///    current Wi-Fi/cellular throughput supports).
///
/// Requests to ad / popunder hosts are blocked so the top frame can never be
/// hijacked; navigation stays inside the player hosts. Movies load
/// `embed/movie/{imdb}`, episodes `embed/tv/{imdb}/{s}-{e}` (verified live).
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
  bool _loading = true;
  bool _failed = false;
  int _loadPct = 0;
  Timer? _watchdog;

  String get _title {
    final String? direct = widget._directTitle;
    if (direct != null) return direct;
    final CinemaMeta? m = widget.meta;
    if (m == null) return 'Cinema';
    if (widget.episode > 0) {
      final String ep = widget.episodeName.isEmpty
          ? 'Episode ${widget.episode}'
          : widget.episodeName;
      return '${m.name} — S${widget.season} · $ep';
    }
    return m.name;
  }

  String? get _startUrl {
    final String? direct = widget._directUrl;
    if (direct != null) return direct;
    final CinemaMeta? m = widget.meta;
    if (m == null) return null;
    if (widget.episode > 0) {
      return CinemaPlayback.episodeUrl(m.id, widget.season, widget.episode);
    }
    return CinemaPlayback.movieUrl(m.id);
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(CinemaPlayback.ua)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (NavigationRequest req) {
          final Uri? uri = Uri.tryParse(req.url);
          if (uri == null || !uri.hasScheme) return NavigationDecision.prevent;
          if (uri.scheme == 'http' ||
              uri.scheme == 'https' &&
                  !CinemaPlayback.isAllowedHost(uri.host)) {
            // Popunders / ad redirects — never leave the player.
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onProgress: (int p) {
          if (!mounted) return;
          setState(() => _loadPct = p);
          if (p >= 100) _settle();
        },
        onPageFinished: (_) => _settle(),
        onWebResourceError: (_) => _settle(),
      ))
      ..setOnConsoleMessage((JavaScriptConsoleMessage _) {})
      ..loadRequest(Uri.parse(_startUrl ?? 'about:blank'));
    if (_startUrl == null) {
      setState(() => _failed = true);
    }
    // Some embeds never fire onPageFinished when the frame stays busy —
    // hide the spinner after 12 s regardless.
    _watchdog = Timer(const Duration(seconds: 12), _settle);
  }

  void _settle() {
    if (!mounted) return;
    _watchdog?.cancel();
    if (_loading || _loadPct < 100) {
      setState(() {
        _loading = false;
        _loadPct = 100;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause embed media when backgrounded (WebView keeps playing otherwise).
    if (state == AppLifecycleState.paused) {
      _controller.runJavaScript(
          'document.querySelectorAll("video,audio").forEach(v=>v.pause());')
          .catchError((Object e) => '');
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
    });
    _controller.loadRequest(Uri.parse(_startUrl ?? 'about:blank'));
    _watchdog = Timer(const Duration(seconds: 12), _settle);
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
                padding:
                    const EdgeInsets.fromLTRB(12, 6, 12, 26),
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
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
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
            // Loading overlay
            if (_loading && !_failed)
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
                        const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                              color: AppColors.green, strokeWidth: 2.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadPct > 0 && _loadPct < 100
                              ? 'Loading player $_loadPct%'
                              : 'Connecting to stream servers…',
                          style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Error card
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
                      const Text('Player could not load',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text)),
                      const SizedBox(height: 6),
                      const Text(
                        'Check your connection and try again. The stream '
                        'player also needs a few seconds on first open.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Poppins',
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
                            label: const Text('Retry',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    color: AppColors.text)),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded,
                                size: 18, color: AppColors.sub),
                            label: const Text('Back',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
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
