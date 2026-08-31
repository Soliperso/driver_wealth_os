/// A cost that is not attached to one shift.
///
/// Until now an expense was a single scalar on a `Shift` — fuel, tolls and
/// parking for that day. That covers what a driver spends *while* driving and
/// nothing else: a brake job, an insurance premium, a phone bill and a car
/// payment are all real costs of the business and none of them belong to a
/// shift. They were simply unrecordable, which understated every driver's
/// costs and made the tax year impossible to assemble.
library;

/// The Schedule C line an expense belongs on.
///
/// Named for what a driver recognises, with the IRS line noted, because the
/// point of categorising at all is that the totals can be transcribed onto the
/// form — or handed to an accountant — without a second pass.
enum ExpenseCategory {
  fuel('Fuel', 'Car and truck expenses', isVehicleCost: true),
  maintenance(
    'Maintenance & repairs',
    'Car and truck expenses',
    isVehicleCost: true,
  ),
  insurance('Vehicle insurance', 'Car and truck expenses', isVehicleCost: true),
  vehiclePayment(
    'Car payment or lease',
    'Car and truck expenses',
    isVehicleCost: true,
  ),
  registration(
    'Registration & licensing',
    'Taxes and licenses',
    isVehicleCost: true,
  ),
  tollsAndParking(
    'Tolls & parking',
    'Car and truck expenses',
    isVehicleCost: true,
  ),

  // Everything below is claimable alongside either vehicle method.
  phone('Phone & data', 'Utilities'),
  supplies('Supplies', 'Supplies'),
  platformFees('Platform fees & commissions', 'Commissions and fees'),
  healthInsurance('Health insurance', 'Self-employed health insurance'),
  other('Other', 'Other expenses');

  const ExpenseCategory(
    this.label,
    this.scheduleCLine, {
    this.isVehicleCost = false,
  });

  final String label;

  /// The Schedule C heading this rolls up to.
  final String scheduleCLine;

  /// True when the cost is part of running the car.
  ///
  /// This is the flag that decides the standard-mileage comparison. The
  /// standard rate already covers fuel, maintenance, insurance and
  /// depreciation, so a driver claiming it cannot also claim these — they are
  /// the *alternative*, not an addition. Miscategorising here double-counts a
  /// cost on someone's tax return, which is why the flag lives on the category
  /// rather than being decided at the call site.
  final bool isVehicleCost;

  static ExpenseCategory fromId(Object? value) => values.firstWhere(
    (category) => category.name == value,
    orElse: () => ExpenseCategory.other,
  );
}

class Expense {
  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.incurredOn,
    this.note = '',
    this.receiptPath,
  });

  final String id;
  final double amount;
  final ExpenseCategory category;
  final DateTime incurredOn;
  final String note;

  /// A photo of the receipt, stored on the device only.
  ///
  /// The path is synced but the image is not: a receipt can carry a card
  /// number and a home address, and pushing every driver's shoebox to a server
  /// is a liability the app has no reason to take on. A second device shows
  /// the entry without the photo.
  final String? receiptPath;

  bool occurredIn(int year) => incurredOn.year == year;

  /// [clearReceipt] removes the photo rather than keeping it.
  ///
  /// A plain null `receiptPath` cannot mean "remove", because that is also what
  /// every caller that is not touching the receipt passes — including the sync
  /// merge, which relies on null meaning "leave the local photo alone".
  Expense copyWith({
    double? amount,
    ExpenseCategory? category,
    DateTime? incurredOn,
    String? note,
    String? receiptPath,
    bool clearReceipt = false,
  }) => Expense(
    id: id,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    incurredOn: incurredOn ?? this.incurredOn,
    note: note ?? this.note,
    receiptPath: clearReceipt ? null : (receiptPath ?? this.receiptPath),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'amount': amount,
    'category': category.name,
    'incurredOn': incurredOn.toIso8601String(),
    'note': note,
    'receiptPath': receiptPath,
  };

  factory Expense.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final incurredOn = DateTime.tryParse(json['incurredOn'] as String? ?? '');
    if (id is! String || id.isEmpty || incurredOn == null) {
      throw const FormatException('Invalid expense identity');
    }
    return Expense(
      id: id,
      amount: _number(json['amount']),
      category: ExpenseCategory.fromId(json['category']),
      incurredOn: incurredOn,
      note: json['note'] as String? ?? '',
      receiptPath: json['receiptPath'] as String?,
    );
  }

  static double _number(Object? value) {
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    throw const FormatException('Invalid expense amount');
  }

  @override
  bool operator ==(Object other) =>
      other is Expense &&
      other.id == id &&
      other.amount == amount &&
      other.category == category &&
      other.incurredOn == incurredOn &&
      other.note == note &&
      other.receiptPath == receiptPath;

  @override
  int get hashCode =>
      Object.hash(id, amount, category, incurredOn, note, receiptPath);
}
