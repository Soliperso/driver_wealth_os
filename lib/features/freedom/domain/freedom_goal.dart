import '../../shifts/domain/shift.dart';

class FreedomGoal {
  const FreedomGoal({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.startingAmount,
    required this.allocationRate,
    required this.createdAt,
  });

  final String id;
  final String title;
  final double targetAmount;
  final double startingAmount;
  final double allocationRate;
  final DateTime createdAt;

  FreedomProgress progress(Iterable<Shift> shifts, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final unique = <String, Shift>{};
    for (final shift in shifts) {
      if (!shift.completedAt.isBefore(createdAt) &&
          !shift.completedAt.isAfter(current)) {
        unique.putIfAbsent(shift.id, () => shift);
      }
    }
    final positiveProfit = unique.values.fold(
      0.0,
      (sum, shift) => sum + shift.netProfit.clamp(0, double.infinity),
    );
    final allocatedProfit = _currency(positiveProfit * allocationRate);
    final amount = _currency(
      (startingAmount + allocatedProfit).clamp(0, targetAmount),
    );
    final activeDays = unique.values
        .map(
          (shift) => DateTime(
            shift.completedAt.year,
            shift.completedAt.month,
            shift.completedAt.day,
          ),
        )
        .toSet()
        .length;
    final remaining = _currency(targetAmount - amount);
    final weeklyAllocation = activeDays < 2
        ? null
        : _currency((allocatedProfit / activeDays) * 7);
    final projectedWeeks = weeklyAllocation == null || weeklyAllocation <= 0
        ? null
        : remaining / weeklyAllocation;
    return FreedomProgress(
      amount: amount,
      allocatedProfit: allocatedProfit,
      remaining: remaining,
      activeDays: activeDays,
      weeklyAllocation: weeklyAllocation,
      projectedWeeks: projectedWeeks,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'targetAmount': targetAmount,
    'startingAmount': startingAmount,
    'allocationRate': allocationRate,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FreedomGoal.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final target = _number(json['targetAmount']);
    final starting = _number(json['startingAmount']);
    final rate = _number(json['allocationRate']);
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        createdAt == null ||
        target <= 0 ||
        starting > target ||
        rate <= 0 ||
        rate > 1) {
      throw const FormatException('Invalid freedom goal');
    }
    return FreedomGoal(
      id: id,
      title: title.trim(),
      targetAmount: target,
      startingAmount: starting,
      allocationRate: rate,
      createdAt: createdAt,
    );
  }

  static double _number(Object? value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    throw const FormatException('Invalid goal amount');
  }

  static double _currency(num value) => (value * 100).round() / 100;
}

class FreedomProgress {
  const FreedomProgress({
    required this.amount,
    required this.allocatedProfit,
    required this.remaining,
    required this.activeDays,
    required this.weeklyAllocation,
    required this.projectedWeeks,
  });

  final double amount;
  final double allocatedProfit;
  final double remaining;
  final int activeDays;
  final double? weeklyAllocation;
  final double? projectedWeeks;
}
