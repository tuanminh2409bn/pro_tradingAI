import 'package:equatable/equatable.dart';

class SystemStats extends Equatable {
  final int dau;
  final int mau;
  final double growth;
  final int latency;
  final int pendingAlerts;
  final int totalTrades;
  final int activeSessions;
  final double globalPnl;

  const SystemStats({
    required this.dau,
    required this.mau,
    required this.growth,
    required this.latency,
    required this.pendingAlerts,
    this.totalTrades = 0,
    this.activeSessions = 0,
    this.globalPnl = 0.0,
  });

  @override
  List<Object?> get props => [dau, mau, latency, totalTrades, globalPnl];
}

class PendingRequest extends Equatable {
  final String userId;
  final String username;
  final String type; // 'WITHDRAWAL', 'REWARD'
  final String amount;
  final DateTime date;

  const PendingRequest({
    required this.userId,
    required this.username,
    required this.type,
    required this.amount,
    required this.date,
  });

  @override
  List<Object?> get props => [userId, type, amount];
}

class AIConfig extends Equatable {
  final String masterPrompt;
  final String lastUpdatedBy;
  final DateTime? lastUpdatedAt;

  const AIConfig({
    required this.masterPrompt,
    required this.lastUpdatedBy,
    this.lastUpdatedAt,
  });

  factory AIConfig.fromMap(Map<String, dynamic> map) {
    return AIConfig(
      masterPrompt: map['ai_master_prompt'] ?? '',
      lastUpdatedBy: map['lastUpdatedBy'] ?? '',
      lastUpdatedAt: map['lastUpdatedAt'] != null
          ? (map['lastUpdatedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ai_master_prompt': masterPrompt,
      'lastUpdatedBy': lastUpdatedBy,
      'lastUpdatedAt': lastUpdatedAt,
    };
  }

  @override
  List<Object?> get props => [masterPrompt, lastUpdatedBy, lastUpdatedAt];
}

class ServiceStatus extends Equatable {
  final String name;
  final bool isOnline;
  final int latencyMs;

  const ServiceStatus({
    required this.name,
    required this.isOnline,
    required this.latencyMs,
  });

  @override
  List<Object?> get props => [name, isOnline, latencyMs];
}

class GlobalRiskConfig extends Equatable {
  final String maxLeverage; // '1:100', '1:500', '1:1000'
  final bool newsGuardEnabled;
  final double maxDrawdownPct;

  const GlobalRiskConfig({
    this.maxLeverage = '1:500',
    this.newsGuardEnabled = true,
    this.maxDrawdownPct = 5.0,
  });

  factory GlobalRiskConfig.fromMap(Map<String, dynamic> map) {
    return GlobalRiskConfig(
      maxLeverage: map['maxLeverage'] ?? '1:500',
      newsGuardEnabled: map['newsGuardEnabled'] ?? true,
      maxDrawdownPct: (map['maxDrawdownPct'] ?? 5.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'maxLeverage': maxLeverage,
        'newsGuardEnabled': newsGuardEnabled,
        'maxDrawdownPct': maxDrawdownPct,
      };

  @override
  List<Object?> get props => [maxLeverage, newsGuardEnabled, maxDrawdownPct];
}
