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
