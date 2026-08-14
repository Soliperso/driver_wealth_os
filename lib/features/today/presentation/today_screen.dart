import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../accounts/presentation/platform_logo.dart';
import '../../driving/domain/driving_session.dart';
import '../../driving/presentation/driving_hero.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_summary.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.driverName,
    required this.shifts,
    required this.dailyGoal,
    required this.onAddShift,
    required this.onConnectAccounts,
    required this.onDailyGoalChanged,
    this.onOpenShift,
    this.onOpenSettings,
    this.onRefresh,
    this.drivingSession,
    this.drivingBackgroundLimited = false,
    this.drivingTrackingInterrupted = false,
    this.onStartDriving,
    this.onEndShift,
    this.onUpgradeBackground,
    this.drivingRefreshInterval = const Duration(seconds: 1),
    this.pendingDraft,
    this.onResumeDraft,
    this.onDiscardDraft,
    this.storageError,
  });

  final String driverName;
  final List<Shift> shifts;
  final double dailyGoal;
  final VoidCallback onAddShift;
  final VoidCallback onConnectAccounts;
  final ValueChanged<double> onDailyGoalChanged;
  final ValueChanged<Shift>? onOpenShift;
  final VoidCallback? onOpenSettings;
  final Future<void> Function()? onRefresh;

  /// Non-null while a driving session is running.
  final DrivingSession? drivingSession;
  final bool drivingBackgroundLimited;
  final bool drivingTrackingInterrupted;
  final VoidCallback? onStartDriving;
  final Future<void> Function()? onEndShift;
  final Future<void> Function()? onUpgradeBackground;

  /// Null freezes the live clock. See [DrivingHero.refreshInterval].
  final Duration? drivingRefreshInterval;

  /// A tracked shift still waiting on its earnings.
  final Shift? pendingDraft;
  final VoidCallback? onResumeDraft;
  final VoidCallback? onDiscardDraft;

  /// Non-null when the last write to device storage failed.
  final String? storageError;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
            _formattedDate(DateTime.now()),
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
                const SizedBox(height: 16),
              ],
              // Unfinished tracked driving outranks everything else on the
              // screen: it is the only thing here that can still be lost.
              if (pendingDraft != null && drivingSession == null) ...[
                _TrackedDraftCard(
                  draft: pendingDraft!,
                  onResume: onResumeDraft,
                  onDiscard: onDiscardDraft,
                ),
                const SizedBox(height: 16),
              ],
              // Mid-shift the live session is what the driver opened the app
              // to see, so it takes the hero slot until the shift ends.
              if (drivingSession != null)
                DrivingHero(
                  session: drivingSession!,
                  backgroundLimited: drivingBackgroundLimited,
                  trackingInterrupted: drivingTrackingInterrupted,
                  onEndShift: onEndShift ?? () async {},
                  onUpgradeBackground: onUpgradeBackground,
                  refreshInterval: drivingRefreshInterval,
                )
              else ...[
                _ProfitHero(
                  net: net,
                  keepRate: keepRate,
                  target: target,
                  hasShifts: summary.shiftCount > 0,
                  onEditGoal: () => _editDailyGoal(context),
                ),
                const SizedBox(height: 16),
                if (onStartDriving != null)
                  _StartDrivingCard(
                    onStart: onStartDriving!,
                    onEnterManually: onAddShift,
                  )
                else
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: onAddShift,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Enter a shift manually'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              _ConnectAccountsCard(
                compact: summary.shiftCount > 0,
                onConnect: onConnectAccounts,
              ),
              if (summary.shiftCount > 0) ...[
                const SizedBox(height: 16),
                _PerformancePanel(
                  netPerHour: summary.hours == 0 ? null : summary.netPerHour,
                  netPerMile: summary.miles == 0 ? null : summary.netPerMile,
                  miles: summary.miles,
                  shiftCount: summary.shiftCount,
                ),
                const SizedBox(height: 16),
                _NextMove(
                  message: _nextMove(
                    hasShifts: true,
                    net: net,
                    target: target,
                    keepRate: keepRate,
                    netPerHour: summary.netPerHour,
                  ),
                ),
              ],
              // "Recent" means the latest shifts overall, so this is gated on
              // having any history at all rather than on having driven today.
              if (recentShifts.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionHeader(onAddShift: onAddShift),
                const SizedBox(height: 12),
                ...recentShifts.map(
                  (shift) => _ShiftRow(
                    shift: shift,
                    onTap: onOpenShift == null
                        ? null
                        : () => onOpenShift!(shift),
                  ),
                ),
              ],
              const SizedBox(height: 92),
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
  }) {
    if (!hasShifts) {
      return 'Add one completed shift to reveal your true hourly profit and keep rate.';
    }
    if (net < 0) {
      return 'Today’s driving cost ${Money.cents(net.abs())} more than it earned. '
          'Check the shift’s mileage and expenses before repeating this pattern.';
    }
    if (net >= target) {
      return 'You reached today’s profit goal. Review this shift before deciding whether more driving is worth it.';
    }
    if (keepRate < .65) {
      return 'Your keep rate is below 65%. Check mileage and direct costs before repeating this shift pattern.';
    }
    if (netPerHour >= 25) {
      return 'This is a healthy hourly pace. You’re '
          '${Money.whole((target - net).clamp(0, target).toDouble())} from today’s goal.';
    }
    return 'You’re ${Money.whole((target - net).clamp(0, target).toDouble())} '
        'from today’s goal. Compare your next shift’s hours and miles carefully.';
  }

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
          Row(
            children: [
              const SoftIcon(Icons.play_arrow_rounded),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Not driving',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Track your hours and miles automatically while you work.',
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
            key: const ValueKey('start-driving-button'),
            onPressed: onStart,
            child: const Text('START DRIVING'),
          ),
          const SizedBox(height: Space.xs),
          TextButton.icon(
            onPressed: onEnterManually,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Enter a shift manually'),
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
    required this.onResume,
    required this.onDiscard,
  });

  final Shift draft;
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
                      'Shift waiting on earnings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${Money.hours(draft.hours)} and '
                      '${Money.number(draft.miles)} miles tracked on '
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
            child: const Text('ENTER EARNINGS'),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            key: const ValueKey('discard-draft-button'),
            onPressed: onDiscard,
            child: const Text('Discard this shift'),
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

class _ConnectAccountsCard extends StatelessWidget {
  const _ConnectAccountsCard({required this.compact, required this.onConnect});

  final bool compact;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: EdgeInsets.all(compact ? 18 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SoftIcon(Icons.sync_rounded),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      compact
                          ? 'Work accounts'
                          : 'Bring in earnings automatically',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      compact
                          ? 'Combine income from every platform you use.'
                          : 'Connect Uber, Lyft, DoorDash and more. We’ll combine your income into one clear view.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.42,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 16 : 20),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.add_link_rounded, size: 20),
            label: const Text('Connect work accounts'),
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
    required this.onEditGoal,
  });

  final double net;
  final double keepRate;
  final double target;
  final bool hasShifts;
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
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: .20)),
                ),
                child: Icon(
                  switch (goalState) {
                    _GoalState.loss => Icons.trending_down_rounded,
                    _GoalState.reached ||
                    _GoalState.exceeded => Icons.check_rounded,
                    _ => Icons.paid_outlined,
                  },
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRUE PROFIT',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _goalStatus(goalState, net, target),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(99),
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
                ? 'True profit today ${Money.cents(net)}'
                : 'No shifts added today',
            child: ExcludeSemantics(
              child: AnimatedMoney(
                value: net,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: colors.onSurface),
              ),
            ),
          ),
          Space.gapXl,
          InkWell(
            onTap: onEditGoal,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                // Label hugs the left, amount hugs the right; the slack sits
                // between them instead of trailing the amount.
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Daily goal',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: Space.xs + 1),
                        Icon(
                          Icons.edit_outlined,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  // Large goals and big losses make this pair long; it shrinks
                  // rather than running off the card.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${Money.whole(net)} / ${Money.whole(target)}',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
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
        ],
      ),
    );
  }

  static String _goalStatus(_GoalState goalState, double net, double target) =>
      switch (goalState) {
        _GoalState.noActivity => 'No shifts added today',
        _GoalState.loss => 'You spent more than you earned',
        _GoalState.inProgress => 'After driving costs',
        _GoalState.reached => 'Daily goal reached',
        _GoalState.exceeded => 'Goal exceeded by ${Money.cents(net - target)}',
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
  });

  final double? netPerHour;
  final double? netPerMile;
  final double miles;
  final int shiftCount;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              _Stat(
                label: 'Net / hour',
                value: netPerHour == null ? '—' : Money.cents(netPerHour!),
                icon: Icons.schedule_rounded,
              ),
              _Stat(
                label: 'Net / mile',
                value: netPerMile == null ? '—' : Money.cents(netPerMile!),
                icon: Icons.route_rounded,
              ),
              _Stat(
                label: 'Miles',
                value: miles.toStringAsFixed(1),
                icon: Icons.directions_car_outlined,
              ),
              _Stat(
                label: 'Shifts',
                value: '$shiftCount',
                icon: Icons.work_outline_rounded,
              ),
            ];
            if (constraints.maxWidth < 560) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: stats[0]),
                      const _VerticalRule(),
                      Expanded(child: stats[1]),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Row(
                    children: [
                      Expanded(child: stats[2]),
                      const _VerticalRule(),
                      Expanded(child: stats[3]),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: stats[0]),
                const _VerticalRule(),
                Expanded(child: stats[1]),
                const _VerticalRule(),
                Expanded(child: stats[2]),
                const _VerticalRule(),
                Expanded(child: stats[3]),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
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
    height: 48,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5),
  );
}

class _NextMove extends StatelessWidget {
  const _NextMove({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftIcon(Icons.auto_awesome_rounded, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your next move',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onAddShift});

  final VoidCallback onAddShift;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Recent shifts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      FilledButton.icon(
        onPressed: onAddShift,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add shift'),
      ),
    ],
  );
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shift, this.onTap});

  final Shift shift;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLoss = shift.netProfit < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassSurface(
        padding: EdgeInsets.zero,
        radius: 18,
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: PlatformLogo(
              key: ValueKey('shift-platform-logo-${shift.id}'),
              platform: shift.platform,
              size: 42,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    shift.platform.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (shift.source == ShiftSource.imported) ...[
                  const SizedBox(width: 8),
                  const _ImportedChip(),
                ],
              ],
            ),
            subtitle: Text(
              '${shift.hours.toStringAsFixed(1)} hrs · ${shift.miles.toStringAsFixed(0)} miles',
            ),
            trailing: Text(
              Money.cents(shift.netProfit),
              style: TextStyle(
                color: isLoss ? colors.error : colors.primary,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
        ),
      ),
    );
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
