import 'package:equatable/equatable.dart';
import '../../../data/models/referral_models.dart';

abstract class ReferralState extends Equatable {
  const ReferralState();

  @override
  List<Object?> get props => [];
}

class ReferralInitial extends ReferralState {}

class ReferralLoading extends ReferralState {}

class ReferralLoaded extends ReferralState {
  final ReferralStats stats;
  final List<MemberNode> network;
  final List<RewardTransaction> history;

  const ReferralLoaded({
    required this.stats,
    required this.network,
    required this.history,
  });

  ReferralLoaded copyWith({
    ReferralStats? stats,
    List<MemberNode>? network,
    List<RewardTransaction>? history,
  }) {
    return ReferralLoaded(
      stats: stats ?? this.stats,
      network: network ?? this.network,
      history: history ?? this.history,
    );
  }

  @override
  List<Object?> get props => [stats, network, history];
}

class ReferralError extends ReferralState {
  final String message;
  const ReferralError(this.message);

  @override
  List<Object?> get props => [message];
}
