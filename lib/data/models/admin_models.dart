import 'package:equatable/equatable.dart';

class SystemStats extends Equatable {
  final int dau;
  final int mau;
  final double growth;
  final int latency;
  final int pendingAlerts;

  const SystemStats({
    required this.dau,
    required this.mau,
    required this.growth,
    required this.latency,
    required this.pendingAlerts,
  });

  @override
  List<Object?> get props => [dau, mau, latency];
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
