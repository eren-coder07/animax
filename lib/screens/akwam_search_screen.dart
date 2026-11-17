import 'dart:async';

import 'package:flutter/material.dart';

import '../core/akwam_api.dart';
import '../core/app_theme.dart';
import '../widgets/common.dart' show IconBubble;
import 'akwam_tab.dart';

/// Akwam keyword search across movies, series and shows.
class AkwamSearchScreen extends StatefulWidget {
  const AkwamSearchScreen({super.key});

  @override
  State<AkwamSearchScreen> createState() => _AkwamSearchScreenState();
}

class _AkwamSearchScreenState extends State<AkwamSearchScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  final List<AkwamItem> _results = <AkwamItem>[];
  bool _loading = false;
  bool _done = false;
  int _page = 1;
  String _lastQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(value);
    });
  }

  Future<void> _search(String query, {bool nextPage = false}) async {
    final String q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results.clear();
        _loading = false;
        _done = false;
        _error = null;
        _lastQuery = '';
      });
      return;
    }
    if (_loading || (nextPage && _done)) return;
    setState(() {
      if (!nextPage || q != _lastQuery) {
        _results.clear();
        _page = 1;
        _done = false;
      }
      _lastQuery = q;
      _loading = true;
      _error = null;
    });
    try {
      final List<AkwamItem> fresh = await AkwamApi.I.search(q, page: _page);
      if (!mounted) return;
      setState(() {
        for (final AkwamItem it in fresh) {
          if (!_results.any((AkwamItem x) => x.id == it.id)) _results.add(it);
        }
        _page++;
        _loading = false;
        if (fresh.isEmpty) _done = true;
      });
    } on AkwamApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_results.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_results.isEmpty) _error = 'Search failed — try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showResults = _lastQuery.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: <Widget>[
                  IconBubble(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      onSubmitted: _search,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: AppColors.text),
                      decoration: InputDecoration(
                        hintText: 'Search Akwam — movies, series, shows…',
                        hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            color: AppColors.muted),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AkwamColors.teal, size: 20),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppColors.stroke),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: AkwamColors.teal, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showResults)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Text('Results for “$_lastQuery”',
                    style: AppText.h3.copyWith(fontSize: 14)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!,
                    style: AppText.body.copyWith(color: AppColors.danger)),
              ),
            Expanded(
              child: !showResults
                  ? _Hint()
                  : _results.isEmpty && _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AkwamColors.teal, strokeWidth: 2.4))
                      : _results.isEmpty
                          ? const Center(
                              child: Text('No results on Akwam.',
                                  style: AppText.body))
                          : NotificationListener<ScrollNotification>(
                              onNotification: (ScrollNotification n) {
                                if (n.metrics.pixels >
                                    n.metrics.maxScrollExtent - 600) {
                                  _search(_lastQuery, nextPage: true);
                                }
                                return false;
                              },
                              child: GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 10, 20, 40),
                                physics: const BouncingScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.52,
                                ),
                                itemCount: _results.length +
                                    (_done || _error != null ? 0 : 1),
                                itemBuilder: (BuildContext context, int i) {
                                  if (i >= _results.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(18),
                                        child: CircularProgressIndicator(
                                            color: AkwamColors.teal,
                                            strokeWidth: 2.4),
                                      ),
                                    );
                                  }
                                  return AkwamCard(item: _results[i]);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.movie_filter_rounded,
              color: AkwamColors.teal.withValues(alpha: 0.6), size: 44),
          const SizedBox(height: 12),
          Text('Type to search akwam.ss',
              style: AppText.body.copyWith(fontSize: 13)),
          const SizedBox(height: 6),
          Text('Arabic and English titles both work',
              style: AppText.label.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
