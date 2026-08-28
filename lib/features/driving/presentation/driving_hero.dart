import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../settings/domain/driver_preferences.dart';
import '../../settings/domain/measurement_units.dart';
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
    this.hourlyFloor = DriverPreferences.defaultHourlyFloor,
    this.units = const MeasurementUnits(),
    this.refreshInterval = const Duration(seconds: 1),
    this.onUpgradeBackground,
    this.onPause,
    this.onResume,
    this.onAutoEnd,
    this.onAddPlatform,
    this.onRemovePlatform,
    this.onCancel,
  });

  final DrivingSession session;
  final Future<void> Function() onEndShift;

  /// Throws the session away instead of banking it. Absent renders no control
  /// at all, because a driver offered a way out of a shift they cannot actually
  /// abandon is worse than one who is offered nothing.
  final Future<void> Function()? onCancel;

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

  /// The lowest hourly profit this driver considers worth the trip. Drives the
  /// break-even figure; a floor of zero leaves only the running cost to cover.
  final double hourlyFloor;

  /// The driver's distance unit and currency. Every figure on this card is
  /// rendered through it rather than through the app's pinned US formatter.
  final MeasurementUnits units;

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
              _LiveDot(paused: paused, pulse: widget.refreshInterval != null),
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
                '${widget.units.distanceLabel(session.miles)} tracked',
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
          _LiveStats(
            elapsed: elapsed,
            hourlyFloor: widget.hourlyFloor,
            runningCost: session.estimatedVehicleCost,
            miles: session.miles,
            units: widget.units,
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
                // Left at the shared default so the target is the same size in
                // every state, including the idle card this replaces.
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
          //
          // Filled and in the app's own green, not dressed as a warning:
          // finishing a shift is the ordinary, expected end of this screen and
          // the step that banks the hours. Throwing them away is the button
          // below, and that one is the one wearing red.
          FilledButton(
            key: const ValueKey('end-shift-button'),
            onPressed: _ending ? null : _end,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
            ),
            child: Text(_ending ? 'Ending…' : 'End session'),
          ),
          if (widget.onCancel != null) ...[
            Space.gapXs,
            // Text, not a second filled button: it competes with nothing, and
            // the only driver who should find it is the one looking for it.
            TextButton(
              key: const ValueKey('cancel-session-button'),
              onPressed: _ending ? null : () => widget.onCancel!(),
              style: TextButton.styleFrom(
                foregroundColor: colors.error,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Cancel session'),
            ),
          ],
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
/// a driver who wants that wants End session, which is its own deliberate
/// button.
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

/// The numbers this shift is running up, on one raised surface.
///
/// One card rather than a loose block and two tiles: the break-even figure is
/// computed from the miles and the cost sitting under it, so putting them on
/// separate surfaces asked the driver to connect three things that are really
/// one reading. The card is lifted off the hero's tint so the whole reading
/// separates from the clock and the controls around it.
class _LiveStats extends StatelessWidget {
  const _LiveStats({
    required this.elapsed,
    required this.hourlyFloor,
    required this.runningCost,
    required this.miles,
    required this.units,
  });

  final Duration elapsed;
  final double hourlyFloor;
  final double runningCost;

  /// Always stored in miles; converted on the way to the label.
  final double miles;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        // Lifted off whatever the hero is tinted with rather than painted a
        // fixed colour: the hero fills green while driving and near-black on a
        // break, and a fixed surface fill vanished into the paused card.
        color: isDark
            ? colors.onSurface.withValues(alpha: .06)
            : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BreakEven(
            elapsed: elapsed,
            hourlyFloor: hourlyFloor,
            runningCost: runningCost,
            units: units,
          ),
          Space.gapLg,
          Divider(
            height: 1,
            thickness: 1,
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
          Space.gapLg,
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _LiveMetric(
                    // Named for whichever unit the driver picked, so a metric
                    // driver is not told their kilometres are miles.
                    label: units.distance.label,
                    value: units.distanceLabel(miles),
                  ),
                ),
                const _VerticalRule(),
                Expanded(
                  child: _LiveMetric(
                    // "Estimated" said how sure the figure is; "running" says
                    // what it is doing, which is the part that changes while
                    // the driver watches it.
                    label: 'Running cost',
                    value: units.cents(runningCost),
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

/// What this shift has to have earned, so far, to have been worth taking.
///
/// The one figure on the card a driver cannot work out in their head mid-shift:
/// their own hourly floor multiplied by the time actually counted, plus the
/// vehicle cost the miles have already run up. Everything else here — the
/// clock, the miles, the cost — is an input to it.
///
/// It is deliberately a target and not a score: the app does not know what the
/// platforms have paid until the shift ends and the driver enters it, so this
/// says what the number has to beat rather than pretending to know it.
class _BreakEven extends StatelessWidget {
  const _BreakEven({
    required this.elapsed,
    required this.hourlyFloor,
    required this.runningCost,
    required this.units,
  });

  final Duration elapsed;
  final double hourlyFloor;
  final double runningCost;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Seconds, not `inHours`: whole hours would hold the figure at the floor's
    // first multiple for an hour at a time, which reads as a broken counter on
    // a card that ticks every second.
    final target =
        hourlyFloor * (elapsed.inSeconds / Duration.secondsPerHour) +
        runningCost;

    return Semantics(
      label:
          'Earn ${units.cents(target)} to break even, '
          '${units.cents(hourlyFloor)} per hour floor plus '
          '${units.cents(runningCost)} running cost',
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('earn-to-break-even'),
        // Left, with the label and the working stacked flush under it, so the
        // three lines read as one statement and line up with the metrics below.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EARN TO BREAK EVEN',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          Space.gapXs,
          Text(
            units.cents(target),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
          Space.gapXs,
          // Shows its own working, so the figure is never a number the app
          // simply asserts — and so a driver who disagrees with it knows which
          // setting to go and change.
          Text(
            '${units.cents(hourlyFloor)}/hr floor + '
            '${units.cents(runningCost)} running cost',
            maxLines: 2,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: Space.md),
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5),
  );
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
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
              'counting. If you are driving, resume now — this session ends '
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
/// The core dot is solid; a halo swells out of it and fades, once a beat, only
/// while the session is actually counting. The motion is what separates
/// "recording" from "stopped" at a glance — a paused session holds a still dot,
/// so the two states can never be confused by a driver who glances at the card
/// for half a second.
class _LiveDot extends StatefulWidget {
  const _LiveDot({this.paused = false, this.pulse = true});

  final bool paused;

  /// Whether the halo beats. The parent passes false wherever it has frozen
  /// its own ticker: a loop that never ends means a frame is always scheduled,
  /// which hangs `pumpAndSettle` in every test that reaches this screen.
  final bool pulse;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  static const _diameter = 18.0;
  static const _core = 8.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _LiveDot old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  /// Runs only while the session is counting, and never when the platform has
  /// asked for reduced motion.
  void _syncTicker() {
    final shouldBeat =
        widget.pulse &&
        !widget.paused &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldBeat == _controller.isAnimating) return;
    if (shouldBeat) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = widget.paused ? colors.onSurfaceVariant : colors.primary;
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final beat = _controller.value;
              // Eased growth against a linear fade. Easing both together made
              // the halo dim faster than it grew, which left it invisible for
              // most of the beat.
              final grow = Curves.easeOut.transform(beat);
              return Opacity(
                // Fades as it grows, so the halo dissolves at the edge rather
                // than snapping back to the dot at the end of each beat.
                opacity: (1 - beat) * .45,
                child: Container(
                  // Starts flush with the core dot and swells to fill the box.
                  width: _core + (_diameter - _core) * grow,
                  height: _core + (_diameter - _core) * grow,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
          Container(
            width: _core,
            height: _core,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
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
