import 'package:equatable/equatable.dart';
import '../../../data/models/referral_models.dart';

abstract class ReferralEvent extends Equatable {
  const ReferralEvent();

  @override
  List<Object?> get props => [];
}

class LoadReferralData extends ReferralEvent {
  final String? userId;
  const LoadReferralData({this.userId});

  @override
  List<Object?> get props => [userId];
}

class UpdateReferralStats extends ReferralEvent {
  final ReferralStats stats;
  const UpdateReferralStats(this.stats);

  @override
  List<Object?> get props => [stats];
}

class UpdateReferralNetwork extends ReferralEvent {
  final List<MemberNode> network;
  const UpdateReferralNetwork(this.network);

  @override
  List<Object?> get props => [network];
}

class UpdateRewardHistory extends ReferralEvent {
  final List<RewardTransaction> history;
  const UpdateRewardHistory(this.history);

  @override
  List<Object?> get props => [history];
}

class WithdrawRewards extends ReferralEvent {
  final double amount;
  const WithdrawRewards(this.amount);

  @override
  List<Object?> get props => [amount];
}
