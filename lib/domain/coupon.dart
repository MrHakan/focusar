import 'json_reader.dart';

/// Screen time bought back with credits.
///
/// FocusAR cannot switch off the rest of the phone — neither platform lets a
/// third-party app do that — so a coupon is a budget you hold yourself. It
/// records what you earned the right to spend, and when that right lapses.
class Coupon {
  const Coupon({
    required this.issuedAt,
    required this.amount,
    required this.cost,
    this.spent = false,
  });

  /// A coupon is worth using while it is fresh.
  static const Duration validity = Duration(hours: 24);

  final DateTime issuedAt;

  /// Screen time this coupon unlocks.
  final Duration amount;

  /// Credits it cost to issue.
  final double cost;

  final bool spent;

  DateTime get expiresAt => issuedAt.add(validity);

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  bool isRedeemable(DateTime now) => !spent && !isExpired(now);

  Duration remainingValidity(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Coupon copyWith({bool? spent}) => Coupon(
        issuedAt: issuedAt,
        amount: amount,
        cost: cost,
        spent: spent ?? this.spent,
      );

  Map<String, dynamic> toJson() => {
        'issuedAt': issuedAt.toIso8601String(),
        'amountSeconds': amount.inSeconds,
        'cost': cost,
        'spent': spent,
      };

  static Coupon fromJson(Map<String, dynamic> json) => Coupon(
        issuedAt: json.readDate('issuedAt') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        amount: json.readDuration('amountSeconds'),
        cost: json.readDouble('cost'),
        spent: json.readBool('spent'),
      );
}
