import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/hh_api.dart';
import 'hentai_tab.dart';

/// Live search over the hentai catalog (WordPress REST `search=`).
/// Debounced, paginated via "Load more".
class HhSearchScreen extends StatefulWidget {
  const HhSearchScreen({super.key});

  @override
  State<HhSearchScreen> createState() => _HhSearchScreenState();
}

class _HhSearchScreenState extends State<HhSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  String _query = '';
  final List<HhSeries> _results = <HhSeries>[];
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Keyboard pops with the screen — this is the only thing to do here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final String q = value.trim();
      if (q == _query) return;
      setState(() {
        _query = q;
        _results.clear();
        _page = 1;
        _done = false;
        _error = null;
      });
      if (q.length >= 2) _run();
    });
  }

  Future<void> _run() async {
    if (_loading || _query.length < 2) return;
    setState(() => _loading = true);
    try {
      final HhSearchResult res = await HentaiApi.I.search(_query, page: _page);
      if (!mounted) return;
      setState(() {
        _results.addAll(res.items);
        _page++;
        _loading = false;
        if (res.items.isEmpty) _done = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _done = true;
        if (_results.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _done = true;
        if (_results.isEmpty) _error = 'تعذّر الوصول إلى المصدر — تحقّق من اتصالك.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool idle = _query.length < 2;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: _SearchField(
          controller: _controller,
          focus: _focus,
          onChanged: _onChanged,
          onClear: () {
            _controller.clear();
            _onChanged('');
          },
        ),
      ),
      body: idle
          ? _Idle()
          : _error != null && _results.isEmpty
              ? Center(
                  child: Text(_error!,
                      style: AppText.body.copyWith(color: AppColors.danger)),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification n) {
                    if (!_done &&
                        !_loading &&
                        n.metrics.pixels >
                            n.metrics.maxScrollExtent - 600) {
                      _run();
                    }
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.52,
                    ),
                    itemCount:
                        _results.length + (_loading || !_done ? 1 : 0),
                    itemBuilder: (BuildContext context, int i) {
                      if (i >= _results.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                                color: HhColors.red, strokeWidth: 2.4),
                          ),
                        );
                      }
                      return HhSeriesCard(series: _results[i],
                          width: double.infinity);
                    },
                  ),
                ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focus,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppText.bodyBold.copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'ابحث…',
        hintStyle: AppText.body.copyWith(color: AppColors.muted),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        prefixIcon:
            Icon(Icons.search_rounded, color: AppColors.muted, size: 22),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, TextEditingValue v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.muted, size: 19),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_search_rounded,
                color: AppColors.muted, size: 44),
            const SizedBox(height: 14),
            Text('اكتب حرفين على الأقل',
                style: AppText.body),
            const SizedBox(height: 6),
            Text('ابحث باسم المسلسل أو بكلمة مفتاحية.',
                style: AppText.label),
          ],
        ),
      ),
    );
  }
}
