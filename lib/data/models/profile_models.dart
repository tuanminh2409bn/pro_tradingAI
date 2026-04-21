import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String username;
  final String email;
  final String tier; // 'FREE', 'VIP', 'ENTERPRISE'
  final int totalTrades;
  final double winRate;
  final int rank;
  final String avatarUrl;

  const UserProfile({
    required this.username,
    required this.email,
    required this.tier,
    required this.totalTrades,
    required this.winRate,
    required this.rank,
    required this.avatarUrl,
  });

  @override
  List<Object?> get props => [username, email, tier, rank];
}

class AccessQuota extends Equatable {
  final int apiUsed;
  final int apiLimit;
  final int backtestUsed;
  final int backtestLimit;
  final double storageUsed;
  final double storageLimit;

  const AccessQuota({
    required this.apiUsed,
    required this.apiLimit,
    required this.backtestUsed,
    required this.backtestLimit,
    required this.storageUsed,
    required this.storageLimit,
  });

  @override
  List<Object?> get props => [apiUsed, backtestUsed, storageUsed];
}
