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

class BrokerAccount extends Equatable {
  final String accountId;
  final String platform; // 'mt4' or 'mt5'
  final String server;
  final String login;
  final String status; // 'CONNECTED', 'DISCONNECTED', 'PENDING'

  const BrokerAccount({
    required this.accountId,
    required this.platform,
    required this.server,
    required this.login,
    required this.status,
  });

  @override
  List<Object?> get props => [accountId, platform, server, login, status];
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
