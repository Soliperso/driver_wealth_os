import 'package:flutter/material.dart';

/// The app icon, shown inside the app.
///
/// This renders the same artwork the launcher icon is generated from rather
/// than a hand-drawn approximation of it. The previous version painted its own
/// glyph in code, which silently stopped matching the moment the icon artwork
/// was replaced — the mark on the onboarding screen and the mark on the home
/// screen were two different logos.
///
/// The artwork carries its own rounded tile and transparent corners, so there
/// is deliberately no clip or decoration here: anything added would either
/// fight the tile or cut into it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Keeprate logo',
    image: true,
    child: Image.asset(
      'assets/icon/app_mark.png',
      width: size,
      height: size,
      // The source is 256px square and is drawn far smaller than that, so the
      // downscale is what anyone actually sees.
      filterQuality: FilterQuality.medium,
    ),
  );
}
