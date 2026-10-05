import 'package:equatable/equatable.dart';
import '../../../data/models/admin_models.dart';

abstract class AdminState extends Equatable {
  const AdminState();
  @override
  List<Object?> get props => [];
}

class AdminInitial extends AdminState {}

class AdminLoading extends AdminState {}

class AdminLoaded extends AdminState {
  final SystemStats stats;
  final List<PendingRequest> requests;
  final AIConfig? aiConfig;
  final bool aiConfigSaving;
  final bool aiConfigLoaded;
  final bool tradingEnabled;
  final List<ServiceStatus> serviceStatuses;
  final GlobalRiskConfig globalRisk;
  final int actionResultNonce;
  final String actionMessageKey;
  final bool actionSucceeded;
  final List<Map<String, dynamic>> dailyStats;
  final RadarAdminConfig? radarConfig;
  final bool radarConfigLoaded;
  final bool referralReceiptBusy;
  final String? lastReferralReceiptId;

  const AdminLoaded({
    required this.stats,
    required this.requests,
    this.aiConfig,
    this.aiConfigSaving = false,
    this.aiConfigLoaded = false,
    this.tradingEnabled = false,
    this.serviceStatuses = const [],
    this.globalRisk = const GlobalRiskConfig.unavailable(),
    this.actionResultNonce = 0,
    this.actionMessageKey = '',
    this.actionSucceeded = false,
    this.dailyStats = const [],
    this.radarConfig,
    this.radarConfigLoaded = false,
    this.referralReceiptBusy = false,
    this.lastReferralReceiptId,
  });

  AdminLoaded copyWith({
    SystemStats? stats,
    List<PendingRequest>? requests,
    AIConfig? aiConfig,
    bool? aiConfigSaving,
    bool? aiConfigLoaded,
    bool? tradingEnabled,
    List<ServiceStatus>? serviceStatuses,
    GlobalRiskConfig? globalRisk,
    int? actionResultNonce,
    String? actionMessageKey,
    bool? actionSucceeded,
    List<Map<String, dynamic>>? dailyStats,
    RadarAdminConfig? radarConfig,
    bool? radarConfigLoaded,
    bool? referralReceiptBusy,
    String? lastReferralReceiptId,
  }) {
    return AdminLoaded(
      stats: stats ?? this.stats,
      requests: requests ?? this.requests,
      aiConfig: aiConfig ?? this.aiConfig,
      aiConfigSaving: aiConfigSaving ?? this.aiConfigSaving,
      aiConfigLoaded: aiConfigLoaded ?? this.aiConfigLoaded,
      tradingEnabled: tradingEnabled ?? this.tradingEnabled,
      serviceStatuses: serviceStatuses ?? this.serviceStatuses,
      globalRisk: globalRisk ?? this.globalRisk,
      actionResultNonce: actionResultNonce ?? this.actionResultNonce,
      actionMessageKey: actionMessageKey ?? this.actionMessageKey,
      actionSucceeded: actionSucceeded ?? this.actionSucceeded,
      dailyStats: dailyStats ?? this.dailyStats,
      radarConfig: radarConfig ?? this.radarConfig,
      radarConfigLoaded: radarConfigLoaded ?? this.radarConfigLoaded,
      referralReceiptBusy: referralReceiptBusy ?? this.referralReceiptBusy,
      lastReferralReceiptId:
          lastReferralReceiptId ?? this.lastReferralReceiptId,
    );
  }

  @override
  List<Object?> get props => [
    referralReceiptBusy,
    lastReferralReceiptId,
    stats,
    requests,
    aiConfig,
    aiConfigSaving,
    aiConfigLoaded,
    tradingEnabled,
    serviceStatuses,
    globalRisk,
    actionResultNonce,
    actionMessageKey,
    actionSucceeded,
    dailyStats,
    radarConfig,
    radarConfigLoaded,
  ];
}

class AdminError extends AdminState {
  final String message;
  const AdminError(this.message);
  @override
  List<Object?> get props => [message];
}
