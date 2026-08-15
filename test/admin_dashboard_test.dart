import 'package:driver_wealth_os/app.dart';
import 'package:driver_wealth_os/core/persistence/app_store.dart';
import 'package:driver_wealth_os/features/admin/application/admin_repository.dart';
import 'package:driver_wealth_os/features/admin/domain/admin_models.dart';
import 'package:driver_wealth_os/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:driver_wealth_os/features/auth/domain/auth_user.dart';
import 'package:driver_wealth_os/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  testWidgets('normal accounts never see a role or admin entry', (
    tester,
  ) async {
    final auth = FakeAuthGateway(
      user: const AuthUser(id: 'driver-1', email: 'driver@example.com'),
    );
    final admin = _FakeAdminRepository(allowed: false);

    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(const AppSnapshot(driverName: 'Taylor')),
        authGateway: auth,
        adminRepository: admin,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-open-admin')), findsNothing);
    expect(find.text('User'), findsNothing);
    expect(find.text('Role'), findsNothing);
    await auth.dispose();
  });

  testWidgets('owner can open dashboard and pause driver cloud access', (
    tester,
  ) async {
    final auth = FakeAuthGateway(
      user: const AuthUser(id: 'owner-1', email: 'owner@example.com'),
    );
    final admin = _FakeAdminRepository(allowed: true);

    await tester.pumpWidget(
      DriverWealthApp(
        store: MemoryAppStore(const AppSnapshot(driverName: 'Owner')),
        authGateway: auth,
        adminRepository: admin,
        drivingRefreshInterval: null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-open-admin')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-open-admin')));
    await tester.pumpAndSettle();

    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Platform overview'), findsOneWidget);
    expect(find.text('Drivers'), findsWidgets);
    expect(find.text('Role'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin-cloud-access-driver-1')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(AdminDashboardScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('admin-cloud-access-driver-1')));
    await tester.pumpAndSettle();
    expect(find.text('Pause cloud access?'), findsOneWidget);
    await tester.tap(find.text('Pause access'));
    await tester.pumpAndSettle();

    expect(admin.accessChanges, [('driver-1', false)]);
    await auth.dispose();
  });

  test('admin payload parsing keeps roles out of the client model', () {
    final user = AdminUserSummary.fromJson({
      'id': 'driver-1',
      'email': 'driver@example.com',
      'driver_name': 'Taylor',
      'created_at': '2026-08-14T12:00:00Z',
      'last_sign_in_at': null,
      'status': 'active',
      'shift_count': 7,
      'total_profit': '812.50',
      'work_account_count': 2,
    });

    expect(user.displayName, 'Taylor');
    expect(user.cloudAccessEnabled, isTrue);
    expect(user.shiftCount, 7);
    expect(user.totalProfit, 812.5);
  });
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({required this.allowed});

  final bool allowed;
  final accessChanges = <(String, bool)>[];
  var users = <AdminUserSummary>[
    AdminUserSummary(
      id: 'driver-1',
      email: 'driver@example.com',
      driverName: 'Taylor',
      createdAt: DateTime.utc(2026, 8, 10),
      lastSignInAt: DateTime.utc(2026, 8, 14),
      cloudAccessEnabled: true,
      shiftCount: 7,
      totalProfit: 812.5,
      workAccountCount: 2,
    ),
  ];

  @override
  Future<bool> canAccessAdmin() async => allowed;

  @override
  Future<AdminOverview> loadOverview() async => const AdminOverview(
    drivers: 1,
    activeDrivers: 1,
    shifts: 7,
    connectedAccounts: 2,
    failedSyncs: 0,
    profit30Days: 812.5,
  );

  @override
  Future<List<AdminUserSummary>> loadUsers({String query = ''}) async => users;

  @override
  Future<void> setCloudAccess({
    required String userId,
    required bool enabled,
  }) async {
    accessChanges.add((userId, enabled));
    users = [
      for (final user in users)
        if (user.id == userId)
          AdminUserSummary(
            id: user.id,
            email: user.email,
            driverName: user.driverName,
            createdAt: user.createdAt,
            lastSignInAt: user.lastSignInAt,
            cloudAccessEnabled: enabled,
            shiftCount: user.shiftCount,
            totalProfit: user.totalProfit,
            workAccountCount: user.workAccountCount,
          )
        else
          user,
    ];
  }
}
