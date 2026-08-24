import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../domain/driving_session.dart';
import 'shift_control.dart';

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
    this.onPause,
    this.onResume,
    this.onAutoEnd,
    this.onAddPlatform,
    this.onRemovePlatform,
  });

  final DrivingSession session;
  final Future<void> Function() onEndShift;

  /// Switches another app on mid-shift. Null renders the app chips read-only,
  /// which is what a screen with no controller wired should show.
  final Future<void> Function()? onAddPlatform;

  /// Switches one app off, leaving the shift running on the rest.
  final Future<void> Function(WorkPlatform platform)? onRemovePlatform;

  /// Starts and ends a break. Both are absent when no controller is wired,
  /// which hides the control rather than offering a button that does nothing.
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;

  /// Fired from the display ticker once a break has run past
  /// [pauseAutoEndAfter]. Idempotent downstream, so it costs nothing to call
  /// more than once.
  final VoidCallback? onAutoEnd;

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
      _ticker = Timer.periodic(interval, (_) {
        // The overrun check rides the clock that is already running rather
        // than starting a second timer. It only matters while the app is
        // open; the cold-start path is handled in the controller.
        if (widget.session.currentPause() >= pauseAutoEndAfter) {
          widget.onAutoEnd?.call();
        }
        setState(() {});
      });
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
    final paused = session.isPaused;
    final breakSoFar = session.currentPause();

    return GlassSurface(
      key: const ValueKey('driving-session-active'),
      elevation: Elevation.flat,
      radius: Radii.lg,
      padding: const EdgeInsets.all(Space.lg),
      tint: paused
          ? colors.surface.withValues(alpha: .84)
          : colors.primaryContainer.withValues(alpha: .68),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _LiveDot(paused: paused),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  paused ? 'Paused' : 'Driving',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: paused ? colors.onSurfaceVariant : colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Space.gapMd,
          // Directly under the status, above the clock: what you are running,
          // then how long you have been running it. Editable in place because
          // a driver switches Lyft on two hours into an Uber shift and must
          // not have to end the shift to say so.
          _AppsRow(
            live: session.livePlatforms,
            onAdd: widget.onAddPlatform,
            onRemove: widget.onRemovePlatform,
          ),
          Space.gapLg,
          Semantics(
            label:
                '${paused ? 'Paused after' : 'Driving for'} '
                '${elapsed.inHours} hours '
                '${elapsed.inMinutes.remainder(60)} minutes, '
                '${Money.number(session.miles)} miles tracked',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  formatElapsed(elapsed),
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: colors.onSurface),
                ),
                Space.gapXs,
                Text(
                  'Started at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(session.startedAt), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Space.gapLg,
          SizedBox(
            height: 72,
            child: Row(
              children: [
                Expanded(
                  child: _LiveMetric(
                    label: 'Miles',
                    value: '${Money.number(session.miles)} mi',
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _LiveMetric(
                    label: 'Estimated cost',
                    value: Money.cents(session.estimatedVehicleCost),
                  ),
                ),
              ],
            ),
          ),
          // Cost stays visible while it accrues. Hiding it until the end would
          // let a driver finish before learning that the shift was expensive.
          // A long break outranks both tracking warnings, because during one
          // the tracking is off by design and saying so is the whole point.
          if (paused && breakSoFar >= pauseWarningAfter) ...[
            Space.gapMd,
            _PausedNotice(taken: breakSoFar),
          ] else if (widget.trackingInterrupted) ...[
            // An outright stall outranks the foreground-only warning: if
            // nothing is being counted, whether it would count in the
            // background is moot.
            Space.gapMd,
            const _TrackingInterruptedNotice(),
          ] else if (widget.backgroundLimited) ...[
            Space.gapMd,
            _LimitedBackgroundNotice(onUpgrade: widget.onUpgradeBackground),
          ],
          if (widget.onPause != null && widget.onResume != null) ...[
            Space.gapLg,
            Center(
              child: ShiftControl(
                diameter: 80,
                state: paused
                    ? ShiftControlState.paused
                    : ShiftControlState.driving,
                // Only a break fills the ring, and it fills toward the point
                // the shift ends itself — the one thing on this card the
                // driver cannot read anywhere else. While driving it stays a
                // plain bezel, because the clock directly above it already
                // says everything a sweep could.
                ringProgress: paused
                    ? breakSoFar.inMilliseconds /
                          pauseAutoEndAfter.inMilliseconds
                    : 0,
                onPressed: paused ? _resume : _pause,
              ),
            ),
          ],
          Space.gapLg,
          // Kept a plain full-width button rather than folded into the round
          // control: it is the one action here that cannot be taken back, so
          // it should not sit under the thumb that pauses.
          OutlinedButton(
            key: const ValueKey('end-shift-button'),
            onPressed: _ending ? null : _end,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: .38)),
            ),
            child: Text(_ending ? 'Ending…' : 'End shift'),
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

  Future<void> _pause() async => widget.onPause?.call();

  Future<void> _resume() async => widget.onResume?.call();
}

/// The apps this shift is running, and the controls to change them.
///
/// A chip per live app plus one "Add app" button. The button is present even on
/// a single-app shift, because it is the only place a driver finds out that
/// running two at once is supported at all.
///
/// Removing is a plain tap with no confirmation: it closes the app's span
/// rather than deleting anything, the shift keeps running, and switching it
/// back on is one more tap. The last remaining app has no remove control at
/// all — a shift running nothing has no one to attribute the earnings to, and
/// a driver who wants that wants End shift, which is its own deliberate button.
class _AppsRow extends StatelessWidget {
  const _AppsRow({required this.live, this.onAdd, this.onRemove});

  final List<WorkPlatform> live;
  final Future<void> Function()? onAdd;
  final Future<void> Function(WorkPlatform platform)? onRemove;

  @override
  Widget build(BuildContext context) {
    final removable = live.length > 1 && onRemove != null;
    return SizedBox(
      // Tall enough for the 30px logo plus the tile's padding and border;
      // anything tighter overflows the row rather than scrolling it.
      height: 46,
      child: Row(
        children: [
          // The live apps scroll; the button does not. Pinning it to the right
          // edge keeps it in the same place whether the shift runs one app or
          // four, so it never slides under the thumb reaching for a chip.
          Expanded(
            child: ListView(
              key: const ValueKey('driving-apps-row'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final platform in live) ...[
                  _AppChip(
                    platform: platform,
                    onRemove: removable ? () => onRemove!(platform) : null,
                  ),
                  const SizedBox(width: Space.sm),
                ],
              ],
            ),
          ),
          if (onAdd != null)
            ActionChip(
              key: const ValueKey('add-app-button'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add app'),
              onPressed: () => onAdd!(),
            ),
        ],
      ),
    );
  }
}

class _AppChip extends StatelessWidget {
  const _AppChip({required this.platform, this.onRemove});

  final WorkPlatform platform;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      // The logo alone carries no name for a screen reader, so the label does.
      label: '${platform.displayName}, running',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('app-chip-${platform.id}'),
        padding: EdgeInsets.fromLTRB(6, 5, onRemove == null ? 6 : 2, 5),
        decoration: BoxDecoration(
          // Lifted off the card rather than tinted with it: the tile has to
          // read as a surface the logo sits on, or a dark brand disc sinks
          // into the hero's own dark fill.
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo only. A driver knows their own apps by their marks, and on
            // a card read at a glance in a moving car the wordmarks are noise.
            //
            // Deliberately not a Material chip. InputChip with no onPressed or
            // onDeleted counts as disabled and dims whatever it is given as a
            // label, which washed the brand disc out to grey on exactly the
            // common case — a shift running one app, where nothing is
            // removable.
            PlatformLogo(platform: platform, size: 30),
            // Absent on the last remaining app rather than disabled: a
            // greyed-out × invites a tap that will be refused.
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                tooltip: 'Stop ${platform.displayName}',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once a break has run long enough to look forgotten.
///
/// The quiet failure this catches: a paused session counts no time and no
/// miles, so a driver who paused for coffee and drove off without resuming
/// records a shorter, cheaper shift than they drove — which reads as a more
/// profitable one. Saying how long it has been, and what happens next, is the
/// only way they find out before the numbers are wrong.
class _PausedNotice extends StatelessWidget {
  const _PausedNotice({required this.taken});

  final Duration taken;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hours = taken.inHours;
    final minutes = taken.inMinutes.remainder(60);
    final spent = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    return Container(
      key: const ValueKey('paused-notice'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 16,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'Paused for $spent. Neither your time nor your miles are '
              'counting. If you are driving, resume now — this shift ends '
              'itself after ${pauseAutoEndAfter.inHours} hours paused.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes it unmistakable that tracking is running, which is both a usability
/// and a privacy obligation.
///
/// Deliberately static and shadow-free. The status label and running clock make
/// the state clear without adding motion or glow to a screen used while moving.
class _LiveDot extends StatelessWidget {
  const _LiveDot({this.paused = false});

  final bool paused;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = paused ? colors.onSurfaceVariant : colors.primary;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Semantics(
              label:
                  'Background tracking is limited. Miles may stop counting '
                  'when you switch apps.',
              child: ExcludeSemantics(
                child: Text(
                  'Background tracking is limited',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (onUpgrade != null) ...[
            const SizedBox(width: Space.sm),
            TextButton(
              key: const ValueKey('upgrade-background-button'),
              onPressed: () => onUpgrade!(),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                minimumSize: const Size(44, 40),
              ),
              child: const Text('Fix'),
            ),
          ],
        ],
      ),
    );
  }
}
