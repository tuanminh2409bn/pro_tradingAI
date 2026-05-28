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
  final bool tradingEnabled;
  final List<ServiceStatus> serviceStatuses;
  final GlobalRiskConfig globalRisk;

  const AdminLoaded({
    required this.stats,
    required this.requests,
    this.aiConfig,
    this.aiConfigSaving = false,
    this.tradingEnabled = true,
    this.serviceStatuses = const [],
    this.globalRisk = const GlobalRiskConfig(),
  });

  AdminLoaded copyWith({
    SystemStats? stats,
    List<PendingRequest>? requests,
    AIConfig? aiConfig,
    bool? aiConfigSaving,
    bool? tradingEnabled,
    List<ServiceStatus>? serviceStatuses,
    GlobalRiskConfig? globalRisk,
  }) {
    return AdminLoaded(
      stats: stats ?? this.stats,
      requests: requests ?? this.requests,
      aiConfig: aiConfig ?? this.aiConfig,
      aiConfigSaving: aiConfigSaving ?? this.aiConfigSaving,
      tradingEnabled: tradingEnabled ?? this.tradingEnabled,
      serviceStatuses: serviceStatuses ?? this.serviceStatuses,
      globalRisk: globalRisk ?? this.globalRisk,
    );
  }

  @override
  List<Object?> get props => [stats, requests, aiConfig, aiConfigSaving, tradingEnabled, serviceStatuses, globalRisk];
}

class AdminError extends AdminState {
  final String message;
  const AdminError(this.message);
  @override
  List<Object?> get props => [message];
}
