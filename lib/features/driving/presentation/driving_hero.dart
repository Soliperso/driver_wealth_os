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
    this.trackingInterrupted = false,
    this.refreshInterval = const Duration(seconds: 1),
    this.onUpgradeBackground,
  });

  final DrivingSession session;
  final Future<void> Function() onEndShift;

  /// Only foreground location was granted, so mileage may stall once the
  /// driver switches to Uber.
  final bool backgroundLimited;

  /// The location stream has failed or permission was revoked mid-shift, so
  /// miles are no longer accruing at all.
  final bool trackingInterrupted;

  /// Escalates to background location without leaving the shift.
  final Future<void> Function()? onUpgradeBackground;

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
          // An outright stall outranks the foreground-only warning: if nothing
          // is being counted, whether it would count in the background is moot.
          if (widget.trackingInterrupted) ...[
            Space.gapMd,
            const _TrackingInterruptedNotice(),
          ] else if (widget.backgroundLimited) ...[
            Space.gapMd,
            _LimitedBackgroundNotice(onUpgrade: widget.onUpgradeBackground),
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

/// Surfaced when the location stream has stopped producing fixes.
///
/// The failure mode this prevents is the quiet one: a session that still shows
/// a running clock while its mileage sits frozen. Fewer miles means a smaller
/// vehicle-cost deduction and a larger apparent profit, so a driver who is not
/// told would be misled in the direction they would most like to believe.
class _TrackingInterruptedNotice extends StatelessWidget {
  const _TrackingInterruptedNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('tracking-interrupted-notice'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gps_off_rounded, size: 16, color: colors.error),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Mileage tracking stopped. Your time is still counting, but '
              'check your location settings — miles are not being added.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Surfaced when only foreground location was granted.
///
/// Worth interrupting for: silently under-counting miles shrinks the vehicle
/// cost and inflates the profit figure, so a driver who thinks they are being
/// tracked and is not would be misled in the flattering direction.
class _LimitedBackgroundNotice extends StatelessWidget {
  const _LimitedBackgroundNotice({this.onUpgrade});

  final Future<void> Function()? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('background-limited-notice'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colors.onSurface,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Location is set to “While Using”. Your miles may stop '
                  'counting when you switch to another app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (onUpgrade != null) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('upgrade-background-button'),
                onPressed: () => onUpgrade!(),
                child: const Text('Track the full shift'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
