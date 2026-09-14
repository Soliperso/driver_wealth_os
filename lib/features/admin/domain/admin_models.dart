class AdminOverview {
  const AdminOverview({
    required this.drivers,
    required this.activeDrivers,
    required this.shifts,
    required this.connectedAccounts,
    required this.failedSyncs,
    required this.profit30Days,
  });

  final int drivers;
  final int activeDrivers;
  final int shifts;
  final int connectedAccounts;
  final int failedSyncs;
  final double profit30Days;

  factory AdminOverview.fromJson(Map<String, dynamic> json) => AdminOverview(
    drivers: _integer(json['drivers']),
    activeDrivers: _integer(json['active_drivers']),
    shifts: _integer(json['shifts']),
    connectedAccounts: _integer(json['connected_accounts']),
    failedSyncs: _integer(json['failed_syncs']),
    profit30Days: _decimal(json['profit_30d']),
  );
}

class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.email,
    required this.driverName,
    required this.createdAt,
    required this.lastSignInAt,
    required this.cloudAccessEnabled,
    required this.shiftCount,
    required this.totalProfit,
    required this.workAccountCount,
  });

  final String id;
  final String? email;
  final String? driverName;
  final DateTime createdAt;
  final DateTime? lastSignInAt;
  final bool cloudAccessEnabled;
  final int shiftCount;
  final double totalProfit;
  final int workAccountCount;

  String get displayName {
    final name = driverName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final address = email?.trim();
    if (address != null && address.isNotEmpty) return address;
    return 'Driver';
  }

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    if (createdAt == null) {
      throw const FormatException('Admin user is missing created_at');
    }
    return AdminUserSummary(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      driverName: json['driver_name']?.toString(),
      createdAt: createdAt,
      lastSignInAt: DateTime.tryParse(
        json['last_sign_in_at']?.toString() ?? '',
      ),
      cloudAccessEnabled: json['status'] == 'active',
      shiftCount: _integer(json['shift_count']),
      totalProfit: _decimal(json['total_profit']),
      workAccountCount: _integer(json['work_account_count']),
    );
  }
}

/// Which drivers the list is asking for.
///
/// Sent to the server rather than applied to the page after it arrives: a
/// filter that ran on the client would only ever narrow the rows already
/// fetched, so "Paused" would show the paused drivers *in the first page*
/// rather than the paused drivers.
enum AdminAccessFilter {
  all(null, 'All'),
  active('active', 'Active'),
  paused('suspended', 'Paused');

  const AdminAccessFilter(this.id, this.label);

  /// The `status` value the control plane stores, or null for no filter.
  final String? id;
  final String label;
}

/// One page of drivers, plus how many the filter matched in total.
///
/// [total] counts the whole matching set, not this page, which is what lets the
/// dashboard say how many are left and decide whether to offer another page.
class AdminUserPage {
  const AdminUserPage({required this.users, required this.total});

  const AdminUserPage.empty() : users = const [], total = 0;

  /// The control plane's own ceiling on one request. Refetching the rows
  /// already on screen has to stop here, or a deep list would ask for more than
  /// the server will return and silently lose the tail.
  static const maxRows = 200;

  final List<AdminUserSummary> users;
  final int total;

  bool get hasMore => users.length < total;

  /// Appends the next page, keeping the server's ordering.
  AdminUserPage followedBy(AdminUserPage next) => AdminUserPage(
    users: [...users, ...next.users],
    // The later count wins: rows can be added or removed between requests, and
    // a stale total would leave the list offering a page that is not there.
    total: next.total,
  );

  factory AdminUserPage.fromJson(Object? json) {
    // A jsonb object with `rows` and `total`. A bare list is what the previous
    // control-plane function returned, and is still accepted so a client
    // running against an un-migrated project degrades to a single page rather
    // than an error screen.
    if (json is List) {
      final users = _usersFrom(json);
      return AdminUserPage(users: users, total: users.length);
    }
    if (json is! Map) {
      throw const FormatException('The driver list was not an object');
    }
    final users = _usersFrom(json['rows']);
    return AdminUserPage(
      users: users,
      total: json.containsKey('total') ? _integer(json['total']) : users.length,
    );
  }

  static List<AdminUserSummary> _usersFrom(Object? rows) => [
    if (rows is List)
      for (final row in rows)
        if (row is Map)
          AdminUserSummary.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
  ];
}

/// What an owner did, and to whom.
///
/// Read-only in the client. The log is written by the control plane and has no
/// row-level policy, so nothing here can edit or delete an entry.
class AdminAction {
  const AdminAction({
    required this.id,
    required this.paused,
    required this.actorEmail,
    required this.targetLabel,
    required this.at,
  });

  final String id;

  /// True for a pause, false for a restore.
  final bool paused;

  final String? actorEmail;

  /// The driver's name if the control plane still has one, otherwise their
  /// email — the log keeps a copy of both so a deleted account still reads as
  /// something more useful than a bare id.
  final String targetLabel;

  final DateTime at;

  String get summary => paused
      ? 'Paused cloud access for $targetLabel'
      : 'Restored cloud access for $targetLabel';

  factory AdminAction.fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['created_at']?.toString() ?? '');
    if (at == null) {
      throw const FormatException('Admin action is missing created_at');
    }
    final name = json['target_name']?.toString().trim();
    final email = json['target_email']?.toString().trim();
    return AdminAction(
      id: json['id']?.toString() ?? '',
      paused: json['action'] == 'cloud_access_paused',
      actorEmail: json['actor_email']?.toString(),
      targetLabel: name != null && name.isNotEmpty
          ? name
          : (email != null && email.isNotEmpty ? email : 'a deleted account'),
      at: at,
    );
  }
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

double _decimal(Object? value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text) ?? 0,
  _ => 0,
};
