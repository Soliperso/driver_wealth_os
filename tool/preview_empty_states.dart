// Development-only entrypoint: both empty states in both themes at once.
//
//   flutter run -t tool/preview_empty_states.dart -d macos
//
// Lives outside `lib/` for the same reason as [preview_charts.dart] — nothing
// that ships should be able to import a harness by accident.
import 'package:flutter/material.dart';

import 'package:driver_wealth_os/core/theme/app_theme.dart';
import 'package:driver_wealth_os/core/widgets/empty_state_card.dart';
import 'package:driver_wealth_os/core/widgets/page_frame.dart';
import 'package:driver_wealth_os/core/widgets/soft_surfaces.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _pane(dark: false, coach: true),
              _pane(dark: true, coach: true),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _pane(dark: false, coach: false),
              _pane(dark: true, coach: false),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _pane({required bool dark, required bool coach}) => Expanded(
    child: Theme(
      data: dark ? AppTheme.dark : AppTheme.light,
      child: SoftScaffold(
        title: coach ? 'Profit coach' : 'History',
        body: PageFrame(
          child: coach
              ? const EmptyStateCard(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Nothing to coach yet',
                  message:
                      'Coach needs earnings, hours, distance and costs before '
                      'it can compare which of your sessions actually paid.',
                )
              : EmptyStateCard(
                  icon: Icons.history_rounded,
                  title: 'No sessions yet',
                  message:
                      'Your completed sessions will appear here with their '
                      'true-profit details.',
                  action: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add first session'),
                  ),
                ),
        ),
      ),
    ),
  );
}
