import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_data.dart';
import '../core/app_theme.dart';
import '../widgets/cards.dart';

/// Live keyword search over the backend (`/search?keyword=`).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  List<Anime> _results = const <Anime>[];
  String _query = '';
  bool _searched = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Keyboard opens with the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final String q = value.trim();
    if (q.length < 2) {
      if (_searched || _results.isNotEmpty || _error != null) {
        setState(() {
          _results = const <Anime>[];
          _searched = false;
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _query = q;
    });
    try {
      final List<Anime> found = await ApiService.I
          .search(q)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _results = found;
        _searched = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searched = true;
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'Something went wrong — try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              return TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (String v) {
                  _debounce?.cancel();
                  final String q = v.trim();
                  if (q.length >= 2) _run(q);
                },
                onChanged: _onChanged,
                style: AppText.body
                    .copyWith(fontSize: 14, color: AppColors.text),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'Search anime…',
                  hintStyle: AppText.label.copyWith(fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: AppColors.muted),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                            _focus.requestFocus();
                          },
                        ),
                ),
              );
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2.5),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: AppColors.muted, size: 40),
              const SizedBox(height: 12),
              Text('Search failed',
                  style: AppText.bodyBold.copyWith(fontSize: 14)),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(fontSize: 11.5)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  final String q = _controller.text.trim();
                  if (q.length >= 2) _run(q);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.accent),
                  ),
                  child: Text('Try again',
                      style: AppText.bodyBold.copyWith(
                          fontSize: 12.5, color: AppColors.accent)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_rounded, color: AppColors.muted, size: 44),
            const SizedBox(height: 12),
            Text('Find your next anime',
                style: AppText.bodyBold.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Text('Type at least 2 characters —\nresults appear as you type.',
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 11.5)),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.muted, size: 44),
            const SizedBox(height: 12),
            Text('No results for “$_query”',
                style: AppText.bodyBold.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            Text('Check the spelling or try a shorter keyword.',
                style: AppText.label.copyWith(fontSize: 11.5)),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Text(
                '${_results.length} result${_results.length == 1 ? '' : 's'} for “$_query”',
                style: AppText.label.copyWith(fontSize: 11)),
          ),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.52,
              ),
              itemCount: _results.length,
              itemBuilder: (BuildContext context, int i) =>
                  PosterCard(anime: _results[i]),
            ),
          ),
        ],
      ),
    );
  }
}
