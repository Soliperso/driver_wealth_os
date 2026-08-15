import '../../accounts/domain/work_platform.dart';
import '../../shifts/domain/shift.dart';

/// How long a pause can run before the driver is warned about it.
const pauseWarningAfter = Duration(minutes: 30);

/// How long a pause can run before the session ends itself.
///
/// A pause nobody resumes is the dangerous failure here: time and miles both
/// stop, so the shift silently records less driving than happened, which
/// shrinks the vehicle cost and overstates profit. Ending into a recoverable
/// draft is worse for tidiness and better for honesty.
const pauseAutoEndAfter = Duration(hours: 2);

/// One stretch of a session with a given app switched on.
///
/// Drivers do not turn both apps on at the same instant: Uber from four, Lyft
/// added at seven when it gets busy, Lyft off again at nine. A plain set of
/// platforms would record that the shift "had" both and lose that one of them
/// was live for two hours of seven — and that gap is exactly what makes a
/// later comparison between the two honest or misleading.
///
/// Stored as timestamps for the same reason the pause bookkeeping is: the OS
/// can kill the app at any point, and only stored instants survive that.
class PlatformSpan {
  const PlatformSpan({required this.platform, required this.from, this.to});

  final WorkPlatform platform;
  final DateTime from;

  /// When the driver switched this app off, or null while it is still on.
  final DateTime? to;

  bool get isLive => to == null;

  /// Wall clock from switch-on to switch-off, breaks included.
  ///
  /// Deliberately not "worked time": the session's breaks are not attributed
  /// per app, so this over-states how long a driver was actually earning on
  /// this platform. Nothing user-facing reads it yet — it exists so the span
  /// data is complete enough to answer that question later.
  Duration wallDuration({DateTime? now}) {
    final closed = to ?? now ?? DateTime.now();
    final taken = closed.difference(from);
    return taken.isNegative ? Duration.zero : taken;
  }

  /// Closes the span, never before it opened — a clock that jumped backwards
  /// would otherwise produce a span that ended before it started.
  PlatformSpan closedAt(DateTime at) => PlatformSpan(
    platform: platform,
    from: from,
    to: at.isBefore(from) ? from : at,
  );

  Map<String, Object?> toJson() => {
    'platform': platform.id,
    'from': from.toIso8601String(),
    'to': to?.toIso8601String(),
  };

  static PlatformSpan? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = DateTime.tryParse(json['from'] as String? ?? '');
    if (from == null) return null;
    return PlatformSpan(
      platform: WorkPlatform.values.firstWhere(
        (candidate) => candidate.id == json['platform'],
        orElse: () => WorkPlatform.other,
      ),
      from: from,
      to: DateTime.tryParse(json['to'] as String? ?? ''),
    );
  }
}

/// A live or just-finished driving session.
///
/// Duration is never stored as a running count. Only [startedAt], [endedAt]
/// and the pause bookkeeping are persisted, and elapsed time is derived from
/// them. The OS is free to suspend or kill the app mid-shift; the arithmetic
/// still comes out right afterwards, which an in-memory ticking counter could
/// not guarantee.
class DrivingSession {
  const DrivingSession({
    required this.id,
    required this.startedAt,
    required this.platformSpans,
    this.endedAt,
    this.distanceMeters = 0,
    this.vehicleCostPerMile = 0.30,
    this.pausedAt,
    this.pausedMillis = 0,
  });

  /// A session running one app from the moment it started.
  DrivingSession.single({
    required String id,
    required DateTime startedAt,
    required WorkPlatform platform,
    DateTime? endedAt,
    double distanceMeters = 0,
    double vehicleCostPerMile = 0.30,
    DateTime? pausedAt,
    int pausedMillis = 0,
  }) : this(
         id: id,
         startedAt: startedAt,
         platformSpans: [PlatformSpan(platform: platform, from: startedAt)],
         endedAt: endedAt,
         distanceMeters: distanceMeters,
         vehicleCostPerMile: vehicleCostPerMile,
         pausedAt: pausedAt,
         pausedMillis: pausedMillis,
       );

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Every stretch of this session with an app switched on, oldest first.
  ///
  /// One app switched off and back on later is two spans, not one: the gap is
  /// real and flattening it would claim the app was live throughout.
  final List<PlatformSpan> platformSpans;

  final double distanceMeters;
  final double vehicleCostPerMile;

  /// When the current break started, or null if the session is running.
  final DateTime? pausedAt;

  /// Break time already taken and closed out, in milliseconds.
  ///
  /// Accumulated rather than folded into [startedAt], so the session keeps
  /// reporting when the shift really began however many breaks it took.
  final int pausedMillis;

  bool get isActive => endedAt == null;

  bool get isPaused => pausedAt != null;

  /// The apps switched on right now, in the order they were switched on.
  List<WorkPlatform> get livePlatforms => [
    for (final span in platformSpans)
      if (span.isLive) span.platform,
  ];

  /// Every app this session has run at any point, first appearance first.
  ///
  /// This is what the finished shift needs an earnings line for: an app that
  /// was live for two hours still paid the driver something, and dropping it
  /// because it was switched off before the shift ended would lose that money.
  List<WorkPlatform> get platforms {
    final seen = <WorkPlatform>[];
    for (final span in platformSpans) {
      if (!seen.contains(span.platform)) seen.add(span.platform);
    }
    return seen;
  }

  /// The single app that stands for this session wherever only one can be
  /// shown. Prefers one that is still live over one already switched off.
  ///
  /// Falls back rather than throwing on a session with no spans: that is a
  /// bug, but not one worth losing a live shift's clock and mileage over.
  WorkPlatform get platform =>
      livePlatforms.firstOrNull ?? platforms.firstOrNull ?? WorkPlatform.other;

  /// Switches an app on, from [at].
  ///
  /// An app switched on again after being switched off opens a second span
  /// rather than reopening the first, so the gap in between stays visible.
  /// Returns the same session when the app is already live, which lets callers
  /// skip a pointless write and notify.
  DrivingSession addingPlatform(WorkPlatform platform, {required DateTime at}) {
    if (livePlatforms.contains(platform)) return this;
    return copyWith(
      platformSpans: [
        ...platformSpans,
        PlatformSpan(
          platform: platform,
          // Never before the session began: an app cannot have been live
          // earlier than the shift it belongs to.
          from: at.isBefore(startedAt) ? startedAt : at,
        ),
      ],
    );
  }

  /// Switches an app off at [at], closing every live span it has.
  ///
  /// Refuses to switch off the last live app. A session running nothing has no
  /// one to attribute the shift's earnings to, and a driver who wanted that
  /// wanted to end the shift — which is a different, deliberate button.
  DrivingSession removingPlatform(
    WorkPlatform platform, {
    required DateTime at,
  }) {
    if (!livePlatforms.contains(platform)) return this;
    if (livePlatforms.length <= 1) return this;
    return copyWith(
      platformSpans: [
        for (final span in platformSpans)
          if (span.isLive && span.platform == platform)
            span.closedAt(at)
          else
            span,
      ],
    );
  }

  /// Closes every span that is still open, so a finished session does not go
  /// on claiming its apps are live.
  DrivingSession closingSpans({required DateTime at}) => copyWith(
    platformSpans: [
      for (final span in platformSpans)
        if (span.isLive) span.closedAt(at) else span,
    ],
  );

  /// How long the break currently in progress has run, or zero if none is.
  ///
  /// Distinct from [pausedTotal] because the warning and the auto-end care
  /// about *this* break, not the day's total. Several short breaks are a
  /// driver using the feature; one long one is a driver who forgot.
  Duration currentPause({DateTime? now}) {
    final open = pausedAt;
    if (open == null) return Duration.zero;
    final taken = (endedAt ?? now ?? DateTime.now()).difference(open);
    return taken.isNegative ? Duration.zero : taken;
  }

  /// Break time excluded from the shift, including a break still open.
  Duration pausedTotal({DateTime? now}) =>
      Duration(milliseconds: pausedMillis) + currentPause(now: now);

  /// Working time: the wall clock minus any breaks. Derived, never counted.
  Duration elapsed({DateTime? now}) =>
      wallElapsed(now: now) - pausedTotal(now: now);

  /// Wall clock from start to now, breaks included. Only the auto-end
  /// threshold cares about this; everything the driver is paid for uses
  /// [elapsed].
  Duration wallElapsed({DateTime? now}) =>
      (endedAt ?? now ?? DateTime.now()).difference(startedAt);

  double get miles => distanceMeters / 1609.344;

  double get hours => elapsed().inMilliseconds / Duration.millisecondsPerHour;

  /// What the mileage has already cost in wear, shown live so the driver can
  /// see the meter running against them, not just the hours accruing.
  double get estimatedVehicleCost =>
      ((miles * vehicleCostPerMile) * 100).round() / 100;

  /// [clearPausedAt] exists because the `?? this` idiom cannot set a field
  /// back to null, and resuming has to do exactly that.
  DrivingSession copyWith({
    DateTime? endedAt,
    double? distanceMeters,
    List<PlatformSpan>? platformSpans,
    double? vehicleCostPerMile,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    int? pausedMillis,
  }) => DrivingSession(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    platformSpans: platformSpans ?? this.platformSpans,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
    pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
    pausedMillis: pausedMillis ?? this.pausedMillis,
  );

  /// Converts a finished session into the shift the earnings then attach to.
  ///
  /// Hours and miles are the tracked figures; everything monetary is left at
  /// zero because a session knows what was driven, never what was paid.
  Shift toDraftShift({required DateTime endedAt}) {
    // Breaks come off here too. This repeats the subtraction in [elapsed]
    // rather than calling it, because the session being converted has not had
    // its own endedAt set yet.
    final duration = endedAt.difference(startedAt) - pausedTotal(now: endedAt);
    return Shift(
      id: 'tracked-${startedAt.microsecondsSinceEpoch}',
      // A line per app the session ever ran, all at zero: the driver is about
      // to fill them in. Apps switched off partway through are included, since
      // they still paid for the part of the shift they were on for.
      earnings: {for (final platform in platforms) platform: 0.0},
      hours: _round(duration.inMilliseconds / Duration.millisecondsPerHour, 4),
      miles: _round(distanceMeters / 1609.344, 2),
      directExpenses: 0,
      vehicleCostPerMile: vehicleCostPerMile,
      completedAt: endedAt,
      source: ShiftSource.tracked,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    // Kept alongside the spans so a build without multi-app support restores a
    // live shift on the app the driver is most likely still running, rather
    // than dropping the session and its accrued time on the floor.
    'platform': platform.id,
    'platformSpans': [for (final span in platformSpans) span.toJson()],
    'distanceMeters': distanceMeters,
    'vehicleCostPerMile': vehicleCostPerMile,
    'pausedAt': pausedAt?.toIso8601String(),
    'pausedMillis': pausedMillis,
  };

  static DrivingSession? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || startedAt == null) return null;
    final distance = json['distanceMeters'];
    final rate = json['vehicleCostPerMile'];
    // Absent in payloads written before pause existed, which is why both fall
    // back to "never paused" rather than being treated as corrupt.
    final paused = json['pausedMillis'];
    return DrivingSession(
      id: id,
      startedAt: startedAt,
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
      platformSpans: _spansFromJson(json, startedAt: startedAt),
      distanceMeters: distance is num && distance.isFinite && distance >= 0
          ? distance.toDouble()
          : 0,
      vehicleCostPerMile: rate is num && rate.isFinite && rate >= 0
          ? rate.toDouble()
          : 0.30,
      pausedAt: DateTime.tryParse(json['pausedAt'] as String? ?? ''),
      pausedMillis: paused is num && paused.isFinite && paused >= 0
          ? paused.toInt()
          : 0,
    );
  }

  /// Rebuilds the spans, falling back to a single one covering the whole
  /// session when the field is absent — a session started by a build that had
  /// only ever run one app at a time.
  static List<PlatformSpan> _spansFromJson(
    Map<String, Object?> json, {
    required DateTime startedAt,
  }) {
    final raw = json['platformSpans'];
    if (raw is List) {
      final spans = [for (final span in raw) ?PlatformSpan.fromJson(span)];
      if (spans.isNotEmpty) return spans;
    }
    return [
      PlatformSpan(
        platform: WorkPlatform.values.firstWhere(
          (candidate) => candidate.id == json['platform'],
          orElse: () => WorkPlatform.uber,
        ),
        from: startedAt,
      ),
    ];
  }

  static double _round(double value, int places) =>
      double.parse(value.toStringAsFixed(places));
}

/// Formats elapsed time as HH:MM:SS for the live display.
String formatElapsed(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
}
