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
      KeeprateApp(
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
      KeeprateApp(
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

  testWidgets('the paused filter is applied by the server, not the page', (
    tester,
  ) async {
    final admin = _FakeAdminRepository(
      allowed: true,
      users: [
        _driver('driver-1', name: 'Taylor'),
        _driver('driver-2', name: 'Sam', active: false),
      ],
    );
    await _openDashboard(tester, admin);

    expect(find.text('Taylor'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-filter-paused')));
    await tester.pumpAndSettle();

    // The request carried the filter, rather than every row arriving and being
    // narrowed here — which is what makes the count and paging trustworthy.
    expect(admin.requests.last.filter, AdminAccessFilter.paused);
    expect(find.text('Taylor'), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-user-count')), findsOneWidget);
  });

  testWidgets('an empty paused list says so rather than blaming the search', (
    tester,
  ) async {
    final admin = _FakeAdminRepository(
      allowed: true,
      users: [_driver('driver-1', name: 'Taylor')],
    );
    await _openDashboard(tester, admin);

    await tester.tap(find.byKey(const ValueKey('admin-filter-paused')));
    await tester.pumpAndSettle();

    expect(find.text('No drivers have their access paused.'), findsOneWidget);
  });

  testWidgets('a list longer than one page loads the rest on request', (
    tester,
  ) async {
    final admin = _FakeAdminRepository(
      allowed: true,
      users: [
        for (var index = 0; index < 52; index++)
          _driver(
            'driver-$index',
            name: 'Driver $index',
            createdAt: DateTime.utc(2026, 8, 10).add(Duration(minutes: index)),
          ),
      ],
    );
    await _openDashboard(tester, admin);

    // The count must not imply the list is complete when it is one page of it.
    expect(find.text('50 of 52'), findsOneWidget);

    final scrollable = find
        .descendant(
          of: find.byType(AdminDashboardScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin-load-more')),
      400,
      scrollable: scrollable,
    );
    expect(find.text('Load 2 more'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-load-more')));
    await tester.pumpAndSettle();

    expect(admin.requests.last.offset, 50);
    expect(find.byKey(const ValueKey('admin-load-more')), findsNothing);

    // Back to the top, where the count now has to stop saying "of".
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('admin-user-count')),
      -400,
      scrollable: scrollable,
    );
    expect(find.text('52 drivers'), findsOneWidget);
  });

  testWidgets('pausing a driver is recorded in the access trail', (
    tester,
  ) async {
    final admin = _FakeAdminRepository(
      allowed: true,
      users: [_driver('driver-1', name: 'Taylor')],
    );
    await _openDashboard(tester, admin);

    expect(find.text('No access has been paused or restored yet.'), findsOne);

    await tester.tap(find.byKey(const ValueKey('admin-cloud-access-driver-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause access'));
    await tester.pumpAndSettle();

    expect(admin.accessChanges, [('driver-1', false)]);
    expect(find.text('Paused cloud access for Taylor'), findsOneWidget);
    expect(find.textContaining('owner@example.com'), findsOneWidget);
  });

  test('a driver page reads both the paged and the legacy shapes', () {
    const row = {
      'id': 'driver-1',
      'email': 'driver@example.com',
      'driver_name': 'Taylor',
      'created_at': '2026-08-14T12:00:00Z',
      'status': 'active',
      'shift_count': 7,
      'total_profit': '812.50',
      'work_account_count': 2,
    };

    final paged = AdminUserPage.fromJson({
      'total': 90,
      'rows': [row],
    });
    expect(paged.users.single.displayName, 'Taylor');
    expect(paged.total, 90);
    expect(paged.hasMore, isTrue);

    // An un-migrated project still answers with a bare array. That degrades to
    // a single complete page instead of an error screen.
    final legacy = AdminUserPage.fromJson([row]);
    expect(legacy.total, 1);
    expect(legacy.hasMore, isFalse);
  });
}

/// Opens the dashboard on a surface tall enough that the overview, the driver
/// list and the access trail are all built. The default 800×600 test window
/// leaves most of a lazy [ListView] unrendered, which reads as "the widget is
/// missing" rather than "the widget is below the fold".
Future<void> _openDashboard(
  WidgetTester tester,
  _FakeAdminRepository admin,
) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminDashboardScreen(repository: admin)),
  );
  await tester.pumpAndSettle();
}

AdminUserSummary _driver(
  String id, {
  String? name,
  bool active = true,
  DateTime? createdAt,
}) => AdminUserSummary(
  id: id,
  email: '$id@example.com',
  driverName: name,
  createdAt: createdAt ?? DateTime.utc(2026, 8, 10),
  lastSignInAt: DateTime.utc(2026, 8, 14),
  cloudAccessEnabled: active,
  shiftCount: 7,
  totalProfit: 812.5,
  workAccountCount: 2,
);

/// Applies the search, the status filter and the window server-side, the way
/// the control plane does. A fake that returned every row regardless would let
/// a client-side filter or an off-by-one page look like it worked.
class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({required this.allowed, List<AdminUserSummary>? users})
    : users = users ?? [_driver('driver-1', name: 'Taylor')];

  final bool allowed;
  final accessChanges = <(String, bool)>[];
  final actions = <AdminAction>[];
  final requests = <({String query, AdminAccessFilter filter, int offset})>[];
  List<AdminUserSummary> users;

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
  Future<List<AdminAction>> loadRecentActions() async => actions;

  @override
  Future<AdminUserPage> loadUsers({
    String query = '',
    AdminAccessFilter filter = AdminAccessFilter.all,
    int limit = 50,
    int offset = 0,
  }) async {
    requests.add((query: query, filter: filter, offset: offset));
    final needle = query.trim().toLowerCase();
    final matched = [
      for (final user in users)
        if ((needle.isEmpty ||
                user.displayName.toLowerCase().contains(needle) ||
                (user.email ?? '').toLowerCase().contains(needle)) &&
            switch (filter) {
              AdminAccessFilter.all => true,
              AdminAccessFilter.active => user.cloudAccessEnabled,
              AdminAccessFilter.paused => !user.cloudAccessEnabled,
            })
          user,
    ];
    return AdminUserPage(
      total: matched.length,
      users: matched.skip(offset).take(limit).toList(),
    );
  }

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
    actions.insert(
      0,
      AdminAction(
        id: '${actions.length + 1}',
        paused: !enabled,
        actorEmail: 'owner@example.com',
        targetLabel: users.firstWhere((user) => user.id == userId).displayName,
        at: DateTime.utc(2026, 9, 1, 10),
      ),
    );
  }
}
