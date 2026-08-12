import '../../accounts/domain/work_platform.dart';

/// What a platform paid for a window of work.
class ShiftEarnings {
  const ShiftEarnings({
    required this.gross,
    this.tips = 0,
    this.bonuses = 0,
    this.platform,
  });

  /// Fares before tips and bonuses.
  final double gross;
  final double tips;
  final double bonuses;
  final WorkPlatform? platform;

  double get total => gross + tips + bonuses;
}

/// Where a shift's money came from.
///
/// The profit engine never asks. Whether the figures were typed in, parsed
/// from a CSV, or pulled from a provider API, everything downstream —
/// analytics, Money Leaks, the Freedom goal, the Coach — sees the same
/// [ShiftEarnings]. That is what lets an API integration be added later
/// without reworking the parts that matter.
abstract interface class EarningsSource {
  String get id;

  String get displayName;

  /// False until the driver has connected the source and it is approved for
  /// use, which for provider APIs is not a given.
  bool get isAvailable;

  /// Earnings for a completed shift window, or null when this source cannot
  /// answer for that period.
  Future<ShiftEarnings?> earningsBetween({
    required DateTime start,
    required DateTime end,
    WorkPlatform? platform,
  });
}

/// The MVP source: the driver tells us.
///
/// Deliberately the only implementation that ships. Provider APIs — Uber's
/// Driver API among them — require an application and approval, so making the
/// product depend on one before it is granted would risk building a release
/// around an integration that cannot launch. Manual entry keeps every
/// downstream feature working today, and this interface is the seam an
/// approved API drops into later.
final class ManualEarningsSource implements EarningsSource {
  const ManualEarningsSource();

  @override
  String get id => 'manual';

  @override
  String get displayName => 'Entered by you';

  @override
  bool get isAvailable => true;

  /// Manual entry is collected by the earnings form, not fetched, so there is
  /// nothing to return here.
  @override
  Future<ShiftEarnings?> earningsBetween({
    required DateTime start,
    required DateTime end,
    WorkPlatform? platform,
  }) async => null;
}
