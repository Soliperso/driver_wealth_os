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
