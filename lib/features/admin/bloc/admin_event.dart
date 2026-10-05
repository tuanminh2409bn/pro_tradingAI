import 'package:equatable/equatable.dart';
import '../../../data/models/admin_models.dart';

abstract class AdminEvent extends Equatable {
  const AdminEvent();
  @override
  List<Object?> get props => [];
}

class LoadAdminData extends AdminEvent {}

class UpdateSystemStats extends AdminEvent {
  final SystemStats stats;
  const UpdateSystemStats(this.stats);
  @override
  List<Object?> get props => [stats];
}

class UpdatePendingRequests extends AdminEvent {
  final List<PendingRequest> requests;
  const UpdatePendingRequests(this.requests);
  @override
  List<Object?> get props => [requests];
}

class BroadcastRequested extends AdminEvent {
  final String message;
  final String tier;
  const BroadcastRequested(this.message, this.tier);
  @override
  List<Object?> get props => [message, tier];
}

class HandleRequest extends AdminEvent {
  final String requestId;
  final bool approve;
  const HandleRequest(this.requestId, this.approve);
  @override
  List<Object?> get props => [requestId, approve];
}

class LoadAIConfig extends AdminEvent {}

class ConfirmReferralPayment extends AdminEvent {
  final String requestId;
  final String paymentReference;
  const ConfirmReferralPayment(this.requestId, this.paymentReference);
  @override
  List<Object?> get props => [requestId, paymentReference];
}

class ImportReferralReceipt extends AdminEvent {
  final String receiptId;
  final String payerUid;
  final int netMinor;
  final DateTime settledAt;
  const ImportReferralReceipt(
    this.receiptId,
    this.payerUid,
    this.netMinor,
    this.settledAt,
  );
  @override
  List<Object?> get props => [receiptId, payerUid, netMinor, settledAt];
}

class ReverseReferralReceipt extends AdminEvent {
  final String receiptId;
  const ReverseReferralReceipt(this.receiptId);
  @override
  List<Object?> get props => [receiptId];
}

class SaveAIConfig extends AdminEvent {
  final String masterPrompt;
  const SaveAIConfig(this.masterPrompt);
  @override
  List<Object?> get props => [masterPrompt];
}

// ─── New events ───

class ToggleKillSwitch extends AdminEvent {
  final bool enabled;
  const ToggleKillSwitch(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class UpdateKillSwitch extends AdminEvent {
  final bool enabled;
  const UpdateKillSwitch(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class SaveGlobalRisk extends AdminEvent {
  final GlobalRiskConfig config;
  const SaveGlobalRisk(this.config);
  @override
  List<Object?> get props => [config];
}

class UpdateGlobalRisk extends AdminEvent {
  final GlobalRiskConfig config;
  const UpdateGlobalRisk(this.config);
  @override
  List<Object?> get props => [config];
}

class UpdateServiceStatus extends AdminEvent {
  final List<ServiceStatus> statuses;
  const UpdateServiceStatus(this.statuses);
  @override
  List<Object?> get props => [statuses];
}

class SaveRadarConfig extends AdminEvent {
  final List<String> symbols;
  final double sensitivity;
  const SaveRadarConfig(this.symbols, this.sensitivity);
  @override
  List<Object?> get props => [symbols, sensitivity];
}

class AdminStreamFailed extends AdminEvent {
  const AdminStreamFailed();
}

class LoadDailyStats extends AdminEvent {
  const LoadDailyStats();
}

class UpdateDailyStats extends AdminEvent {
  final List<Map<String, dynamic>> dailyStats;
  const UpdateDailyStats(this.dailyStats);

  @override
  List<Object?> get props => [dailyStats];
}

class LoadRadarConfig extends AdminEvent {
  const LoadRadarConfig();
}

class UpdateRadarConfig extends AdminEvent {
  final RadarAdminConfig? config;
  const UpdateRadarConfig(this.config);

  @override
  List<Object?> get props => [config];
}
