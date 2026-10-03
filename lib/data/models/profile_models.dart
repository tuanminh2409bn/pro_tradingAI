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
  final String? source;
  final DateTime? resetAt;
  final DateTime? backtestResetAt;

  const AccessQuota({
    required this.apiUsed,
    required this.apiLimit,
    required this.backtestUsed,
    required this.backtestLimit,
    required this.storageUsed,
    required this.storageLimit,
    this.source,
    this.resetAt,
    this.backtestResetAt,
  });

  const AccessQuota.unavailable()
    : apiUsed = 0,
      apiLimit = 0,
      backtestUsed = 0,
      backtestLimit = 0,
      storageUsed = 0,
      storageLimit = 0,
      source = null,
      resetAt = null,
      backtestResetAt = null;

  bool get isAuthoritative =>
      source == 'server_enforced' &&
      (resetAt != null || backtestResetAt != null) &&
      apiUsed >= 0 &&
      apiLimit >= 0 &&
      backtestUsed >= 0 &&
      backtestLimit >= 0 &&
      storageUsed >= 0 &&
      storageLimit >= 0;

  bool get hasApiQuota => isAuthoritative && resetAt != null && apiLimit > 0;
  bool get hasBacktestQuota =>
      isAuthoritative && backtestResetAt != null && backtestLimit > 0;
  bool get hasStorageQuota => isAuthoritative && storageLimit > 0;
  int? get apiRemaining =>
      hasApiQuota ? (apiLimit - apiUsed < 0 ? 0 : apiLimit - apiUsed) : null;

  @override
  List<Object?> get props => [
    apiUsed,
    apiLimit,
    backtestUsed,
    backtestLimit,
    storageUsed,
    storageLimit,
    source,
    resetAt,
    backtestResetAt,
  ];
}
