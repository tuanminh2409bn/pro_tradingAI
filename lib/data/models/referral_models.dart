import 'package:equatable/equatable.dart';

class ReferralStats extends Equatable {
  final double totalEarnings;
  final int f1Count;
  final int f2Count;
  final String referralLink;

  const ReferralStats({
    required this.totalEarnings,
    required this.f1Count,
    required this.f2Count,
    required this.referralLink,
  });

  @override
  List<Object?> get props => [totalEarnings, f1Count, f2Count, referralLink];
}

class MemberNode extends Equatable {
  final String id;
  final String name;
  final String avatarUrl;
  final double earningsContribution;
  final String level; // 'F1', 'F2'

  const MemberNode({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.earningsContribution,
    required this.level,
  });

  @override
  List<Object?> get props => [id, name, level];
}

class RewardTransaction extends Equatable {
  final String title;
  final DateTime date;
  final double amount;
  final String status; // 'COMPLETED', 'PROCESSED'
  final String type; // 'COMMISSION', 'BONUS', 'WITHDRAWAL'

  const RewardTransaction({
    required this.title,
    required this.date,
    required this.amount,
    required this.status,
    required this.type,
  });

  @override
  List<Object?> get props => [title, date, amount, status];
}
