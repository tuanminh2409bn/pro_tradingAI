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
  final int? generation;
  const UpdateReferralStats(this.stats, {this.generation});

  @override
  List<Object?> get props => [stats, generation];
}

class UpdateReferralNetwork extends ReferralEvent {
  final List<MemberNode> network;
  final int? generation;
  const UpdateReferralNetwork(this.network, {this.generation});

  @override
  List<Object?> get props => [network, generation];
}

class UpdateRewardHistory extends ReferralEvent {
  final List<RewardTransaction> history;
  final int? generation;
  const UpdateRewardHistory(this.history, {this.generation});

  @override
  List<Object?> get props => [history, generation];
}

class ReferralStreamFailed extends ReferralEvent {
  final int? generation;
  const ReferralStreamFailed({this.generation});
  @override
  List<Object?> get props => [generation];
}
