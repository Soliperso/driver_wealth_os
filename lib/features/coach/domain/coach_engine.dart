import '../../settings/domain/measurement_units.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_analytics.dart';
import '../../shifts/domain/shift_summary.dart';

/// One supporting figure under an insight: what it is called, what it reads,
/// and whether it is describing a loss.
typedef CoachFigure = ({String label, String value, bool loss});

/// The single figure an insight is about.
///
/// Carries both the number and its rendered form: the hero counts up to
/// [value] under `heroLabel`, while a card shows `text` in a tile under
/// `label`. [CoachInsight.figures] holds the *other* figures and never repeats
/// this one, so no surface prints the same number twice.
///
/// Two labels because the two surfaces have very different room. A tile in a
/// row of three has about eight characters before it ellipsizes on a 320pt
/// phone — which is why History's own panel reads "Gross", "Costs", "Net / hr"
/// — while the hero's label owns a full line and can say what it means.
typedef CoachHeadline = ({
  String label,
  String heroLabel,
  String text,
  double value,
  bool loss,
});

/// What an insight is still waiting for before it can say anything true.
typedef CoachProgress = ({int done, int needed, String caption});

class CoachEngine {
  const CoachEngine._();

  /// Compatibility entry point for callers that only need the ordered feed.
  static List<CoachInsight> build({
    required Iterable<Shift> shifts,
    required double dailyGoal,
    DateTime? now,
    double hourlyFloor = 0,
    int weekStartsOn = DateTime.monday,
    int drivingDaysPerWeek = 0,
    MeasurementUnits units = const MeasurementUnits(),
  }) {
    final result = dashboard(
      shifts: shifts,
      dailyGoal: dailyGoal,
      now: now,
      hourlyFloor: hourlyFloor,
      weekStartsOn: weekStartsOn,
      drivingDaysPerWeek: drivingDaysPerWeek,
      units: units,
    );
    return result.priority.kind == CoachInsightKind.start
        ? [result.priority]
        : result.feed;
  }

  static CoachDashboard dashboard({
    required Iterable<Shift> shifts,
    required double dailyGoal,
    DateTime? now,
    double hourlyFloor = 0,
    int weekStartsOn = DateTime.monday,
    int drivingDaysPerWeek = 0,
    MeasurementUnits units = const MeasurementUnits(),
  }) {
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      unique.putIfAbsent(shift.id, () => shift);
    }
    final all = unique.values.toList();
    final reviewed = all.where((shift) => shift.costsReviewed).toList();
    final current = now ?? DateTime.now();
    final weekly = ShiftAnalytics.weekly(
      all,
      now: current,
      weekStartsOn: weekStartsOn,
    );
    final today = ShiftSummary.from(
      all.where((shift) => shift.occurredOn(current)),
    );
    final patterns = ShiftAnalytics.earningsPatterns(
      reviewed.where((shift) => shift.hours > 0),
    );
    final gradedPatterns = patterns
        .where((pattern) => pattern.grade != PatternGrade.pending)
        .toList();
    final leaks = ShiftAnalytics.moneyLeaks(
      reviewed,
      hourlyFloor: hourlyFloor,
      units: units,
    );
    final costShifts = reviewed
        .where((shift) => shift.miles > 0 || shift.directExpenses > 0)
        .toList();

    if (all.isEmpty) {
      const starter = CoachInsight(
        title: 'Add your first completed session',
        message:
            'Your coach needs earnings, hours, distance and costs before it can compare profitable patterns.',
        kind: CoachInsightKind.start,
        isReady: false,
      );
      return const CoachDashboard(
        priority: starter,
        weekly: CoachInsight(
          title: 'Weekly performance',
          message:
              'Complete a session to start your first weekly comparison.',
          kind: CoachInsightKind.weekly,
          isReady: false,
          progress: (done: 0, needed: 1, caption: '0 of 1 sessions this week'),
        ),
        opportunity: CoachInsight(
          title: 'Best opportunity',
          message:
              'Complete sessions on different days and times to build your Earnings DNA.',
          kind: CoachInsightKind.opportunity,
          isReady: false,
          progress: (done: 0, needed: 4, caption: '0 of 4 patterns tracked'),
        ),
        leak: CoachInsight(
          title: 'Money leak',
          message:
              'Review earnings, hours and costs on completed sessions before Coach flags a weak one.',
          kind: CoachInsightKind.leak,
          isReady: false,
          progress: (
            done: 0,
            needed: 3,
            caption: '0 of 3 reviewed sessions',
          ),
        ),
        cost: CoachInsight(
          title: 'Cost insight',
          message:
              'Record distance, fuel, tolls or parking to see how driving costs affect True Profit.',
          kind: CoachInsightKind.cost,
          isReady: false,
          progress: (
            done: 0,
            needed: 1,
            caption: 'No reviewed costs recorded yet',
          ),
        ),
        questions: [
          CoachQuestion(
            prompt: 'What should I track first?',
            answer:
                'Start with gross earnings, driving time, distance and direct expenses. Coach uses those saved fields to calculate True Profit, True hourly and True per mile.',
          ),
        ],
        patterns: [],
        reviewedShiftCount: 0,
      );
    }

    final weeklyInsight = _weeklyInsight(
      weekly,
      dailyGoal: dailyGoal,
      drivingDaysPerWeek: drivingDaysPerWeek,
      units: units,
      hasUnreviewed: reviewed.length != all.length,
    );
    final opportunityInsight = _opportunityInsight(
      patterns,
      gradedPatterns,
      units: units,
    );
    final leakInsight = _leakInsight(
      leaks,
      reviewedShiftCount: reviewed.length,
      units: units,
    );
    final costInsight = _costInsight(
      costShifts,
      reviewedShiftCount: reviewed.length,
      units: units,
    );

    final priority = _priorityInsight(
      today: today,
      dailyGoal: dailyGoal,
      leak: leakInsight,
      opportunity: opportunityInsight,
      hasLeak: leaks.isNotEmpty,
      hasGradedPattern: gradedPatterns.isNotEmpty,
      weekly: weeklyInsight,
      units: units,
    );
    final questions = _questions(
      weekly: weekly,
      weeklyInsight: weeklyInsight,
      patterns: gradedPatterns,
      leaks: leaks,
      costShifts: costShifts,
      costInsight: costInsight,
      units: units,
    );

    return CoachDashboard(
      priority: priority,
      weekly: weeklyInsight,
      opportunity: opportunityInsight,
      leak: leakInsight,
      cost: costInsight,
      questions: questions,
      patterns: patterns,
      reviewedShiftCount: reviewed.length,
    );
  }

  /// Which of the day's readings deserves the top of the screen.
  ///
  /// A *selection* among the insights, not a fifth insight built from the same
  /// data: rebuilding one meant the hero and the card below it printed the same
  /// sentence and the same figure, with no way for the screen to know they were
  /// the same reading. Returning the very object lets the screen skip the
  /// duplicate by identity. Today's goal is the one case with no card of its
  /// own, so it is the one case that still constructs.
  static CoachInsight _priorityInsight({
    required ShiftSummary today,
    required double dailyGoal,
    required CoachInsight leak,
    required CoachInsight opportunity,
    required bool hasLeak,
    required bool hasGradedPattern,
    required CoachInsight weekly,
    required MeasurementUnits units,
  }) {
    if (today.shiftCount > 0) {
      // The figures below carry the numbers, so the sentence carries what to do
      // about them. Restating "you kept $305.00" beside a tile reading $305.00
      // spends two lines saying one thing.
      final pace = today.hours == 0
          ? null
          : 'Compare another hour against your current pace before continuing.';
      if (today.netProfit >= dailyGoal) {
        return CoachInsight(
          title: 'Today’s goal is complete',
          message: [
            'You reached your ${units.whole(dailyGoal)} target.',
            ?pace,
          ].join(' '),
          kind: CoachInsightKind.goal,
          headline: (
            label: 'Kept',
            heroLabel: 'Kept today',
            text: units.cents(today.netProfit),
            value: today.netProfit,
            loss: today.netProfit < 0,
          ),
          figures: _todayFigures(today, dailyGoal, units),
        );
      }
      return CoachInsight(
        title: 'Close today’s profit gap',
        message: [
          'You are short of today’s ${units.whole(dailyGoal)} goal.',
          ?pace,
        ].join(' '),
        kind: CoachInsightKind.goal,
        headline: (
          label: 'Gap',
          heroLabel: 'Gap to goal',
          text: units.cents(dailyGoal - today.netProfit),
          value: dailyGoal - today.netProfit,
          loss: false,
        ),
        figures: _todayFigures(today, dailyGoal, units),
      );
    }
    if (hasLeak) return leak;
    if (hasGradedPattern) return opportunity;
    return weekly;
  }

  static List<CoachFigure> _todayFigures(
    ShiftSummary today,
    double dailyGoal,
    MeasurementUnits units,
  ) => [
    (label: 'Goal', value: units.whole(dailyGoal), loss: false),
    (
      label: 'Net / hr',
      // A rate needs a denominator. Zero hours would print "$0.00", which reads
      // as a terrible day rather than an unmeasurable one.
      value: today.hours == 0 ? '—' : units.cents(today.netPerHour),
      loss: today.netProfit < 0,
    ),
    (label: 'Sessions', value: '${today.shiftCount}', loss: false),
  ];

  /// The pattern's supporting figures. True hourly is deliberately absent: it
  /// is the headline, and a figure that appears in both would print twice.
  static List<CoachFigure> _patternFigures(
    EarningsPattern best,
    MeasurementUnits units,
  ) => [
    (
      label: 'Profit',
      value: units.cents(best.netProfit),
      loss: best.netProfit < 0,
    ),
    (label: 'Sessions', value: '${best.shiftCount}', loss: false),
  ];

  static CoachInsight _weeklyInsight(
    WeeklyPerformance weekly, {
    required double dailyGoal,
    required int drivingDaysPerWeek,
    required MeasurementUnits units,
    required bool hasUnreviewed,
  }) {
    final summary = weekly.summary;
    if (summary.shiftCount == 0) {
      return const CoachInsight(
        title: 'Weekly performance',
        message:
            'Coach will compare this week with the previous one after you complete a session.',
        kind: CoachInsightKind.weekly,
        isReady: false,
        progress: (done: 0, needed: 1, caption: '0 of 1 sessions this week'),
      );
    }
    final comparison = weekly.previousSummary.shiftCount == 0
        ? 'There is no previous-week baseline yet.'
        : weekly.netProfitChange != null
        ? 'That is ${weekly.netProfitChange! >= 0 ? 'up' : 'down'} ${(weekly.netProfitChange!.abs() * 100).toStringAsFixed(0)}% from last week.'
        : 'That is ${units.signed(weekly.netProfitDelta ?? 0)} versus last week.';
    final weeklyTarget = dailyGoal * drivingDaysPerWeek;
    final target = weeklyTarget <= 0
        ? null
        : summary.netProfit >= weeklyTarget
        ? 'You cleared your ${units.whole(weeklyTarget)} weekly target.'
        : 'You are ${units.cents(weeklyTarget - summary.netProfit)} from your ${units.whole(weeklyTarget)} weekly target.';
    final review = hasUnreviewed
        ? 'One or more imported sessions still need a cost review.'
        : null;
    return CoachInsight(
      title: 'This week at a glance',
      message: [comparison, ?target, ?review].join(' '),
      kind: CoachInsightKind.weekly,
      headline: (
        label: 'Net',
        heroLabel: 'True Profit',
        text: units.cents(summary.netProfit),
        value: summary.netProfit,
        loss: summary.netProfit < 0,
      ),
      figures: [
        (
          label: 'Net / hr',
          value: summary.hours == 0 ? '—' : units.cents(summary.netPerHour),
          loss: summary.netProfit < 0,
        ),
        (label: 'Sessions', value: '${summary.shiftCount}', loss: false),
      ],
    );
  }

  static CoachInsight _opportunityInsight(
    List<EarningsPattern> patterns,
    List<EarningsPattern> gradedPatterns, {
    required MeasurementUnits units,
  }) {
    if (gradedPatterns.isEmpty) {
      return CoachInsight(
        title: 'Build your Earnings DNA',
        message:
            'Coach ranks your best times once it has four distinct reviewed day-and-time patterns to compare.',
        kind: CoachInsightKind.opportunity,
        isReady: false,
        progress: (
          done: patterns.length,
          needed: 4,
          caption: '${patterns.length} of 4 patterns tracked',
        ),
      );
    }
    final best = gradedPatterns.first;
    return CoachInsight(
      title: 'Best opportunity: ${best.label}',
      message:
          '${best.timeBlock.range} is your strongest recorded pattern so far.',
      kind: CoachInsightKind.opportunity,
      headline: (
        label: 'Net / hr',
        heroLabel: 'True hourly',
        text: units.cents(best.netPerHour),
        value: best.netPerHour,
        loss: best.netPerHour < 0,
      ),
      figures: _patternFigures(best, units),
    );
  }

  static CoachInsight _leakInsight(
    List<MoneyLeak> leaks, {
    required int reviewedShiftCount,
    required MeasurementUnits units,
  }) {
    if (leaks.isNotEmpty) {
      final leak = leaks.first;
      return CoachInsight(
        title: 'Money leak: ${leak.title.toLowerCase()}',
        message:
            '${leak.detail} The gap below is estimated from your saved session and hourly floor.',
        kind: CoachInsightKind.leak,
        // The gap is the only figure this reading has, so it is the headline
        // and there are no supporting figures beside it.
        headline: (
          label: 'Gap',
          heroLabel: 'Estimated gap',
          text: units.cents(leak.potentialRecovery),
          value: leak.potentialRecovery,
          loss: false,
        ),
      );
    }
    if (reviewedShiftCount < 3) {
      final remaining = 3 - reviewedShiftCount;
      return CoachInsight(
        title: 'Money leak',
        message:
            'Coach needs a few reviewed sessions before it can tell a pattern from a one-off result.',
        kind: CoachInsightKind.leak,
        isReady: false,
        progress: (
          done: reviewedShiftCount,
          needed: 3,
          caption:
              '$reviewedShiftCount of 3 reviewed sessions · $remaining to go',
        ),
      );
    }
    return const CoachInsight(
      title: 'No clear money leak detected',
      message:
          'Your reviewed sessions do not currently show a loss, a low keep rate, or a result below your hourly floor.',
      kind: CoachInsightKind.leak,
    );
  }

  static CoachInsight _costInsight(
    List<Shift> costShifts, {
    required int reviewedShiftCount,
    required MeasurementUnits units,
  }) {
    if (costShifts.isEmpty) {
      return CoachInsight(
        title: 'Cost insight',
        message: reviewedShiftCount == 0
            ? 'Review a session’s costs before Coach evaluates fuel, fees and vehicle wear.'
            : 'Record distance or a direct expense on a reviewed session to see its effect on True Profit.',
        kind: CoachInsightKind.cost,
        isReady: false,
        progress: (
          done: 0,
          needed: 1,
          caption: reviewedShiftCount == 0
              ? 'No reviewed sessions yet'
              : 'No distance or expenses recorded yet',
        ),
      );
    }
    final summary = ShiftSummary.from(costShifts);
    final share = summary.gross <= 0
        ? null
        : summary.totalExpenses / summary.gross;
    final dominant = summary.directExpenses >= summary.vehicleCost
        ? 'Direct expenses are the larger part at ${units.cents(summary.directExpenses)}.'
        : 'Vehicle cost is the larger part at ${units.cents(summary.vehicleCost)}.';
    return CoachInsight(
      title: 'Cost insight',
      message:
          'Recorded costs across ${summary.shiftCount} reviewed ${summary.shiftCount == 1 ? 'session' : 'sessions'} reduced True Profit. $dominant',
      kind: CoachInsightKind.cost,
      headline: (
        label: 'Costs',
        heroLabel: 'Recorded costs',
        text: units.cents(summary.totalExpenses),
        value: summary.totalExpenses,
        loss: false,
      ),
      figures: [
        (
          label: 'Of gross',
          value: share == null ? '—' : '${(share * 100).toStringAsFixed(0)}%',
          loss: false,
        ),
        (
          label: 'Per ${units.distance.symbol}',
          value: summary.miles <= 0
              ? '—'
              : units.rateLabel(summary.totalExpenses / summary.miles),
          loss: false,
        ),
      ],
    );
  }

  static List<CoachQuestion> _questions({
    required WeeklyPerformance weekly,
    required CoachInsight weeklyInsight,
    required List<EarningsPattern> patterns,
    required List<MoneyLeak> leaks,
    required List<Shift> costShifts,
    required CoachInsight costInsight,
    required MeasurementUnits units,
  }) {
    final questions = <CoachQuestion>[];
    if (weekly.summary.shiftCount > 0) {
      final summary = weekly.summary;
      questions.add(
        CoachQuestion(
          prompt: 'How is this week going?',
          // The chat answer restates the figures on purpose: a bubble has no
          // stat tiles beside it, so the sentence has to carry them.
          answer:
              '${summary.shiftCount} ${summary.shiftCount == 1 ? 'session' : 'sessions'} produced ${units.cents(summary.netProfit)} True Profit at ${units.cents(summary.netPerHour)} per hour. ${weeklyInsight.message}',
        ),
      );
    }
    if (patterns.isNotEmpty) {
      final best = patterns.first;
      questions.add(
        CoachQuestion(
          prompt: 'When am I most profitable?',
          answer:
              '${best.label}, ${best.timeBlock.range}, is your strongest reviewed pattern at ${units.cents(best.netPerHour)} True hourly. This is based only on ${best.shiftCount} recorded ${best.shiftCount == 1 ? 'session' : 'sessions'}.',
        ),
      );
    }
    if (leaks.isNotEmpty) {
      questions.add(
        CoachQuestion(
          prompt: 'Where am I losing money?',
          answer:
              '${leaks.first.detail} Its estimated gap is ${units.cents(leaks.first.potentialRecovery)}.',
        ),
      );
    }
    if (costShifts.isNotEmpty) {
      final summary = ShiftSummary.from(costShifts);
      questions.add(
        CoachQuestion(
          prompt: 'What are costs doing to my profit?',
          answer:
              '${units.cents(summary.totalExpenses)} in recorded costs reduced True Profit across ${summary.shiftCount} reviewed ${summary.shiftCount == 1 ? 'session' : 'sessions'}. ${costInsight.message}',
        ),
      );
    }
    if (questions.isEmpty) {
      questions.add(
        const CoachQuestion(
          prompt: 'What does Coach still need?',
          answer:
              'Review costs on completed sessions and record different days and times. Coach will unlock comparisons only when your history supports them.',
        ),
      );
    }
    return questions.take(4).toList();
  }
}

enum CoachInsightKind { start, goal, weekly, opportunity, leak, cost }

class CoachInsight {
  const CoachInsight({
    required this.title,
    required this.message,
    required this.kind,
    this.isReady = true,
    this.headline,
    this.figures = const [],
    this.progress,
  });

  final String title;

  /// What the numbers mean and what to do about them.
  ///
  /// Deliberately not a restatement of [headline] or [figures]: those are
  /// rendered as figures beside it, and a sentence repeating a tile spends two
  /// lines saying one thing.
  final String message;

  final CoachInsightKind kind;
  final bool isReady;

  /// The one figure this insight is about, for whichever surface renders it as
  /// a headline. Ignored by the cards, which lead with [figures].
  final CoachHeadline? headline;

  /// Supporting figures, shown as a row of tiles under the message.
  final List<CoachFigure> figures;

  /// Set instead of [figures] while the insight is still learning: how far the
  /// driver's history is towards supporting a conclusion.
  final CoachProgress? progress;
}

class CoachQuestion {
  const CoachQuestion({required this.prompt, required this.answer});

  final String prompt;
  final String answer;
}

class CoachDashboard {
  const CoachDashboard({
    required this.priority,
    required this.weekly,
    required this.opportunity,
    required this.leak,
    required this.cost,
    required this.questions,
    required this.patterns,
    required this.reviewedShiftCount,
  });

  final CoachInsight priority;
  final CoachInsight weekly;
  final CoachInsight opportunity;
  final CoachInsight leak;
  final CoachInsight cost;
  final List<CoachQuestion> questions;
  final List<EarningsPattern> patterns;
  final int reviewedShiftCount;

  bool get canOpenBestTimes =>
      patterns.any((pattern) => pattern.grade != PatternGrade.pending);

  List<CoachInsight> get feed {
    final ordered = [priority, weekly, opportunity, leak, cost];
    final seen = <String>{};
    return [
      for (final insight in ordered)
        if (seen.add(insight.title)) insight,
    ];
  }
}
