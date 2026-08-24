import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../domain/work_platform.dart';

class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, required this.platform, this.size = 42});

  final WorkPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final disc = _backgroundColor(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: disc,
        shape: BoxShape.circle,
      ),
      child: _logo(context, _markColor(context, disc)),
    );
  }

  /// White on a dark disc, black on a light one — so a brand whose disc flips
  /// with the theme keeps a legible mark without a second per-platform table.
  Color _markColor(BuildContext context, Color disc) => switch (platform) {
    // The only disc drawn from the scheme rather than a brand colour, so it
    // takes the scheme's matching foreground instead of a guess.
    WorkPlatform.other => Theme.of(context).colorScheme.onSecondaryContainer,
    _ => ThemeData.estimateBrightnessForColor(disc) == Brightness.dark
        ? Colors.white
        : Colors.black,
  };

  Color _backgroundColor(BuildContext context) => switch (platform) {
    // Uber's lockup is black-on-white, and a black disc on this app's dark
    // hero card read as a hole punched in the tile rather than a logo — the
    // hairline ring was the only thing separating the two near-blacks. In a
    // dark theme the brand's light lockup is both the higher-contrast and the
    // more faithful of the two; light theme keeps the black disc.
    WorkPlatform.uber => Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000),
    // Uber Eats' own green, so it reads as a sibling brand rather than a
    // duplicate of the rides tile in a list showing both.
    WorkPlatform.uberEats => const Color(0xFF06C167),
    WorkPlatform.lyft => const Color(0xFFD6009A),
    WorkPlatform.doorDash => const Color(0xFFE02B0A),
    WorkPlatform.instacart => const Color(0xFF287A1F),
    WorkPlatform.grubhub => const Color(0xFFE85D04),
    WorkPlatform.amazonFlex => const Color(0xFF146EB4),
    WorkPlatform.walmartSpark => const Color(0xFF0071CE),
    WorkPlatform.other => Theme.of(context).colorScheme.secondaryContainer,
  };

  Widget _logo(BuildContext context, Color mark) {
    // Bumped from .58: at chip size the mark is only a dozen or so pixels
    // across, and the disc had more empty margin than logo.
    final markSize = size * .64;
    return switch (platform) {
      WorkPlatform.uber => Icon(SimpleIcons.uber, color: mark, size: markSize),
      WorkPlatform.uberEats => Icon(
        SimpleIcons.ubereats,
        color: mark,
        size: markSize,
      ),
      WorkPlatform.lyft => Icon(SimpleIcons.lyft, color: mark, size: markSize),
      WorkPlatform.doorDash => Icon(
        SimpleIcons.doordash,
        color: mark,
        size: markSize,
      ),
      WorkPlatform.instacart => Icon(
        SimpleIcons.instacart,
        color: mark,
        size: markSize,
      ),
      WorkPlatform.grubhub => Text(
        'GH',
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: TextStyle(
          color: mark,
          fontSize: size * .31,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.1,
        ),
      ),
      WorkPlatform.amazonFlex => SizedBox.square(
        dimension: markSize,
        child: CustomPaint(painter: _AmazonFlexPainter(mark)),
      ),
      WorkPlatform.walmartSpark => SizedBox.square(
        dimension: markSize,
        child: CustomPaint(painter: _WalmartSparkPainter(mark)),
      ),
      WorkPlatform.other => Icon(
        Icons.work_outline_rounded,
        color: mark,
        size: markSize,
      ),
    };
  }
}

class _AmazonFlexPainter extends CustomPainter {
  const _AmazonFlexPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .13
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final inset = size.width * .14;
    final centerGap = size.width * .08;
    canvas.drawLine(
      Offset(inset, inset),
      Offset(center.dx - centerGap, center.dy - centerGap),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, inset),
      Offset(center.dx + centerGap, center.dy - centerGap),
      paint,
    );
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(center.dx - centerGap, center.dy + centerGap),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset),
      Offset(center.dx + centerGap, center.dy + centerGap),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AmazonFlexPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _WalmartSparkPainter extends CustomPainter {
  const _WalmartSparkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .13
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.width * .17;
    final outerRadius = size.width * .40;
    for (var index = 0; index < 6; index++) {
      final angle = (math.pi * 2 * index / 6) - math.pi / 2;
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius,
        ),
        Offset(
          center.dx + math.cos(angle) * outerRadius,
          center.dy + math.sin(angle) * outerRadius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WalmartSparkPainter oldDelegate) =>
      oldDelegate.color != color;
}
