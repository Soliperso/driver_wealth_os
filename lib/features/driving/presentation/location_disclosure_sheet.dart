import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';

/// Explains location tracking **before** the OS prompt appears.
///
/// This is not decoration. Google Play requires a prominent in-app disclosure
/// before requesting background location, and a system dialog on its own does
/// not tell a driver what is collected, why, or when it stops. It is also
/// simply the honest thing to show someone before asking to follow their car
/// around all day.
///
/// Returns true when the driver agrees to continue to the system prompt.
class LocationDisclosureSheet extends StatelessWidget {
  const LocationDisclosureSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const LocationDisclosureSheet(),
    );
    return agreed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the explanation scrolls. The choice stays pinned, because a
            // consent control that sits below the fold on a small phone is one
            // the driver may never see.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SoftIcon(Icons.my_location_rounded),
                    ),
                    Space.gapLg,
                    Text(
                      'Why Driver Wealth needs your location',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Space.gapSm,
                    Text(
                      'Your miles are half of your true profit. Without them '
                      'there is no vehicle cost to subtract, and the profit '
                      'figure would be flattering and wrong.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    Space.gapXl,
                    const _DisclosurePoint(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Only during a shift you started',
                      detail:
                          'Tracking begins when you tap Start Driving and stops '
                          'the moment you tap End Shift. Never before, never '
                          'after.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.phone_android_rounded,
                      title: 'In the background, while you work',
                      detail:
                          'So your miles keep counting while you are in the Uber '
                          'or Lyft app. This is what the “Always” option allows.',
                    ),
                    const _DisclosurePoint(
                      icon: Icons.straighten_rounded,
                      title: 'Used to measure distance, nothing else',
                      detail:
                          'Your positions are added up into a mileage total on '
                          'this phone. Driver Wealth does not sell, share, or '
                          'advertise against where you drive.',
                    ),
                  ],
                ),
              ),
            ),
            Space.gapLg,
            FilledButton(
              key: const ValueKey('location-disclosure-continue'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
            Space.gapSm,
            TextButton(
              key: const ValueKey('location-disclosure-decline'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            Space.gapXs,
            Text(
              'You can still track shifts by entering hours and miles yourself.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclosurePoint extends StatelessWidget {
  const _DisclosurePoint({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
