import 'package:equatable/equatable.dart';
import '../../../data/models/community_models.dart';

abstract class CommunityState extends Equatable {
  const CommunityState();

  @override
  List<Object?> get props => [];
}

class CommunityInitial extends CommunityState {}

class CommunityLoading extends CommunityState {}

class CommunityLoaded extends CommunityState {
  final List<CommunityPost> posts;
  final List<LeaderboardEntry> leaderboard;

  const CommunityLoaded({
    required this.posts,
    required this.leaderboard,
  });

  CommunityLoaded copyWith({
    List<CommunityPost>? posts,
    List<LeaderboardEntry>? leaderboard,
  }) {
    return CommunityLoaded(
      posts: posts ?? this.posts,
      leaderboard: leaderboard ?? this.leaderboard,
    );
  }

  @override
  List<Object?> get props => [posts, leaderboard];
}

class CommunityError extends CommunityState {
  final String message;
  const CommunityError(this.message);

  @override
  List<Object?> get props => [message];
}
