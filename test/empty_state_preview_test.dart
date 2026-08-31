// Temporary harness: renders the shared empty state in both themes and writes
// PNGs so the result can be looked at. Delete once checked.
import 'dart:io';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/core/widgets/empty_state_card.dart';
import 'package:driver_wealth_os/core/widgets/page_frame.dart';
import 'package:driver_wealth_os/core/widgets/soft_surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  const faces = {
    'Roboto': [
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ],
    'MaterialIcons': ['build/unit_test_assets/fonts/MaterialIcons-Regular.otf'],
  };
  for (final entry in faces.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.view(file.readAsBytesSync().buffer)),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required bool dark,
    required Widget child,
    required String title,
  }) async {
    tester.view.physicalSize = const Size(1179, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: SoftScaffold(
          title: title,
          body: PageFrame(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/$name.png'),
    );
  }

  const coach = EmptyStateCard(
    icon: Icons.auto_awesome_rounded,
    title: 'Nothing to coach yet',
    message:
        'Coach needs earnings, hours, distance and costs before it can '
        'compare which of your sessions actually paid.',
  );

  final history = EmptyStateCard(
    icon: Icons.history_rounded,
    title: 'No sessions yet',
    message:
        'Your completed sessions will appear here with their true-profit '
        'details.',
    action: OutlinedButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add first session'),
    ),
  );

  testWidgets('coach light', (t) async {
    await shot(
      t,
      name: 'coach_light',
      dark: false,
      child: coach,
      title: 'Profit coach',
    );
  });
  testWidgets('coach dark', (t) async {
    await shot(
      t,
      name: 'coach_dark',
      dark: true,
      child: coach,
      title: 'Profit coach',
    );
  });
  testWidgets('history light', (t) async {
    await shot(
      t,
      name: 'history_light',
      dark: false,
      child: history,
      title: 'History',
    );
  });
  testWidgets('history dark', (t) async {
    await shot(
      t,
      name: 'history_dark',
      dark: true,
      child: history,
      title: 'History',
    );
  });
}
