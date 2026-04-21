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

  const AdminLoaded({
    required this.stats,
    required this.requests,
  });

  AdminLoaded copyWith({
    SystemStats? stats,
    List<PendingRequest>? requests,
  }) {
    return AdminLoaded(
      stats: stats ?? this.stats,
      requests: requests ?? this.requests,
    );
  }

  @override
  List<Object?> get props => [stats, requests];
}

class AdminError extends AdminState {
  final String message;
  const AdminError(this.message);

  @override
  List<Object?> get props => [message];
}
