import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/metric_panel.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/section_card_title.dart';
import '../../../core/widgets/section_heading.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/domain/work_platform.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../driving/domain/driving_session.dart';
import '../../driving/presentation/driving_hero.dart';
import '../../driving/presentation/shift_control.dart';
import '../../settings/domain/driver_preferences.dart';
import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.driverName,
    required this.shifts,
    required this.dailyGoal,
    required this.onAddShift,
    required this.onDailyGoalChanged,
    this.onOpenShift,
    this.onOpenHistory,
    this.onOpenSettings,
    this.onRefresh,
    this.drivingSession,
    this.drivingBackgroundLimited = false,
    this.drivingTrackingInterrupted = false,
    this.hourlyFloor = DriverPreferences.defaultHourlyFloor,
    this.units = const MeasurementUnits(),
    this.onStartDriving,
    this.onEndShift,
    this.onPauseDriving,
    this.onResumeDriving,
    this.onAutoEndShift,
    this.onCancelDriving,
    this.onUpgradeBackground,
    this.onAddDrivingPlatform,
    this.onRemoveDrivingPlatform,
    this.drivingRefreshInterval = const Duration(seconds: 1),
    this.clock,
    this.pendingDraft,
    this.onResumeDraft,
    this.onDiscardDraft,
    this.storageError,
  });

  final String driverName;
  final List<Shift> shifts;
  final double dailyGoal;
  final VoidCallback onAddShift;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<Shift>? onOpenShift;

  /// Switches to the History tab. Null hides the link out of Recent sessions.
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenSettings;
  final Future<void> Function()? onRefresh;

  /// Non-null while a driving session is running.
  final DrivingSession? drivingSession;
  final bool drivingBackgroundLimited;
  final bool drivingTrackingInterrupted;

  /// Passed to the live card's break-even figure. See [DrivingHero.hourlyFloor].
  final double hourlyFloor;

  /// The driver's distance unit and currency. Every figure on this screen goes
  /// through it, so nothing here is fixed to miles or to dollars.
  final MeasurementUnits units;
  final VoidCallback? onStartDriving;
  final Future<void> Function()? onEndShift;
  final Future<void> Function()? onPauseDriving;
  final Future<void> Function()? onResumeDriving;
  final VoidCallback? onAutoEndShift;

  /// Abandons the running session without banking a shift.
  final Future<void> Function()? onCancelDriving;
  final Future<void> Function()? onUpgradeBackground;

  /// Switches apps on and off without interrupting the running shift.
  final Future<void> Function()? onAddDrivingPlatform;
  final Future<void> Function(WorkPlatform platform)? onRemoveDrivingPlatform;

  /// Null freezes the live clock. See [DrivingHero.refreshInterval].
  final Duration? drivingRefreshInterval;

  /// Injectable wall clock, as on History and Taxes.
  ///
  /// This screen is anchored on "now" twice over — the date in the header and
  /// which shifts count as today's — so without a seam a golden of it can only
  /// match on the day it was taken, and a running session's elapsed time makes
  /// it drift between one run and the next.
  final DateTime Function()? clock;

  /// A tracked shift still waiting on its earnings.
  final Shift? pendingDraft;
  final VoidCallback? onResumeDraft;
  final VoidCallback? onDiscardDraft;

  /// Non-null when the last write to device storage failed.
  final String? storageError;

  @override
  Widget build(BuildContext context) {
    final now = (clock ?? DateTime.now)();
    final todayShifts = shifts.where((shift) => shift.occurredOn(now));
    final recentShifts = shifts.take(5).toList();
    final summary = ShiftSummary.from(todayShifts);
    final net = summary.netProfit;
    final keepRate = summary.keepRate;
    final target = dailyGoal;
    final colors = Theme.of(context).colorScheme;

    return SoftScaffold(
      toolbarHeight: 68,
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hi, $driverName!',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            _formattedDate(now),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Semantics(
            label: '$driverName profile and settings',
            button: true,
            child: InkWell(
              onTap: onOpenSettings,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colors.primary,
                child: Text(
                  driverName.trim().isEmpty
                      ? 'D'
                      : driverName.trim()[0].toUpperCase(),
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      body: PageFrame(
        child: RefreshIndicator(
          // Always present so the gesture is consistent; with no backend
          // configured the refresh simply finds nothing to import.
          onRefresh: onRefresh ?? () async {},
          child: ListView(
            children: [
              if (storageError != null) ...[
                _StorageErrorBanner(message: storageError!),
                Space.gapLg,
              ],
              // Unfinished tracked driving outranks everything else on the
              // screen: it is the only thing here that can still be lost.
              if (pendingDraft != null && drivingSession == null) ...[
                _TrackedDraftCard(
                  draft: pendingDraft!,
                  units: units,
                  onResume: onResumeDraft,
                  onDiscard: onDiscardDraft,
                ),
                Space.gapLg,
              ],
              // Mid-shift the live session is what the driver opened the app
              // to see, so it takes the hero slot until the shift ends.
              if (drivingSession != null)
                DrivingHero(
                  session: drivingSession!,
                  backgroundLimited: drivingBackgroundLimited,
                  trackingInterrupted: drivingTrackingInterrupted,
                  hourlyFloor: hourlyFloor,
                  units: units,
                  clock: clock,
                  onEndShift: onEndShift ?? () async {},
                  onPause: onPauseDriving,
                  onResume: onResumeDriving,
                  onAutoEnd: onAutoEndShift,
                  onCancel: onCancelDriving,
                  onUpgradeBackground: onUpgradeBackground,
                  onAddPlatform: onAddDrivingPlatform,
                  onRemovePlatform: onRemoveDrivingPlatform,
                  refreshInterval: drivingRefreshInterval,
                )
              else ...[
                _ProfitHero(
                  net: net,
                  keepRate: keepRate,
                  target: target,
                  hasShifts: summary.shiftCount > 0,
                  units: units,
                  onEditGoal: () => _editDailyGoal(context),
                ),
                Space.gapLg,
                if (onStartDriving != null)
                  _StartDrivingCard(
                    onStart: onStartDriving!,
                    onEnterManually: onAddShift,
                  )
                else
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: onAddShift,
                      child: const Text('Enter a session manually'),
                    ),
                  ),
              ],
              if (summary.shiftCount > 0) ...[
                Space.gapLg,
                _PerformancePanel(
                  netPerHour: summary.hours == 0 ? null : summary.netPerHour,
                  netPerMile: summary.miles == 0 ? null : summary.netPerMile,
                  miles: summary.miles,
                  shiftCount: summary.shiftCount,
                  units: units,
                ),
                Space.gapLg,
                _NextMove(
                  message: _nextMove(
                    hasShifts: true,
                    net: net,
                    target: target,
                    keepRate: keepRate,
                    netPerHour: summary.netPerHour,
                    hourlyFloor: hourlyFloor,
                    units: units,
                  ),
                ),
              ],
              // "Recent" means the latest shifts overall, so this is gated on
              // having any history at all rather than on having driven today.
              if (recentShifts.isNotEmpty) ...[
                Space.gapXl,
                SectionHeading(
                  title: 'RECENT SESSIONS',
                  // A link out, not a second way in: this list is the last five
                  // sessions, and the question it raises is "where are the
                  // rest?". Adding one by hand already has its own control up
                  // the screen.
                  actionLabel: onOpenHistory == null ? null : 'View history',
                  onAction: onOpenHistory,
                  actionKey: const ValueKey('view-history-link'),
                ),
                Space.gapMd,
                ...recentShifts.map(
                  (shift) => _ShiftRow(
                    shift: shift,
                    units: units,
                    onTap: onOpenShift == null
                        ? null
                        : () => onOpenShift!(shift),
                  ),
                ),
              ],
              const SizedBox(height: Space.bottomNavClearance),
            ],
          ),
        ),
      ),
    );
  }

  static String _nextMove({
    required bool hasShifts,
    required double net,
    required double target,
    required double keepRate,
    required double netPerHour,
    required double hourlyFloor,
    required MeasurementUnits units,
  }) {
    final toGo = units.whole((target - net).clamp(0, target).toDouble());
    if (!hasShifts) {
      return 'Add one completed session to reveal your true hourly profit and keep rate.';
    }
    if (net < 0) {
      return 'Today’s driving cost ${units.cents(net.abs())} more than it earned. '
          'Check the session’s mileage and expenses before repeating this pattern.';
    }
    if (net >= target) {
      return 'You reached today’s profit goal. Review this session before deciding whether more driving is worth it.';
    }
    if (keepRate < _lowKeepRate) {
      return 'Your keep rate is below ${Money.percent(_lowKeepRate)}. Check '
          'mileage and direct costs before repeating this pattern.';
    }
    // Measured against the driver's own floor, not a number the app picked:
    // $25/hr is a healthy pace in one city and a losing one in another, and the
    // driver has already told Settings which they are.
    if (hourlyFloor > 0 && netPerHour >= hourlyFloor) {
      return 'This is a healthy hourly pace, above your '
          '${units.cents(hourlyFloor)}/hr floor. You’re $toGo from today’s goal.';
    }
    return 'You’re $toGo from today’s goal. Compare your next session’s hours '
        'and miles carefully.';
  }

  /// Where "most of what you earned went to running the car" starts. A rule of
  /// thumb rather than a preference: it is the app's own judgement about the
  /// shape of a bad shift, not a figure about this driver.
  static const _lowKeepRate = .65;

  static String _formattedDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Future<void> _editDailyGoal(BuildContext context) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _DailyGoalSheet(initialGoal: dailyGoal),
    );
    if (value != null) onDailyGoalChanged(value);
  }
}

class _DailyGoalSheet extends StatefulWidget {
  const _DailyGoalSheet({required this.initialGoal});

  final double initialGoal;

  @override
  State<_DailyGoalSheet> createState() => _DailyGoalSheetState();
}

class _DailyGoalSheetState extends State<_DailyGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialGoal.toStringAsFixed(
        widget.initialGoal.truncateToDouble() == widget.initialGoal ? 0 : 2,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SafeArea(
      top: false,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Daily profit goal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            Text(
              'Set the amount you want to keep after driving costs.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Goal amount',
                prefixText: '\$ ',
              ),
              validator: (input) {
                final parsed = double.tryParse(input?.trim() ?? '');
                if (parsed == null || parsed <= 0 || parsed > 100000) {
                  return 'Enter an amount between \$1 and \$100,000';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _save, child: const Text('Save goal')),
          ],
        ),
      ),
    ),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(double.parse(_controller.text.trim()));
  }
}

/// The primary action when no session is running.
///
/// Deliberately the loudest control on the screen: capturing time and mileage
/// automatically is what removes the guesswork from every number downstream.
class _StartDrivingCard extends StatelessWidget {
  const _StartDrivingCard({
    required this.onStart,
    required this.onEnterManually,
  });

  final VoidCallback onStart;

  /// The fallback for a driver who would rather not be tracked, or who is
  /// logging a shift they already finished. Kept directly under the primary
  /// action so it stays a visible choice rather than something to hunt for.
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      key: const ValueKey('start-driving-card'),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The play glyph that used to sit in a SoftIcon here is now the
          // button itself, so the heading no longer needs its own.
          //
          // A status line, not a heading: set like the other eyebrow labels on
          // this screen so it reads as the state the card is in. It carries no
          // explanatory line under it — the button below says what tapping it
          // does, and a paragraph of copy repeated on every idle visit is one
          // more thing to scroll past.
          Text(
            'NOT DRIVING',
            textAlign: TextAlign.center,
            // The card-eyebrow rank, not a title: it was set two sizes above
            // every other eyebrow in the app, so an idle screen shouted its
            // least useful line the loudest.
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: .6,
              fontWeight: FontWeight.w700,
            ),
          ),
          Space.gapXl,
          Center(
            child: ShiftControl(
              state: ShiftControlState.idle,
              onPressed: onStart,
            ),
          ),
          Space.gapMd,
          TextButton(
            onPressed: onEnterManually,
            child: const Text('Enter a session manually'),
          ),
        ],
      ),
    );
  }
}

/// A finished session whose earnings were never entered.
///
/// Tracked hours and miles cannot be reconstructed once thrown away — the
/// driving already happened. So an abandoned earnings screen leaves this behind
/// rather than silently discarding the shift.
class _TrackedDraftCard extends StatelessWidget {
  const _TrackedDraftCard({
    required this.draft,
    required this.units,
    required this.onResume,
    required this.onDiscard,
  });

  final Shift draft;
  final MeasurementUnits units;
  final VoidCallback? onResume;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      key: const ValueKey('pending-draft-card'),
      padding: const EdgeInsets.all(Space.xl),
      tint: colors.tertiaryContainer.withValues(alpha: .82),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SoftIcon(Icons.pending_actions_rounded),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session waiting on earnings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${Money.hours(draft.hours)} and '
                      '${units.distanceLabel(draft.miles)} tracked on '
                      '${draft.platform.displayName}. Add what you earned to '
                      'see the profit.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Space.gapLg,
          FilledButton(
            key: const ValueKey('resume-draft-button'),
            onPressed: onResume,
            // Sentence case like every other button in the app. All-caps read
            // as shouting on the one card that is already the loudest thing on
            // the screen.
            child: const Text('Enter earnings'),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            key: const ValueKey('discard-draft-button'),
            onPressed: onDiscard,
            child: const Text('Discard this session'),
          ),
        ],
      ),
    );
  }
}

/// Shown when the device refused a write. Silence here would mean a driver
/// keeps logging shifts that are never actually saved.
class _StorageErrorBanner extends StatelessWidget {
  const _StorageErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      key: const ValueKey('storage-error-banner'),
      padding: const EdgeInsets.all(Space.lg),
      tint: colors.errorContainer.withValues(alpha: .82),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              message,
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

class _ProfitHero extends StatelessWidget {
  const _ProfitHero({
    required this.net,
    required this.keepRate,
    required this.target,
    required this.hasShifts,
    required this.units,
    required this.onEditGoal,
  });

  final double net;
  final double keepRate;
  final double target;
  final bool hasShifts;
  final MeasurementUnits units;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final goalState = _GoalState.from(
      net: net,
      target: target,
      hasShifts: hasShifts,
    );
    final isLoss = goalState == _GoalState.loss;
    // A loss has no meaningful progress toward a profit goal, so the bar sits
    // empty rather than implying partial credit.
    final progress = isLoss ? 0.0 : (net / target).clamp(0.0, 1.0);
    final accent = switch (goalState) {
      _GoalState.loss => colors.error,
      _GoalState.reached || _GoalState.exceeded => colors.tertiary,
      _ => colors.primary,
    };
    final tint = switch (goalState) {
      _GoalState.loss => colors.errorContainer.withValues(alpha: .82),
      _GoalState.reached ||
      _GoalState.exceeded => colors.tertiaryContainer.withValues(alpha: .82),
      _ => colors.primaryContainer.withValues(alpha: .82),
    };
    return GlassSurface(
      key: ValueKey('daily-goal-state-${goalState.name}'),
      elevation: Elevation.hero,
      padding: const EdgeInsets.all(Space.xl),
      tint: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // No badge alongside the eyebrow: the card is already coloured by
              // its state, and a coin next to the words "true profit" restated
              // what they say.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRUE PROFIT',
                      // The hero-eyebrow rank shared with Coach and History.
                      // The accent colour stays: here it is carrying the goal
                      // state, which is information rather than decoration.
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accent,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _goalStatus(goalState),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  // Without shifts there is no keep rate; "0% kept" would read
                  // as a catastrophic day rather than an empty one.
                  hasShifts ? '${Money.percent(keepRate)} kept' : '— kept',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Space.gapXl,
          Semantics(
            liveRegion: true,
            label: hasShifts
                ? 'True profit today ${units.cents(net)}'
                : 'No sessions added today',
            child: ExcludeSemantics(
              child: AnimatedMoney(
                value: net,
                units: units,
                // One token for a hero figure across the app. `displaySmall`
                // renders at the same 40pt, but naming it differently here was
                // how the three heroes drifted apart in the first place.
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(color: colors.onSurface),
              ),
            ),
          ),
          Space.gapXl,
          TweenAnimationBuilder<double>(
            tween: Tween(begin: progress, end: progress),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 7,
              borderRadius: BorderRadius.circular(Radii.pill),
              color: accent,
              backgroundColor: isLoss
                  ? colors.onSurface.withValues(alpha: .12)
                  : accent.withValues(alpha: .13),
            ),
          ),
          // Below the bar, not above it: the bar is the picture of where the
          // day stands and this line is its caption.
          Space.gapXs,
          _GoalLine(
            goalState: goalState,
            net: net,
            target: target,
            units: units,
            onEditGoal: onEditGoal,
          ),
        ],
      ),
    );
  }

  /// Says what the figure below is, not how it compares to the goal — the goal
  /// line does that now, and stating it twice on one card just made a reached
  /// goal announce itself in two consecutive sentences.
  static String _goalStatus(_GoalState goalState) => switch (goalState) {
    _GoalState.noActivity => 'No sessions added today',
    _GoalState.loss => 'You spent more than you earned',
    _ => 'After driving costs',
  };
}

/// The tappable goal line under the profit figure.
///
/// States the gap rather than the score: `$0 / $100` makes a driver do the
/// subtraction themselves, and the number they actually act on is how much
/// further they have to drive. The pencil is what marks the line as an editable
/// setting rather than another read-only stat on a card full of them.
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.goalState,
    required this.net,
    required this.target,
    required this.units,
    required this.onEditGoal,
  });

  final _GoalState goalState;
  final double net;
  final double target;
  final MeasurementUnits units;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodySmall;
    final (amount, rest) = _copy;

    return InkWell(
      key: const ValueKey('daily-goal-line'),
      onTap: onEditGoal,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Large goals and big losses make this line long; it shrinks rather
            // than wrapping or running off the card, and the pencil stays
            // pinned to the end of the sentence where it reads as its affordance.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (amount != null)
                        TextSpan(
                          text: '$amount ',
                          style: body?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      TextSpan(text: rest),
                    ],
                  ),
                  maxLines: 1,
                  style: body?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: Space.xs + 1),
            Icon(Icons.edit_outlined, size: 15, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// The emphasised figure, and the sentence it sits in. Split so the amount
  /// can carry the weight and the tabular digits while the words around it stay
  /// quiet — and so a reached goal, which has no gap left to state, can drop
  /// the figure entirely instead of announcing `$0.00`.
  (String?, String) get _copy => switch (goalState) {
    _GoalState.reached => (null, 'Today’s ${units.whole(target)} goal reached'),
    _GoalState.exceeded => (
      units.cents(net - target),
      'past today’s ${units.whole(target)} goal',
    ),
    // A loss counts the whole way back plus the hole, which is the real
    // distance left to drive.
    _ => (units.cents(target - net), 'to today’s ${units.whole(target)} goal'),
  };
}

enum _GoalState {
  noActivity,
  loss,
  inProgress,
  reached,
  exceeded;

  static _GoalState from({
    required double net,
    required double target,
    required bool hasShifts,
  }) {
    if (!hasShifts) return noActivity;
    // A losing day is the moment this app exists for, so it gets its own
    // state rather than sitting quietly at the bottom of "in progress".
    if (net < 0) return loss;
    if (net > target) return exceeded;
    if (net == target) return reached;
    return inProgress;
  }
}

class _PerformancePanel extends StatelessWidget {
  const _PerformancePanel({
    required this.netPerHour,
    required this.netPerMile,
    required this.miles,
    required this.shiftCount,
    required this.units,
  });

  final double? netPerHour;

  /// Per mile as stored; converted to the driver's unit for display.
  final double? netPerMile;
  final double miles;
  final int shiftCount;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(Space.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCardTitle(icon: Icons.speed_rounded, title: 'Performance'),
        Space.gapLg,
        // The shared panel, as on Coach and History. This grid used to fence
        // each figure off from its neighbours with hairline rules and a
        // divider, which is the exact treatment [MetricPanel] exists to
        // replace: six ruled cells read as a table competing with the hero
        // above them.
        MetricPanel(
          rows: [
            [
              (
                label: 'Net / hour',
                value: netPerHour == null ? '—' : units.cents(netPerHour!),
                loss: false,
              ),
              (
                label: 'Net / ${units.distance.singular}',
                value: netPerMile == null ? '—' : units.cents(netPerMile!),
                loss: false,
              ),
            ],
            [
              (
                label: units.distance.label,
                value: miles.toStringAsFixed(1),
                loss: false,
              ),
              (label: 'Sessions', value: '$shiftCount', loss: false),
            ],
          ],
        ),
      ],
    ),
  );
}

class _NextMove extends StatelessWidget {
  const _NextMove({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(Space.xl),
    // Coach's insight card, which is what this has always been: an icon, the
    // heading it belongs to, and the sentence underneath. It was hand-rolled
    // with its own eyebrow, its own gaps and its own line height, so the same
    // reading looked like a different component depending on which of the two
    // screens the driver was standing on.
    child: SectionCardTitle(
      icon: Icons.auto_awesome_rounded,
      title: 'Your next move',
      subtitle: message,
    ),
  );
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shift, required this.units, this.onTap});

  final Shift shift;
  final MeasurementUnits units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLoss = shift.netProfit < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        padding: EdgeInsets.zero,
        radius: 14,
        elevation: Elevation.flat,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  PlatformLogo(
                    key: ValueKey('shift-platform-logo-${shift.id}'),
                    platform: shift.platform,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                shift.platform.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (shift.source == ShiftSource.imported) ...[
                              const SizedBox(width: Space.sm),
                              const _ImportedChip(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // When it was, and how long it ran. Miles used to sit
                        // here too, but on a row already carrying a platform,
                        // a date and a profit figure they were the one number
                        // nobody was reading — and they are on the shift's own
                        // screen, one tap away.
                        Text(
                          '${_dateLabel(context)} · '
                          '${shift.hours.toStringAsFixed(1)} hr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  // The figure alone, with no "Net" caption under it. Every
                  // money figure on this screen is already what was kept — the
                  // card above says so in letters twice the size — and a label
                  // on one row of one list only raised the question of what the
                  // unlabelled ones were.
                  Text(
                    units.cents(shift.netProfit),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isLoss ? colors.error : colors.primary,
                      fontWeight: FontWeight.w800,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: Space.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _dateLabel(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final completed = DateUtils.dateOnly(shift.completedAt);
    if (completed == today) return 'Today';
    if (completed == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return MaterialLocalizations.of(context).formatShortDate(shift.completedAt);
  }
}

/// Marks a shift that came from a connected account. Those carry no fuel,
/// tolls or parking, so their keep rate reads high until the driver adds them.
class _ImportedChip extends StatelessWidget {
  const _ImportedChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Imported',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
