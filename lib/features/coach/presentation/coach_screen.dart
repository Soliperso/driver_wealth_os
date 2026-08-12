import 'package:flutter/material.dart';

import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../freedom/domain/freedom_goal.dart';
import '../../shifts/domain/shift.dart';
import '../domain/coach_engine.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({
    super.key,
    required this.shifts,
    required this.dailyGoal,
    required this.freedomGoal,
  });

  final List<Shift> shifts;
  final double dailyGoal;
  final FreedomGoal? freedomGoal;

  @override
  Widget build(BuildContext context) {
    final insights = CoachEngine.build(
      shifts: shifts,
      dailyGoal: dailyGoal,
      freedomGoal: freedomGoal,
    );
    return SoftScaffold(
      title: 'Profit coach',
      body: PageFrame(
        maxWidth: 760,
        child: ListView(
          children: [
            _PriorityInsight(insight: insights.first),
            if (insights.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                'More from your numbers',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final insight in insights.skip(1)) ...[
                _SupportingInsight(insight: insight),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 8),
            Text(
              'Recommendations use only your saved shifts, goal and calculated profit. They are not financial or tax advice.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 92),
          ],
        ),
      ),
    );
  }
}

class _PriorityInsight extends StatelessWidget {
  const _PriorityInsight({required this.insight});

  final CoachInsight insight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(22),
      tint: colors.primaryContainer.withValues(alpha: .76),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colors.primary.withValues(alpha: .18)),
            ),
            child: Icon(_icon(insight.kind), color: colors.primary, size: 22),
          ),
          const SizedBox(height: 18),
          Text(
            'Your next move',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            insight.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            insight.message,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.48),
          ),
        ],
      ),
    );
  }
}

class _SupportingInsight extends StatelessWidget {
  const _SupportingInsight({required this.insight});

  final CoachInsight insight;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _icon(insight.kind),
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                insight.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData _icon(CoachInsightKind kind) => switch (kind) {
  CoachInsightKind.start => Icons.add_chart_rounded,
  CoachInsightKind.goal => Icons.flag_rounded,
  CoachInsightKind.leak => Icons.trending_down_rounded,
  CoachInsightKind.pattern => Icons.fingerprint_rounded,
  CoachInsightKind.freedom => Icons.savings_outlined,
  CoachInsightKind.weekly => Icons.calendar_view_week_rounded,
};
