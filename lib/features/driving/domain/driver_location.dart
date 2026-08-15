import 'dart:math' as math;

/// One GPS fix.
class DriverLocation {
  const DriverLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters = 0,
    this.speedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Horizontal accuracy radius. Larger means the fix is less trustworthy.
  final double accuracyMeters;

  /// Reported ground speed, when the platform provides one.
  final double? speedMetersPerSecond;

  /// Great-circle distance to [other] in metres.
  ///
  /// Deliberately computed from the fixes themselves rather than asked of a
  /// routing service: a rideshare driver circles airports, repositions and
  /// deadheads, so the miles actually driven and the optimal road distance
  /// between two points are very different numbers. Only the former is a
  /// legitimate basis for a cost-per-mile deduction.
  double distanceMetersTo(DriverLocation other) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(latitude);
    final lat2 = _radians(other.latitude);
    final deltaLat = _radians(other.latitude - latitude);
    final deltaLon = _radians(other.longitude - longitude);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

/// Accumulates distance from a stream of fixes.
///
/// The hard part is not the trigonometry, it is rejecting movement that never
/// happened. A phone sitting on a dashboard at an airport queue still emits
/// fixes that wander by tens of metres, and summing those raw would invent
/// miles — which in this app becomes an invented vehicle cost and a wrong
/// profit figure. Every rule below exists to avoid charging a driver for
/// mileage they did not drive.
class DistanceAccumulator {
  DistanceAccumulator({double initialMeters = 0}) : _meters = initialMeters;

  /// Fixes worse than this are ignored outright.
  static const maxAccuracyMeters = 50.0;

  /// A leg at least this long is travel on displacement alone.
  ///
  /// Must stay *below* the platform's `distanceFilter`, or every emitted fix
  /// lands in a dead zone between the two and is discarded. That failure is
  /// especially nasty here: it under-counts miles, which shrinks the vehicle
  /// cost, which makes reported profit too high — the app would be wrong in
  /// the flattering direction.
  static const minLegMeters = 8.0;

  /// Below this, a leg needs corroboration before it counts.
  static const _shortLegMeters = 25.0;

  /// Reported ground speed that indicates real driving rather than drift.
  /// Roughly 4 mph — slower than traffic crawls, faster than GPS wander.
  static const minMovingSpeed = 1.8;

  /// Implausible for a road vehicle (~180 mph); indicates a fix jump rather
  /// than travel.
  static const maxSpeedMetersPerSecond = 80.0;

  double _meters = 0;
  DriverLocation? _last;

  double get meters => _meters;
  double get miles => _meters / 1609.344;
  DriverLocation? get lastLocation => _last;

  /// Forgets the anchor fix without touching the banked total.
  ///
  /// Used when tracking stops and restarts within one session, as a break
  /// does. Without it the first fix after the gap would be measured against
  /// wherever the driver was before it and credited as a straight line across
  /// the whole break — miles that were never driven.
  void reanchor() => _last = null;

  /// Returns true when the fix advanced the total.
  bool add(DriverLocation location) {
    if (location.accuracyMeters > maxAccuracyMeters) return false;

    final previous = _last;
    if (previous == null) {
      _last = location;
      return false;
    }

    final elapsed = location.timestamp.difference(previous.timestamp);
    if (elapsed.isNegative || elapsed == Duration.zero) {
      // Out-of-order or duplicate fix; keep the newer one as the anchor only
      // if it is genuinely newer.
      if (!elapsed.isNegative) _last = location;
      return false;
    }

    final legMeters = previous.distanceMetersTo(location);
    if (legMeters < minLegMeters) {
      // Held stationary: do not advance the anchor, otherwise repeated small
      // drifts would accumulate one sub-threshold step at a time.
      return false;
    }

    final speed = legMeters / elapsed.inMilliseconds * 1000;
    if (speed > maxSpeedMetersPerSecond) {
      // A teleport between fixes, typically a tunnel exit or a bad fix. Re-anchor
      // without crediting the jump.
      _last = location;
      return false;
    }

    // A mid-length leg is ambiguous: it could be a slow crawl through traffic
    // or it could be drift on a parked car. Rather than pick a single
    // displacement cutoff — which either invents miles when parked or loses
    // them in traffic — require one piece of corroborating evidence.
    if (legMeters < _shortLegMeters && !_looksLikeMovement(location, speed)) {
      return false;
    }

    _meters += legMeters;
    _last = location;
    return true;
  }

  /// Evidence that a short leg was real travel rather than drift.
  ///
  /// Speed is the discriminator, because it is what actually separates the two
  /// cases: a car crawling covers 20 m in about ten seconds, while a parked
  /// phone takes minutes to wander the same distance. Displacement alone
  /// cannot tell them apart at this range — a good fix on a stationary car
  /// still drifts far enough to look like movement.
  bool _looksLikeMovement(DriverLocation location, double impliedSpeed) {
    final reported = location.speedMetersPerSecond;
    if (reported != null && reported >= minMovingSpeed) return true;
    return impliedSpeed >= minMovingSpeed;
  }
}
