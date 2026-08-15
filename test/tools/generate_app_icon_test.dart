@Tags(['tools'])
library;

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:driver_wealth_os/core/theme/app_colors.dart';
import 'package:driver_wealth_os/core/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the launcher icon source images from [BrandMark].
///
/// Not a test — a generator, kept here because painting a widget to a PNG needs
/// the Flutter test binding. It exists so the icon is the real brand mark
/// rather than a separately drawn asset that drifts from it.
///
/// Run it, then regenerate the platform icons:
///
///   flutter test --tags=tools test/tools/generate_app_icon_test.dart
///   dart run flutter_launcher_icons
void main() {
  testWidgets('writes the launcher icon sources', (tester) async {
    // Two variants. The plain icon keeps the rounded-square mark, which is
    // what Android and iOS expect to letterbox themselves. The adaptive
    // foreground is inset and transparent, because Android crops it to
    // whatever shape the launcher uses and a full-bleed image loses its edges.
    await _capture(tester, const _IconCanvas(), 'assets/icon/app_icon.png');
    await _capture(
      tester,
      const _IconCanvas(adaptive: true),
      'assets/icon/app_icon_foreground.png',
    );
  });
}

Future<void> _capture(WidgetTester tester, Widget child, String path) async {
  // 1024 is the App Store's required source size; every smaller asset is
  // downscaled from it.
  tester.view
    ..physicalSize = const Size(1024, 1024)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1024, 1024)),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

class _IconCanvas extends StatelessWidget {
  const _IconCanvas({this.adaptive = false});

  final bool adaptive;

  @override
  Widget build(BuildContext context) {
    if (adaptive) {
      return SizedBox.square(
        dimension: 1024,
        // Android's adaptive-icon safe zone is the centre ~66%; anything
        // outside it can be cropped away by the launcher's mask.
        child: Center(
          child: SizedBox.square(
            dimension: 620,
            child: CustomPaint(painter: BrandGlyphPainter()),
          ),
        ),
      );
    }
    return Container(
      width: 1024,
      height: 1024,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand, AppColors.brandDeep],
        ),
      ),
      child: Center(
        child: SizedBox.square(
          dimension: 660,
          child: CustomPaint(painter: BrandGlyphPainter()),
        ),
      ),
    );
  }
}
