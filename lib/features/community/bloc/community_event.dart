import 'package:equatable/equatable.dart';
import '../../../data/models/community_models.dart';

abstract class CommunityEvent extends Equatable {
  const CommunityEvent();

  @override
  List<Object?> get props => [];
}

class LoadCommunityData extends CommunityEvent {}

class UpdateCommunityFeed extends CommunityEvent {
  final List<CommunityPost> posts;
  const UpdateCommunityFeed(this.posts);

  @override
  List<Object?> get props => [posts];
}

class UpdateLeaderboard extends CommunityEvent {
  final List<LeaderboardEntry> leaderboard;
  const UpdateLeaderboard(this.leaderboard);

  @override
  List<Object?> get props => [leaderboard];
}

class CreatePost extends CommunityEvent {
  final String content;
  const CreatePost(this.content);

  @override
  List<Object?> get props => [content];
}
