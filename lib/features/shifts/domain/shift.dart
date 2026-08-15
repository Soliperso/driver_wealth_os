import '../../accounts/domain/work_platform.dart';

/// Where a shift's figures came from.
///
/// Imported shifts are aggregated from a connected platform's gig feed, which
/// reports earnings, duration and distance but never fuel, tolls or parking.
/// They therefore start with no direct expenses and the driver is expected to
/// add them, so the two sources must stay distinguishable in the UI.
enum ShiftSource {
  manual('manual'),
  imported('imported'),

  /// Hours and miles came from a live driving session; the money was still
  /// supplied by the driver or an earnings source afterwards.
  tracked('tracked');

  const ShiftSource(this.id);

  final String id;

  static ShiftSource fromId(Object? value) => values.firstWhere(
    (source) => source.id == value,
    orElse: () => ShiftSource.manual,
  );
}

class Shift {
  Shift({
    required this.id,
    required Map<WorkPlatform, double> earnings,
    required this.hours,
    required this.miles,
    required this.directExpenses,
    required this.vehicleCostPerMile,
    required this.completedAt,
    this.source = ShiftSource.manual,
    this.costsReviewed = true,
  }) : earnings = Map.unmodifiable(earnings);

  /// A shift worked on one platform, which is still most of them.
  Shift.single({
    required String id,
    required WorkPlatform platform,
    required double gross,
    required double hours,
    required double miles,
    required double directExpenses,
    required double vehicleCostPerMile,
    required DateTime completedAt,
    ShiftSource source = ShiftSource.manual,
    bool costsReviewed = true,
  }) : this(
         id: id,
         earnings: {platform: gross},
         hours: hours,
         miles: miles,
         directExpenses: directExpenses,
         vehicleCostPerMile: vehicleCostPerMile,
         completedAt: completedAt,
         source: source,
         costsReviewed: costsReviewed,
       );

  final String id;

  /// What each platform paid, in the order the driver added them.
  ///
  /// Drivers multi-app: Uber and Lyft are both live in the same car on the same
  /// trip home. The hours, the miles and therefore the vehicle cost are caused
  /// jointly by every app that was running, so recording one shift per platform
  /// would count the same time and mileage twice and halve the apparent cost of
  /// driving. A shift instead holds one set of resources and one earnings line
  /// per platform.
  ///
  /// Gross is the only figure that can honestly be attributed to a single app.
  /// Nothing here splits [directExpenses] or [vehicleCost] per platform,
  /// because there is no true split to make — the fuel was burned once.
  final Map<WorkPlatform, double> earnings;

  final double hours;
  final double miles;
  final double directExpenses;
  final double vehicleCostPerMile;
  final DateTime completedAt;
  final ShiftSource source;

  /// False only when a platform import arrived without the driver's own fuel,
  /// toll and parking costs. Editing the shift confirms the cost figure, even
  /// when the correct amount is zero.
  final bool costsReviewed;

  /// Everything the shift paid, across every app that was running.
  double get gross =>
      _currency(earnings.values.fold(0.0, (total, paid) => total + paid));

  /// True when more than one app was live, which is what makes per-platform
  /// net profit unanswerable for this shift.
  bool get isMultiApp => earnings.length > 1;

  Set<WorkPlatform> get platforms => earnings.keys.toSet();

  /// Platforms ordered by what each paid, biggest first. Ties keep the order
  /// the driver entered them in, so the display does not reshuffle itself
  /// while two apps sit at zero on a shift that has just been tracked.
  List<WorkPlatform> get platformsByEarnings =>
      earnings.keys.toList()
        ..sort((a, b) => earnings[b]!.compareTo(earnings[a]!));

  /// The app that paid most, used wherever a single icon or name has to stand
  /// for the shift. Multi-app shifts should prefer [platformLabel].
  ///
  /// Falls back rather than throwing on an empty map: a shift with no earnings
  /// line is a bug, but one that must not take a driver's history down with it.
  WorkPlatform get platform => earnings.isEmpty
      ? WorkPlatform.other
      : earnings.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  /// How the shift names itself: "Uber", "Uber + Lyft", "Uber + 2 more".
  String get platformLabel {
    final ordered = platformsByEarnings;
    return switch (ordered.length) {
      0 => WorkPlatform.other.displayName,
      1 => ordered.first.displayName,
      2 => '${ordered[0].displayName} + ${ordered[1].displayName}',
      _ => '${ordered.first.displayName} + ${ordered.length - 1} more',
    };
  }

  double earnedOn(WorkPlatform platform) => earnings[platform] ?? 0;

  /// This platform's share of the shift's gross, 0..1. The only per-platform
  /// figure a multi-app shift can support.
  double shareOf(WorkPlatform platform) =>
      gross == 0 ? 0 : earnedOn(platform) / gross;

  double get vehicleCost => _currency(miles * vehicleCostPerMile);
  double get totalExpenses => _currency(directExpenses + vehicleCost);
  double get netProfit => _currency(gross - totalExpenses);
  double get netPerHour => hours == 0 ? 0 : netProfit / hours;
  double get netPerMile => miles == 0 ? 0 : netProfit / miles;
  double get keepRate => gross == 0 ? 0 : netProfit / gross;

  bool occurredOn(DateTime date) =>
      completedAt.year == date.year &&
      completedAt.month == date.month &&
      completedAt.day == date.day;

  /// [earnings] replaces the whole map rather than merging into it, so removing
  /// a platform the driver turned off is expressible. Merging would make a
  /// deletion impossible to say.
  Shift copyWith({
    Map<WorkPlatform, double>? earnings,
    double? hours,
    double? miles,
    double? directExpenses,
    double? vehicleCostPerMile,
    DateTime? completedAt,
    bool? costsReviewed,
  }) => Shift(
    id: id,
    earnings: earnings ?? this.earnings,
    hours: hours ?? this.hours,
    miles: miles ?? this.miles,
    directExpenses: directExpenses ?? this.directExpenses,
    vehicleCostPerMile: vehicleCostPerMile ?? this.vehicleCostPerMile,
    completedAt: completedAt ?? this.completedAt,
    source: source,
    costsReviewed: costsReviewed ?? this.costsReviewed,
  );

  /// [platform] and [gross] are still written alongside [earnings].
  ///
  /// They are what a build without multi-app support reads, and a driver who
  /// rolls back an update should find their history intact rather than empty:
  /// the older build sees the dominant app and the full day's takings, which is
  /// a lossy but honest view of a multi-app shift. They are ignored on the way
  /// back in whenever `earnings` is present.
  Map<String, Object> toJson() => {
    'id': id,
    'platform': platform.id,
    'gross': gross,
    'earnings': earningsToJson(earnings),
    'hours': hours,
    'miles': miles,
    'directExpenses': directExpenses,
    'vehicleCostPerMile': vehicleCostPerMile,
    'completedAt': completedAt.toIso8601String(),
    'source': source.id,
    'costsReviewed': costsReviewed,
  };

  factory Shift.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '');
    if (id is! String || id.isEmpty || completedAt == null) {
      throw const FormatException('Invalid shift identity');
    }
    final source = ShiftSource.fromId(json['source']);
    return Shift(
      id: id,
      earnings: earningsFromJson(
        json['earnings'],
        // Every record written before multi-apping existed, which is all of
        // them at the point this ships.
        legacyPlatform: json['platform'],
        legacyGross: () => _number(json['gross']),
      ),
      hours: _number(json['hours']),
      miles: _number(json['miles']),
      directExpenses: _number(json['directExpenses']),
      vehicleCostPerMile: _number(json['vehicleCostPerMile']),
      completedAt: completedAt,
      // Absent on records written before imports existed: they are all manual.
      source: source,
      // Existing imported records never contained direct platform expense
      // data, so migrate them into the review queue. Hand-entered records were
      // already confirmed by the driver.
      costsReviewed: json['costsReviewed'] is bool
          ? json['costsReviewed']! as bool
          : source != ShiftSource.imported,
    );
  }

  /// The wire form of [earnings]: a list, not an object keyed by platform id.
  ///
  /// A list keeps the driver's entry order, which the object form would leave
  /// to whatever the JSON decoder happens to do, and it is the same shape the
  /// `earnings` jsonb column holds.
  static List<Map<String, Object>> earningsToJson(
    Map<WorkPlatform, double> earnings,
  ) => [
    for (final line in earnings.entries)
      {'platform': line.key.id, 'gross': line.value},
  ];

  /// Decodes [earningsToJson], falling back to a single legacy platform/gross
  /// pair when the field is absent — an older record, or a row from a database
  /// that has not been migrated yet.
  ///
  /// [legacyGross] is a callback because it may throw on a malformed amount,
  /// and a record that does carry valid earnings lines should not be rejected
  /// over a legacy mirror nobody is going to read.
  ///
  /// [parseAmount] defaults to this class's strict decoder, which rejects the
  /// record. Callers that must not fail a whole batch over one bad line — the
  /// sync merge, where a thrown exception would strand every other change
  /// behind it — pass their own lenient parser.
  static Map<WorkPlatform, double> earningsFromJson(
    Object? raw, {
    required Object? legacyPlatform,
    required double Function() legacyGross,
    double Function(Object?)? parseAmount,
  }) {
    final amount = parseAmount ?? _number;
    final decoded = <WorkPlatform, double>{};
    if (raw is List) {
      for (final line in raw) {
        if (line is! Map) continue;
        final platformId = line['platform'];
        final platform = WorkPlatform.values.firstWhere(
          (candidate) => candidate.id == platformId,
          orElse: () => WorkPlatform.other,
        );
        // Summed rather than assigned: two lines that both fall back to
        // `other` are two different unrecognised apps, and dropping one would
        // understate the driver's gross.
        decoded[platform] = (decoded[platform] ?? 0) + amount(line['gross']);
      }
    }
    if (decoded.isNotEmpty) return decoded;
    return {
      WorkPlatform.values.firstWhere(
        (candidate) => candidate.id == legacyPlatform,
        orElse: () => WorkPlatform.other,
      ): legacyGross(),
    };
  }

  static double _currency(double value) => (value * 100).round() / 100;

  static double _number(Object? value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    throw const FormatException('Invalid shift amount');
  }
}
