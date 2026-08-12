import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../domain/driving_session.dart';

/// The live session card.
///
/// The clock here is a *display* refresh, not the source of truth: every tick
/// recomputes `now - startedAt` from the stored timestamp, so a suspended or
/// killed app still shows the correct elapsed time when it comes back.
///
class DrivingHero extends StatefulWidget {
  const DrivingHero({
    super.key,
    required this.session,
    required this.onEndShift,
    this.backgroundLimited = false,
    this.refreshInterval = const Duration(seconds: 1),
  });

  final DrivingSession session;
  final Future<void> Function() onEndShift;

  /// Only foreground location was granted, so mileage may stall once the
  /// driver switches to Uber.
  final bool backgroundLimited;

  /// How often the displayed clock re-reads the wall clock. Pass null to hold
  /// a single frame.
  ///
  /// Tests should disable it: a periodic rebuild means a frame is always
  /// scheduled, so `pumpAndSettle()` never returns. Correctness does not
  /// depend on it — elapsed time is computed from [DrivingSession.startedAt]
  /// on every build, so a frozen ticker shows a stale label and nothing more.
  final Duration? refreshInterval;

  @override
  State<DrivingHero> createState() => _DrivingHeroState();
}

class _DrivingHeroState extends State<DrivingHero> {
  Timer? _ticker;
  var _ending = false;

  @override
  void initState() {
    super.initState();
    final interval = widget.refreshInterval;
    if (interval != null) {
      _ticker = Timer.periodic(interval, (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = widget.session;
    final elapsed = session.elapsed();

    return GlassSurface(
      key: const ValueKey('driving-session-active'),
      elevation: Elevation.hero,
      padding: const EdgeInsets.all(Space.xl),
      tint: colors.primaryContainer.withValues(alpha: .9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _LiveDot(),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'DRIVING',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                session.platform.displayName,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Space.gapLg,
          Semantics(
            label:
                'Driving for ${elapsed.inHours} hours '
                '${elapsed.inMinutes.remainder(60)} minutes, '
                '${Money.number(session.miles)} miles tracked',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatElapsed(elapsed),
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: colors.onSurface),
                ),
                Space.gapSm,
                Text(
                  '${Money.number(session.miles)} miles',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Space.gapLg,
          // Cost is shown live because it is already accruing. Hiding it until
          // the end would let a driver finish a shift before learning it was
          // expensive.
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Estimated vehicle cost',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                Money.cents(session.estimatedVehicleCost),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          if (widget.backgroundLimited) ...[
            Space.gapMd,
            _LimitedBackgroundNotice(),
          ],
          Space.gapXl,
          FilledButton(
            key: const ValueKey('end-shift-button'),
            onPressed: _ending ? null : _end,
            style: FilledButton.styleFrom(
              backgroundColor: colors.onSurface,
              foregroundColor: colors.surface,
            ),
            child: Text(_ending ? 'Ending…' : 'END SHIFT'),
          ),
        ],
      ),
    );
  }

  Future<void> _end() async {
    setState(() => _ending = true);
    try {
      await widget.onEndShift();
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }
}

/// Makes it unmistakable that tracking is running, which is both a usability
/// and a privacy obligation.
///
/// Deliberately static. A repeating animation would mean this screen never
/// reaches a settled frame, which makes every `pumpAndSettle` in every test
/// that touches it hang — the same trap that already cost this suite a
/// ten-minute stall once. The ring, the "DRIVING" label and the running clock
/// already make the state obvious without it.
class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .35), blurRadius: 6),
        ],
      ),
    );
  }
}

class _LimitedBackgroundNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurface),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Location is set to “While Using”. Miles may stop counting when '
              'you switch to another app — choose “Always” to track a full '
              'shift.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
