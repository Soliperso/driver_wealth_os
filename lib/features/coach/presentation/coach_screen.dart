import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_money.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/learning_progress.dart';
import '../../../core/widgets/metric_panel.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/section_card_title.dart';
import '../../../core/widgets/section_heading.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../settings/domain/driver_preferences.dart';
import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift.dart';
import '../domain/coach_engine.dart';
import 'best_times_screen.dart';

/// What to do next, and why.
///
/// Built on the same vocabulary as History — the shared [SectionHeading],
/// [SectionCardTitle], [MetricPanel] and [LearningProgress] — because the two
/// screens report on the same numbers and previously read as though they came
/// from different apps. Coach's own job is the sentence beside each figure; the
/// figures themselves are drawn the way the rest of the app draws them.
///
/// Deliberately unscoped: there is no period selector here. Each insight is
/// computed at the window that makes it true — today for the next move, this
/// week for performance, all reviewed history for patterns, leaks and costs —
/// and a Day/Week/Month/Year control would only invite the question of what
/// "your next move" means for a week last March.
class CoachScreen extends StatefulWidget {
  const CoachScreen({
    super.key,
    required this.shifts,
    required this.preferences,
    this.onAddShift,
    this.onRefresh,
    this.clock,
  });

  final List<Shift> shifts;
  final DriverPreferences preferences;

  final VoidCallback? onAddShift;

  /// Pull-to-refresh, as on Today and History. Imported earnings arrive from
  /// the network, and Coach is drawing conclusions from them.
  final Future<void> Function()? onRefresh;

  final DateTime Function()? clock;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  late CoachDashboard _dashboard;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(CoachScreen old) {
    super.didUpdateWidget(old);
    // The shift list is mutated in place upstream, so neither its identity nor
    // its length reliably signals an edit. A parent rebuild is the signal.
    _recompute();
  }

  /// Every insight is a full scan of the shift list, so the dashboard is built
  /// once per data change and held — never inside [build].
  void _recompute() {
    _dashboard = CoachEngine.dashboard(
      shifts: widget.shifts,
      dailyGoal: widget.preferences.dailyGoal,
      // Re-read rather than caching from [initState]. Held across midnight, a
      // frozen clock keeps calling a finished day "today" and answers the next
      // move from yesterday's earnings.
      now: (widget.clock ?? DateTime.now)(),
      hourlyFloor: widget.preferences.hourlyFloor,
      weekStartsOn: widget.preferences.weekStartsOn,
      drivingDaysPerWeek: widget.preferences.drivingDaysPerWeek,
      units: widget.preferences.units,
    );
  }

  @override
  Widget build(BuildContext context) {
    final add = widget.onAddShift;
    return SoftScaffold(
      title: 'Profit coach',
      actions: [
        if (add != null)
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: IconButton(
              tooltip: 'Add session',
              onPressed: add,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
      ],
      body: PageFrame(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh ?? () async {},
          child: widget.shifts.isEmpty
              ? _EmptyCoach(onAddShift: add)
              : _buildReport(),
        ),
      ),
    );
  }

  /// The Best-times route, or null while there is nothing ranked to open.
  ///
  /// Attached to whichever surface is showing the opportunity insight — the
  /// card, or the hero on a day when that reading was promoted to the top of
  /// the screen. The two never render at once, so the key stays unique.
  VoidCallback? get _openBestTimes => _dashboard.canOpenBestTimes
      ? () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BestTimesScreen(
              patterns: _dashboard.patterns,
              units: widget.preferences.units,
            ),
          ),
        )
      : null;

  Widget _buildReport() {
    final units = widget.preferences.units;
    final priority = _dashboard.priority;
    // The hero *is* one of these readings, not a summary of them. Rendering it
    // again as a card below printed the same sentence and the same figure
    // twice on one screen.
    final performance = [
      _dashboard.weekly,
      // The ranked-patterns reading and the way through to the full ranking
      // are one card, not two. They were separate, and said the same thing
      // twice under the same icon: "1 of 4 patterns tracked" printed
      // back-to-back while learning, and the same window with the same True
      // hourly once ready.
      _dashboard.opportunity,
    ].where((insight) => !identical(insight, priority)).toList();
    final more = [
      _dashboard.leak,
      _dashboard.cost,
    ].where((insight) => !identical(insight, priority)).toList();

    return ListView(
      children: [
        _PriorityInsight(
          insight: priority,
          units: units,
          onTap: priority.kind == CoachInsightKind.opportunity
              ? _openBestTimes
              : null,
          tapKey: const ValueKey('coach-best-times'),
        ),
        if (performance.isNotEmpty) ...[
          Space.gapXl,
          const SectionHeading(title: 'YOUR PERFORMANCE'),
          Space.gapMd,
          // Spaced by prefixing a gap to each card that will actually render,
          // rather than a hardcoded gap per card. This is History's rule, and
          // it is what keeps the page's rhythm from depending on which widget
          // you ask — which matters here, where any card may be absent.
          for (final (index, insight) in performance.indexed) ...[
            if (index > 0) Space.gapLg,
            _InsightCard(
              key: _keyFor(insight),
              insight: insight,
              tapKey: const ValueKey('coach-best-times'),
              onTap: insight.kind == CoachInsightKind.opportunity
                  ? _openBestTimes
                  : null,
            ),
          ],
        ],
        if (more.isNotEmpty) ...[
          Space.gapXl,
          const SectionHeading(title: 'MORE FROM YOUR NUMBERS'),
          Space.gapMd,
          for (final (index, insight) in more.indexed) ...[
            if (index > 0) Space.gapLg,
            _InsightCard(key: _keyFor(insight), insight: insight),
          ],
        ],
        Space.gapXl,
        _SuggestedQuestions(questions: _dashboard.questions),
        // A page-level footnote, so it takes the page's section break rather
        // than the tighter gap that made it read as part of the chat card.
        Space.gapXl,
        Text(
          'Recommendations use only your saved sessions, preferences and '
          'calculated profit. They are not financial or tax advice.',
          // `bodySmall` is already muted and already carries its line height.
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: Space.bottomNavClearance),
      ],
    );
  }

  /// Keyed by what the card is about rather than by position, since any card
  /// may be absent on a given day.
  static Key? _keyFor(CoachInsight insight) => switch (insight.kind) {
    CoachInsightKind.weekly => const ValueKey('coach-weekly-performance'),
    CoachInsightKind.opportunity => const ValueKey('coach-best-opportunity'),
    CoachInsightKind.leak => const ValueKey('coach-money-leak'),
    CoachInsightKind.cost => const ValueKey('coach-cost-insight'),
    CoachInsightKind.goal || CoachInsightKind.start => null,
  };
}

/// The screen's headline: the one move worth making next, and the figure it is
/// about.
///
/// This card used to be prose alone — an icon over three lines of sentence —
/// while History's hero led with a number the size of the page. A coach that
/// never shows a figure reads as advice rather than as a reading of the
/// driver's own data.
class _PriorityInsight extends StatelessWidget {
  const _PriorityInsight({
    required this.insight,
    required this.units,
    this.onTap,
    this.tapKey,
  });

  final CoachInsight insight;
  final MeasurementUnits units;

  /// Set when the promoted reading is one that leads somewhere.
  final VoidCallback? onTap;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final headline = insight.headline;
    final tap = onTap;

    final body = Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            // Every child of this row is a single line, so they centre on the
            // icon rather than each being nudged down by a hand-picked top
            // padding — which is what the eyebrow and the chevron used to do,
            // at two different values.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SoftIcon(_icon(insight.kind), size: 20),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  // Uppercased here rather than in the engine: the label is
                  // sentence case so it reads correctly as a [StatTile] label
                  // on a card, and [StatEmphasis.compact] does this same
                  // transform there.
                  (headline?.heroLabel ?? 'Your next move').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
          // The eyebrow labels whatever leads the card — the figure, or the
          // title when there is no figure — so it binds tight to it at the
          // same gap History's hero uses. The rank is carried by the size
          // contrast, not by the gap.
          Space.gapXs,
          if (headline != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoney(
                  value: headline.value,
                  units: units,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
                    color: headline.loss ? colors.error : null,
                  ),
                ),
              ),
            ),
            // The figure is its own tier; the title and message below it are
            // one block. A gap here equal to the title/message gap glued the
            // figure to the sentence and left the card with no rhythm.
            Space.gapLg,
          ],
          Text(
            insight.title,
            // Down from headlineSmall: with a figure above it, the title is no
            // longer the biggest thing on the card and should not be drawn as
            // though it were. One step above the [SectionCardTitle] used by the
            // supporting cards — which is the whole of the rank it needs, and
            // which it did not actually have while both were `titleMedium`.
            //
            // The theme's own w700, not the w800 this used to force: at 22pt
            // the extra weight put the title level with the figure above it and
            // the card had two things shouting. Size carries the rank here.
            // onSurfaceVariant dims the color to soften the hierarchy below the
            // figure without losing readability.
            style: textTheme.titleLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          // [SectionCardTitle]'s title-to-subtitle gap, because this is the
          // same pairing one rank up.
          Space.gapSm,
          Text(
            insight.message,
            // Line height comes from the theme. Coach was setting 1.4, 1.45 and
            // 1.48 on body text within one screen.
            style: textTheme.bodyMedium,
          ),
          if (insight.figures.isNotEmpty) ...[
            Space.gapLg,
            MetricPanel(rows: [insight.figures]),
          ],
        ],
      ),
    );

    return GlassSurface(
      elevation: Elevation.hero,
      padding: EdgeInsets.zero,
      // History's value. The old .72 was set behind a card carrying nothing but
      // a sentence; the same saturation under a figure and a metric panel made
      // the card shout.
      tint: colors.primaryContainer.withValues(alpha: .55),
      child: tap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: tapKey,
                onTap: tap,
                borderRadius: BorderRadius.circular(Radii.xl),
                child: body,
              ),
            ),
    );
  }
}

/// One of Coach's supporting readings.
///
/// Structurally identical to History's analytics cards, on purpose: same
/// surface rank, same padding, same icon-led heading, and the same honest
/// progress bar where a conclusion is not yet supported. The card previously
/// sat on the *lowest* rank with an eyebrow of its own and a static `LEARNING`
/// chip that reported no progress at all.
class _InsightCard extends StatelessWidget {
  const _InsightCard({
    super.key,
    required this.insight,
    this.onTap,
    this.tapKey,
  });

  final CoachInsight insight;

  /// Set when the card leads somewhere — currently only the ranked patterns.
  /// Null leaves the card inert, which is also what a card still learning
  /// should be: there is nothing to open yet.
  final VoidCallback? onTap;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final progress = insight.progress;
    final tap = onTap;
    final headline = insight.headline;
    // A card has no big figure of its own, so the headline joins the row it
    // leads. The hero counts it up instead, which is why the engine keeps it
    // out of [CoachInsight.figures] rather than letting both render it.
    final tiles = <PanelMetric>[
      if (headline != null)
        (label: headline.label, value: headline.text, loss: headline.loss),
      ...insight.figures,
    ];
    final body = Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCardTitle(
            icon: _icon(insight.kind),
            title: insight.title,
            subtitle: insight.message,
            trailing: tap == null
                ? null
                : Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
          // One heading-to-content gap, whichever of the two bodies a card
          // happens to be showing. A bar at 12 and a panel at 16 made two cards
          // sitting on top of each other breathe differently.
          if (progress != null) ...[
            Space.gapLg,
            LearningProgress(
              done: progress.done,
              needed: progress.needed,
              caption: progress.caption,
            ),
          ] else if (tiles.isNotEmpty) ...[
            Space.gapLg,
            MetricPanel(rows: [tiles]),
          ],
        ],
      ),
    );

    return GlassSurface(
      padding: EdgeInsets.zero,
      child: tap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: tapKey,
                onTap: tap,
                borderRadius: BorderRadius.circular(Radii.lg),
                child: body,
              ),
            ),
    );
  }
}

class _SuggestedQuestions extends StatefulWidget {
  const _SuggestedQuestions({required this.questions});

  final List<CoachQuestion> questions;

  @override
  State<_SuggestedQuestions> createState() => _SuggestedQuestionsState();
}

class _SuggestedQuestionsState extends State<_SuggestedQuestions> {
  CoachQuestion? _selected;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCardTitle(
            icon: Icons.forum_rounded,
            title: 'Coach chat',
            subtitle: 'Choose a question for an answer calculated from your '
                'saved history.',
            trailing: const _LocalPill(),
          ),
          Space.gapLg,
          if (_selected != null) ...[
            _ChatBubble(message: _selected!.prompt, fromCoach: false),
            Space.gapSm,
            _ChatBubble(message: _selected!.answer, fromCoach: true),
            Space.gapLg,
          ],
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final (index, question) in widget.questions.indexed)
                ActionChip(
                  key: ValueKey('coach-question-$index'),
                  avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(question.prompt),
                  onPressed: () => setState(() => _selected = question),
                ),
            ],
          ),
          if (_selected != null) ...[
            Space.gapMd,
            Text(
              'Simulated locally from saved sessions. No AI service is connected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Says the answers never left the phone.
class _LocalPill extends StatelessWidget {
  const _LocalPill();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        'LOCAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.fromCoach});

  final String message;
  final bool fromCoach;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: fromCoach ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: fromCoach
                ? colors.surfaceContainerHighest.withValues(alpha: .72)
                : colors.primary.withValues(alpha: .14),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(Radii.md),
              topRight: const Radius.circular(Radii.md),
              bottomLeft: Radius.circular(fromCoach ? 4 : Radii.md),
              bottomRight: Radius.circular(fromCoach ? Radii.md : 4),
            ),
          ),
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

/// A driver with no history at all.
///
/// Coach used to render its full four-card wall here, every one of them a
/// learning state — a page that said "not yet" five times over. Built like
/// History's empty state so the first screen of both reads the same.
class _EmptyCoach extends StatelessWidget {
  const _EmptyCoach({required this.onAddShift});

  final VoidCallback? onAddShift;

  @override
  Widget build(BuildContext context) {
    final add = onAddShift;
    return EmptyStateCard(
      key: const ValueKey('coach-empty'),
      icon: Icons.auto_awesome_rounded,
      title: 'Nothing to coach yet',
      message: 'Coach needs earnings, hours, distance and costs before '
          'it can compare which of your sessions actually paid.',
      action: add == null
          ? null
          : OutlinedButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add first session'),
            ),
    );
  }
}

IconData _icon(CoachInsightKind kind) => switch (kind) {
  CoachInsightKind.start => Icons.add_chart_rounded,
  CoachInsightKind.goal => Icons.flag_rounded,
  CoachInsightKind.weekly => Icons.calendar_view_week_rounded,
  CoachInsightKind.opportunity => Icons.fingerprint_rounded,
  CoachInsightKind.leak => Icons.trending_down_rounded,
  CoachInsightKind.cost => Icons.local_gas_station_outlined,
};
