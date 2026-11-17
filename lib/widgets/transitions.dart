import 'package:flutter/material.dart';

/// Slide-up + fade page route used across the app for a consistent,
/// snappier feel than the default platform transition.
class SlideFadeRoute<T> extends PageRouteBuilder<T> {
  SlideFadeRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (BuildContext context, Animation<double> a,
                  Animation<double> b) =>
              page,
          transitionsBuilder: (BuildContext context, Animation<double> anim,
                  Animation<double> secondary, Widget child) {
            final CurvedAnimation curved =
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
