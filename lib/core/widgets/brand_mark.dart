import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.showShadow = false});

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final radius = size * .3;
    return Semantics(
      label: 'Driver Wealth OS logo',
      image: true,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brand, AppColors.brandDeep],
            ),
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: AppColors.brandDeep.withValues(alpha: .24),
                      blurRadius: size * .35,
                      offset: Offset(0, size * .16),
                    ),
                  ]
                : null,
          ),
          child: CustomPaint(painter: BrandGlyphPainter()),
        ),
      ),
    );
  }
}

/// The glyph itself, without the tile behind it.
///
/// Public so the launcher-icon generator paints the same marks the app shows.
/// A separately drawn icon asset would drift from this the first time either
/// changed.
class BrandGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final road = Path()
      ..moveTo(size.width * .31, size.height * .72)
      ..cubicTo(
        size.width * .35,
        size.height * .53,
        size.width * .41,
        size.height * .36,
        size.width * .50,
        size.height * .25,
      );
    canvas.drawPath(road, line..color = Colors.white.withValues(alpha: .62));

    final growth = Path()
      ..moveTo(size.width * .36, size.height * .67)
      ..lineTo(size.width * .52, size.height * .52)
      ..lineTo(size.width * .64, size.height * .58)
      ..lineTo(size.width * .73, size.height * .36);
    canvas.drawPath(growth, line..color = Colors.white);

    final arrow = Path()
      ..moveTo(size.width * .60, size.height * .38)
      ..lineTo(size.width * .75, size.height * .32)
      ..lineTo(size.width * .75, size.height * .48);
    canvas.drawPath(arrow, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
