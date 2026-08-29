import 'package:flutter/material.dart';

/// Fades a block in and lifts it into place, after an optional [delay].
///
/// Used to stagger the parts of a first-run screen so it assembles rather than
/// appearing all at once. The movement is small on purpose: it should read as
/// the page settling, not as an animation the driver has to wait through.
///
/// Honours the platform's reduce-motion setting the way `AnimatedMoney` does —
/// when animations are disabled the child appears immediately, which is the
/// correct behaviour for anyone who has asked the OS to calm things down.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far the child rises, in logical pixels.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Where in the controller's run this child starts moving. The delay is part
  /// of the animation rather than a timer that fires later, so a widget test's
  /// `pumpAndSettle` always reaches the end state.
  late final double _start;

  var _started = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _controller = AnimationController(vsync: this, duration: total);
    _start = total.inMicroseconds == 0
        ? 0
        : widget.delay.inMicroseconds / total.inMicroseconds;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final progress = _start >= 1
          ? 1.0
          : ((_controller.value - _start) / (1 - _start)).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(progress);
      return Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - eased)),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}
