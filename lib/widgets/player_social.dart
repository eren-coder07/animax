import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../core/app_prefs.dart';
import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/moments.dart';
import '../screens/auth_screen.dart';
import 'mb_ui.dart' show kFont;

/// Hot-moments strip drawn just above a player's seek bar: the brighter the
/// band, the more people clipped that part of the episode. Tap to jump.
class HeatStrip extends StatelessWidget {
  const HeatStrip({
    super.key,
    required this.social,
    required this.duration,
    required this.onSeek,
    this.height = 14,
  });

  final EpisodeSocial? social;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    final EpisodeSocial? s = social;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, _) {
        final int dur = duration.inSeconds;
        if (s.moments.isEmpty || dur <= 0) return const SizedBox.shrink();
        final List<double> heat = Moments.heat(s.moments, dur);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) => GestureDetector(
            key: const Key('heatStrip'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) {
              final double f = (d.localPosition.dx / c.maxWidth).clamp(
                0.0,
                1.0,
              );
              onSeek(
                Duration(milliseconds: (f * duration.inMilliseconds).round()),
              );
            },
            child: SizedBox(
              height: height,
              width: c.maxWidth,
              child: CustomPaint(painter: _HeatPainter(heat)),
            ),
          ),
        );
      },
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.heat);
  final List<double> heat;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width / heat.length;
    for (int i = 0; i < heat.length; i++) {
      final double v = heat[i];
      if (v <= 0.02) continue;
      final double h = math.max(2, size.height * v);
      final Paint p = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFC14D),
          const Color(0xFFFF3D3D),
          v,
        )!.withValues(alpha: 0.35 + 0.6 * v);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + 0.5, size.height - h, w - 1, h),
          const Radius.circular(1.5),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.heat != heat;
}

/// Danmaku-style layer: comments pinned to a second of the episode fly
/// across the video when playback reaches them. Ignores touches.
class TimedCommentsLayer extends StatefulWidget {
  const TimedCommentsLayer({
    super.key,
    required this.social,
    required this.controller,
  });
  final EpisodeSocial? social;
  final VideoPlayerController? controller;

  @override
  State<TimedCommentsLayer> createState() => _TimedCommentsLayerState();
}

class _TimedCommentsLayerState extends State<TimedCommentsLayer>
    with SingleTickerProviderStateMixin {
  static const double _fly = 8; // seconds a comment takes to cross
  late final Ticker _ticker = createTicker((_) => _tick());
  double _pos = 0; // estimated position (s)
  Duration _lastReported = Duration.zero;
  DateTime _lastAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick() {
    final VideoPlayerController? c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    final Duration p = c.value.position;
    final DateTime now = DateTime.now();
    if (p != _lastReported) {
      _lastReported = p;
      _lastAt = now;
    }
    double est = p.inMilliseconds / 1000;
    if (c.value.isPlaying) {
      est +=
          math.min(1.0, now.difference(_lastAt).inMilliseconds / 1000) *
          c.value.playbackSpeed;
    }
    if ((est - _pos).abs() > 0.015 && mounted) setState(() => _pos = est);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EpisodeSocial? s = widget.social;
    if (s == null || !AppPrefs.I.timedComments) return const SizedBox.shrink();
    final List<TimedComment> active = s.activeAt(_pos, window: _fly);
    if (active.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double laneH = 30;
          final int lanes = math.max(
            1,
            math.min(5, (c.maxHeight * 0.45 / laneH).floor()),
          );
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              for (int i = 0; i < active.length; i++)
                _flyer(active[i], c.maxWidth, (i % lanes) * laneH + 54),
            ],
          );
        },
      ),
    );
  }

  Widget _flyer(TimedComment tc, double width, double top) {
    final double p = ((_pos - tc.t) / _fly).clamp(0.0, 1.0);
    return Positioned(
      left: width * (1 - p),
      top: top,
      child: FractionalTranslation(
        translation: Offset(-p, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '${tc.name.isEmpty ? 'مستخدم' : tc.name}: ',
                  style: const TextStyle(
                    color: AppColors.brandGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: tc.text),
              ],
            ),
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: const TextStyle(
              fontFamily: kFont,
              fontSize: 14,
              color: Colors.white,
              shadows: <Shadow>[Shadow(blurRadius: 3, color: Colors.black)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Player menu: timed comments on/off, write one at the current second,
/// list them all, jump to the hottest moment.
class MomentsMenuButton extends StatelessWidget {
  const MomentsMenuButton({
    super.key,
    required this.social,
    required this.controller,
    required this.onSeek,
    this.iconSize = 21,
  });

  final EpisodeSocial? social;
  final VideoPlayerController? controller;
  final ValueChanged<Duration> onSeek;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('momentsMenu'),
      tooltip: 'لحظات الحلقة',
      icon: Icon(
        Icons.local_fire_department_rounded,
        color: Colors.white,
        size: iconSize,
      ),
      onPressed: social == null ? null : () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final EpisodeSocial s = social!;
    final VideoPlayerController? c = controller;
    final int dur = c?.value.duration.inSeconds ?? 0;
    final int? peak = Moments.peak(s.moments, dur);
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFF7A45),
                ),
                title: Text(
                  peak == null
                      ? 'لا توجد لحظات رائجة بعد'
                      : 'اقفز لأبرز لحظة (${_fmt(peak)})',
                  style: const TextStyle(
                    fontFamily: kFont,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  '${s.moments.length} مقطع من هذه الحلقة',
                  style: const TextStyle(
                    fontFamily: kFont,
                    color: AppColors.sub,
                  ),
                ),
                enabled: peak != null,
                onTap: () => Navigator.pop(ctx, 'peak'),
              ),
              SwitchListTile(
                value: AppPrefs.I.timedComments,
                onChanged: (bool v) {
                  AppPrefs.I.set('timedComments', v);
                  Navigator.pop(ctx);
                },
                secondary: const Icon(
                  Icons.subtitles_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'تعليقات اللحظة على الفيديو',
                  style: TextStyle(fontFamily: kFont, color: Colors.white),
                ),
              ),
              ListTile(
                key: const Key('writeTimedComment'),
                leading: const Icon(
                  Icons.add_comment_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  'علّق عند ${_fmt(c?.value.position.inSeconds ?? 0)}',
                  style: const TextStyle(
                    fontFamily: kFont,
                    color: Colors.white,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'write'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.format_list_bulleted_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  'كل تعليقات الحلقة (${s.comments.length})',
                  style: const TextStyle(
                    fontFamily: kFont,
                    color: Colors.white,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'list'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || pick == null) return;
    switch (pick) {
      case 'peak':
        if (peak != null) onSeek(Duration(seconds: peak));
      case 'write':
        await writeTimedComment(context, s, c);
      case 'list':
        await _list(context, s);
    }
  }

  Future<void> _list(BuildContext context, EpisodeSocial s) async {
    final int? t = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: s.comments.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد تعليقات لحظية بعد — كن الأول!',
                    style: TextStyle(fontFamily: kFont, color: AppColors.sub),
                  ),
                )
              : ListView(
                  children: <Widget>[
                    for (final TimedComment tc in s.comments)
                      ListTile(
                        onTap: () => Navigator.pop(ctx, tc.t),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _fmt(tc.t),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontFamily: kFont,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
                        title: Text(
                          tc.text,
                          style: const TextStyle(
                            fontFamily: kFont,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          tc.name,
                          style: const TextStyle(
                            fontFamily: kFont,
                            color: AppColors.sub,
                          ),
                        ),
                        trailing: tc.uid == CloudAuth.I.user?.uid
                            ? IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.sub,
                                ),
                                onPressed: () {
                                  s.delete(tc);
                                  Navigator.pop(ctx);
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ),
    );
    if (t != null) onSeek(Duration(seconds: t));
  }
}

/// Composer for a comment pinned to the controller's current second.
Future<void> writeTimedComment(
  BuildContext context,
  EpisodeSocial s,
  VideoPlayerController? c,
) async {
  if (!await requireLogin(context)) return;
  if (!context.mounted) return;
  final int t = c?.value.position.inSeconds ?? 0;
  final bool wasPlaying = c?.value.isPlaying ?? false;
  await c?.pause();
  if (!context.mounted) return;
  final TextEditingController text = TextEditingController();
  final String? msg = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    builder: (BuildContext ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'تعليق عند ${_fmt(t)}',
              style: const TextStyle(
                fontFamily: kFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'سيظهر لكل من يشاهد الحلقة عند هذه الثانية بالضبط.',
              style: TextStyle(
                fontFamily: kFont,
                fontSize: 12.5,
                color: AppColors.sub,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('timedCommentField'),
              controller: text,
              autofocus: true,
              maxLength: EpisodeSocial.maxText,
              style: const TextStyle(fontFamily: kFont, color: Colors.white),
              decoration: const InputDecoration(hintText: 'اكتب ردة فعلك…'),
              onSubmitted: (String v) => Navigator.pop(ctx, v),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('sendTimedComment'),
                onPressed: () => Navigator.pop(ctx, text.text),
                child: const Text('نشر', style: TextStyle(fontFamily: kFont)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (msg != null && msg.trim().isNotEmpty) {
    try {
      await s.post(t, msg);
      if (!AppPrefs.I.timedComments) AppPrefs.I.set('timedComments', true);
    } on CloudException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
  if (wasPlaying) await c?.play();
}

String _fmt(int s) {
  final int m = s ~/ 60, ss = s % 60;
  final int h = m ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m % 60)}:${two(ss)}' : '${two(m)}:${two(ss)}';
}
