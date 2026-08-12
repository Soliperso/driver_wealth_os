import 'dart:async';

import 'package:driver_wealth_os/features/driving/application/location_tracker.dart';
import 'package:driver_wealth_os/features/driving/domain/driver_location.dart';

/// Feeds scripted GPS fixes so session behaviour can be tested without a
/// device, a real satellite fix, or a permission dialog.
class FakeLocationTracker implements LocationTracker {
  FakeLocationTracker({this.permission = LocationPermissionState.always});

  LocationPermissionState permission;
  final _controller = StreamController<DriverLocation>.broadcast();

  var started = false;
  var stopped = false;

  @override
  Stream<DriverLocation> get locations => _controller.stream;

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async => permission;

  @override
  Future<void> start() async {
    started = true;
    stopped = false;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  /// Emits a fix and yields so the controller's listener runs before the test
  /// asserts on the result.
  ///
  /// Yields via a microtask rather than `Future.delayed`. A zero-duration delay
  /// is still a *timer*, and inside `testWidgets` timers only fire when the
  /// test pumps — so awaiting one here would deadlock the test body before it
  /// ever got the chance to pump.
  Future<void> emit(DriverLocation location) async {
    _controller.add(location);
    await Future<void>.microtask(() {});
  }

  Future<void> dispose() => _controller.close();
}
