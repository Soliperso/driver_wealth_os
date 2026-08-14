import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../domain/work_platform.dart';

class PlatformLogo extends StatelessWidget {
  const PlatformLogo({super.key, required this.platform, this.size = 42});

  final WorkPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _backgroundColor(context),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: .24)),
    ),
    child: _logo(context),
  );

  Color _backgroundColor(BuildContext context) => switch (platform) {
    WorkPlatform.uber => const Color(0xFF000000),
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

  Widget _logo(BuildContext context) {
    final markSize = size * .58;
    return switch (platform) {
      WorkPlatform.uber => Icon(
        SimpleIcons.uber,
        color: Colors.white,
        size: markSize,
      ),
      WorkPlatform.uberEats => Icon(
        SimpleIcons.ubereats,
        color: Colors.white,
        size: markSize,
      ),
      WorkPlatform.lyft => Icon(
        SimpleIcons.lyft,
        color: Colors.white,
        size: markSize,
      ),
      WorkPlatform.doorDash => Icon(
        SimpleIcons.doordash,
        color: Colors.white,
        size: markSize,
      ),
      WorkPlatform.instacart => Icon(
        SimpleIcons.instacart,
        color: Colors.white,
        size: markSize,
      ),
      WorkPlatform.grubhub => Text(
        'GH',
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .31,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.1,
        ),
      ),
      WorkPlatform.amazonFlex => SizedBox.square(
        dimension: markSize,
        child: const CustomPaint(painter: _AmazonFlexPainter()),
      ),
      WorkPlatform.walmartSpark => SizedBox.square(
        dimension: markSize,
        child: const CustomPaint(painter: _WalmartSparkPainter()),
      ),
      WorkPlatform.other => Icon(
        Icons.work_outline_rounded,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        size: markSize,
      ),
    };
  }
}

class _AmazonFlexPainter extends CustomPainter {
  const _AmazonFlexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
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
  bool shouldRepaint(covariant _AmazonFlexPainter oldDelegate) => false;
}

class _WalmartSparkPainter extends CustomPainter {
  const _WalmartSparkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
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
  bool shouldRepaint(covariant _WalmartSparkPainter oldDelegate) => false;
}
