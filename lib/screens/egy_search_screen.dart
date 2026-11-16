import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/egy_api.dart';
import '../widgets/buttons.dart';
import 'egy_details_screen.dart';
import 'egy_gate_screen.dart';
import 'egy_tab.dart' show EgyColors, EgyPosterCard;

/// EgyDead keyword search (`/api/v1/search/{query}?loader=searchPage`).
class EgySearchScreen extends StatefulWidget {
  const EgySearchScreen({super.key});

  @override
  State<EgySearchScreen> createState() => _EgySearchScreenState();
}

class _EgySearchScreenState extends State<EgySearchScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  List<EgyTitle>? _results;
  bool _searching = false;
  bool _challenge = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(v));
  }

  Future<void> _run(String raw) async {
    final String q = raw.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _results = null;
          _error = null;
          _challenge = false;
        });
      }
      return;
    }
    _debounce?.cancel();
    setState(() {
      _searching = true;
      _error = null;
      _challenge = false;
    });
    try {
      await EgyApi.I.loadCookies();
      final List<EgyTitle> res = await EgyApi.I.search(q);
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    } on EgyChallengeException {
      if (mounted) {
        setState(() {
          _searching = false;
          _challenge = true;
        });
      }
    } on EgyApiException catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = 'Cannot reach egydead.ca right now.';
        });
      }
    }
  }

  Future<void> _openGate() async {
    final bool ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const EgyGateScreen()),
        ) ??
        false;
    if (ok) _run(_query.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        iconTheme: const IconThemeData(color: AppColors.text),
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          focusNode: _focus,
          onChanged: _onChanged,
          onSubmitted: _run,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 14, color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Search EgyDead movies & series…',
            hintStyle: AppText.label.copyWith(fontSize: 12.5),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: <Widget>[
          if (_query.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.sub, size: 20),
              onPressed: () {
                _query.clear();
                setState(() => _results = null);
                _focus.requestFocus();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_challenge) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.shield_outlined,
                  color: EgyColors.red, size: 42),
              const SizedBox(height: 12),
              Text('Verification required',
                  style: AppText.h3.copyWith(fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                'egydead.ca is asking for a Cloudflare check before search '
                'works. Verify once in the built-in browser.',
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 16),
              GhostChip(label: 'Verify access', active: true, onTap: _openGate),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded,
                  color: AppColors.muted, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(fontSize: 12)),
              const SizedBox(height: 14),
              GhostChip(
                  label: 'Retry',
                  active: true,
                  onTap: () => _run(_query.text)),
            ],
          ),
        ),
      );
    }
    if (_searching) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.52,
        ),
        itemCount: 9,
        itemBuilder: (BuildContext context, int i) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    final List<EgyTitle>? results = _results;
    if (results == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.manage_search_rounded,
                color: AppColors.muted, size: 42),
            const SizedBox(height: 10),
            Text('Type a movie or series name',
                style: AppText.label.copyWith(fontSize: 12)),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.search_off_rounded,
                color: AppColors.muted, size: 42),
            const SizedBox(height: 10),
            Text('No results for "${_query.text.trim()}"',
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 12)),
          ],
        ),
      );
    }
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: results.length,
      itemBuilder: (BuildContext context, int i) {
        final EgyTitle t = results[i];
        return EgyPosterCard(
          title: t,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EgyDetailsScreen(title: t),
          )),
        );
      },
    );
  }
}
