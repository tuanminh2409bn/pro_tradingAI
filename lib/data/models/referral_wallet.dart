import 'package:equatable/equatable.dart';

class ReferralWallet extends Equatable {
  final int creditsMinor;
  final int reversedMinor;
  final int heldMinor;
  final int paidMinor;
  final String? pendingRequestId;
  const ReferralWallet._(
    this.creditsMinor,
    this.reversedMinor,
    this.heldMinor,
    this.paidMinor,
    this.pendingRequestId,
  );

  static ReferralWallet? fromServer(Map<String, dynamic> data) {
    if (data['currency'] != 'USD' ||
        data['source'] != 'admin_verified_receipts' ||
        data['policyVersion'] != 'manual-subscription-v1') {
      return null;
    }
    final values = [
      'creditsMinor',
      'reversedMinor',
      'heldMinor',
      'paidMinor',
    ].map((key) => data[key]).toList();
    if (values.any((v) => v is! int || v < 0 || v > 1000000000000)) return null;
    final amounts = values.cast<int>();
    if (amounts[1] > amounts[0] || amounts[2] + amounts[3] > amounts[0]) {
      return null;
    }
    final pending = data['pendingRequestId'];
    if (pending != null &&
        (pending is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(pending))) {
      return null;
    }
    return ReferralWallet._(
      amounts[0],
      amounts[1],
      amounts[2],
      amounts[3],
      pending as String?,
    );
  }

  int get availableMinor =>
      creditsMinor - reversedMinor - heldMinor - paidMinor;
  bool get canRequestWithdrawal =>
      pendingRequestId == null && availableMinor >= 2000;
  static String money(int minor) =>
      '${minor < 0 ? '-' : ''}USD ${minor.abs() ~/ 100}.${(minor.abs() % 100).toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [
    creditsMinor,
    reversedMinor,
    heldMinor,
    paidMinor,
    pendingRequestId,
  ];
}

class ReferralWithdrawal extends Equatable {
  final String id;
  final String status;
  final int amountMinor;
  final DateTime createdAt;
  const ReferralWithdrawal._(
    this.id,
    this.status,
    this.amountMinor,
    this.createdAt,
  );
  static ReferralWithdrawal? fromServer(
    String id,
    Map<String, dynamic> data,
    DateTime? date,
  ) {
    final amount = data['amountMinor'];
    final status = data['status'];
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        data['currency'] != 'USD' ||
        data['policyVersion'] != 'manual-subscription-v1' ||
        date == null ||
        amount is! int ||
        amount < 2000 ||
        amount > 1000000000000 ||
        !{'PENDING', 'APPROVED', 'REJECTED', 'PAID'}.contains(status)) {
      return null;
    }
    return ReferralWithdrawal._(id, status as String, amount, date);
  }

  @override
  List<Object?> get props => [id, status, amountMinor, createdAt];
}
