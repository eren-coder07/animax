import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_theme.dart';
import '../core/egy_api.dart';
import '../widgets/buttons.dart';

/// In-app WebView that solves the egydead.ca Cloudflare challenge and hands
/// the resulting cookies to [EgyApi].
///
/// Flow: load https://egydead.ca/ → the managed challenge runs (usually
/// automatic inside a real WebView) → once a `cf_clearance` cookie appears
/// in the platform cookie jar (read through the `animax/app` → `getCookies`
/// method channel) we persist the header and pop.
class EgyGateScreen extends StatefulWidget {
  const EgyGateScreen({super.key});

  @override
  State<EgyGateScreen> createState() => _EgyGateScreenState();
}

class _EgyGateScreenState extends State<EgyGateScreen> {
  late final WebViewController _controller;
  bool _checking = false;
  bool _done = false;
  String _status = 'Opening egydead.ca…';
  Timer? _poll;

  static const MethodChannel _channel = MethodChannel('animax/app');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String _) => _pollCookies(),
      ))
      ..loadRequest(Uri.parse(EgyApi.base));
    // The challenge can finish without a navigation event — poll anyway.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollCookies());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pollCookies() async {
    if (_checking || _done || !mounted) return;
    _checking = true;
    try {
      final String? jar = await _channel.invokeMethod<String>(
          'getCookies', <String, String>{'url': EgyApi.base});
      final String header = (jar ?? '').trim();
      if (header.contains('cf_clearance')) {
        _done = true;
        await EgyApi.I.saveCookies(header);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      if (mounted) {
        setState(() =>
            _status = 'Verifying access… (keep this screen open)');
      }
    } on PlatformException {
      // Channel unavailable — keep waiting for the page itself.
    } catch (_) {
      // Cookie manager not ready yet — try again on the next tick.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        iconTheme: const IconThemeData(color: AppColors.text),
        title: Text('EgyDead access check',
            style: AppText.h3.copyWith(fontSize: 16)),
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                if (!_done)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: AppColors.green, strokeWidth: 2),
                  )
                else
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.green, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_status,
                      style: AppText.label.copyWith(fontSize: 11.5)),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: GhostChip(
                label: 'Cancel',
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
