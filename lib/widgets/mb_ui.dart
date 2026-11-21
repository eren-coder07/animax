import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Shared building blocks of the streaming-style UI: poster tiles, titled
/// rows with "الكل ›", pill and gradient buttons, grouped cards.

const String kFont = 'Plex';

/// Set by the home screen around an embedded section so the section hides
/// its own title bar (the home header already provides search + tabs).
class EmbeddedSection extends InheritedWidget {
  const EmbeddedSection({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmbeddedSection>() != null;

  @override
  bool updateShouldNotify(EmbeddedSection oldWidget) => false;
}

/// Network image: shimmer while loading, soft fade-in, quiet failure.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return ColoredBox(color: AppColors.surfaceHi);
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(
        color: AppColors.surfaceHi,
        child: const Center(
            child: Icon(Icons.movie_outlined, color: AppColors.muted, size: 26)),
      ),
      frameBuilder: (BuildContext c, Widget child, int? frame, bool sync) {
        if (sync) return child;
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            if (frame == null) const Shimmer(),
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: child,
            ),
          ],
        );
      },
    );
  }
}

/// Animated loading placeholder (soft light sweep).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.radius = 0});
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final double x = _c.value * 3 - 1.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, -0.3),
              end: Alignment(x + 1, 0.3),
              colors: <Color>[
                AppColors.surface,
                AppColors.surfaceHi,
                AppColors.surface,
              ],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Portrait poster with the title underneath (2:3, 6px corners).
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.title,
    required this.image,
    this.onTap,
    this.badge = '',
    this.rating = 0,
    this.width,
    this.heroTag,
  });

  final String title;
  final String image;
  final VoidCallback? onTap;

  /// Small corner tag (quality / language), e.g. "WEB-DL".
  final String badge;
  final double rating;
  final double? width;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget poster = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          NetImage(image),
          if (badge.isNotEmpty)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Color(0x99000000),
                  borderRadius: BorderRadiusDirectional.only(
                      bottomStart: Radius.circular(6)),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          if (rating > 0)
            PositionedDirectional(
              bottom: 4,
              start: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.star_rounded,
                        size: 11, color: AppColors.star),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (heroTag != null) poster = Hero(tag: heroTag!, child: poster);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(aspectRatio: 2 / 3, child: poster),
            const SizedBox(height: 5),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: kFont,
                    fontSize: 12.5,
                    height: 1.3,
                    color: Color(0xFFE6E7EA))),
          ],
        ),
      ),
    );
  }
}

/// "Title ................ الكل ›" row header.
class RowHeader extends StatelessWidget {
  const RowHeader(this.title, {super.key, this.onAll, this.trailing});
  final String title;
  final VoidCallback? onAll;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: kFont,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          ?trailing,
          if (onAll != null)
            GestureDetector(
              onTap: onAll,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('الكل',
                        style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 12.5,
                            color: AppColors.sub)),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppColors.sub),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section title + horizontally scrolling posters (≈3.3 visible).
class PosterRow<T> extends StatelessWidget {
  const PosterRow({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.onAll,
    this.loading = false,
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item, double width)
      itemBuilder;
  final VoidCallback? onAll;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final double w = (MediaQuery.sizeOf(context).width - 24 - 16) / 3.2;
    final double h = w * 1.5 + 26;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RowHeader(title, onAll: onAll),
        SizedBox(
          height: h,
          child: loading && items.isEmpty
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, _) => Column(
                    children: <Widget>[
                      SizedBox(
                          width: w,
                          height: w * 1.5,
                          child: const Shimmer(radius: 6)),
                    ],
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext c, int i) =>
                      itemBuilder(c, items[i], w),
                ),
        ),
      ],
    );
  }
}

/// Dark rounded pill with icon + label (details actions, chips).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHi,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 20,
                  color: active ? AppColors.brandGreen : Colors.white),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontFamily: kFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: active ? AppColors.brandGreen : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cyan → green gradient call-to-action.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 50,
    this.soft = false,
    this.expand = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;

  /// Muted resource-bar variant (dark teal → dark green, colored text).
  final bool soft;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Color fg = soft ? AppColors.brandCyan : const Color(0xFF07130D);
    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: soft ? 15 : 17,
                  fontWeight: FontWeight.w700,
                  color: fg)),
        ),
      ],
    );
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: soft ? AppColors.softGrad : AppColors.brandGrad,
          borderRadius: BorderRadius.circular(soft ? 6 : height / 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(soft ? 6 : height / 2),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grouped dark card (Me screen, settings blocks).
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
            height: 1, indent: 16, endIndent: 16, color: AppColors.stroke));
      }
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// One row inside a [GroupCard]: icon · label · trailing value · ›.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.icon,
    required this.label,
    this.value = '',
    this.badge = 0,
    this.onTap,
    this.below,
  });
  final IconData icon;
  final String label;
  final String value;
  final int badge;
  final VoidCallback? onTap;

  /// Extra content under the row (e.g. watch-history thumbnails).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: Colors.white, size: 25),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                if (badge > 0)
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: AppColors.badge, shape: BoxShape.circle),
                    child: Text('$badge',
                        style: const TextStyle(
                            fontFamily: kFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                if (value.isNotEmpty)
                  Text(value,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 15,
                          color: AppColors.sub)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.sub, size: 22),
              ],
            ),
            ?below,
          ],
        ),
      ),
    );
  }
}

/// Small gray info line pieces joined by thin separators: "★ 7.4 | 2026 | …".
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, this.rating = 0, this.parts = const <String>[]});
  final double rating;
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    const TextStyle st =
        TextStyle(fontFamily: kFont, fontSize: 14, color: AppColors.sub);
    final List<Widget> out = <Widget>[];
    void sep() => out.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('|',
              style: TextStyle(
                  fontFamily: kFont, fontSize: 12, color: AppColors.muted)),
        ));
    if (rating > 0) {
      out.add(const Icon(Icons.star_rounded, color: AppColors.star, size: 18));
      out.add(const SizedBox(width: 2));
      out.add(Text(rating.toStringAsFixed(1),
          style: st.copyWith(color: AppColors.star)));
    }
    for (final String p in parts.where((String p) => p.trim().isNotEmpty)) {
      if (out.isNotEmpty) sep();
      out.add(Flexible(
          child: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)));
    }
    return Row(children: out);
  }
}
