import 'package:equatable/equatable.dart';
import '../../../data/models/community_models.dart';

abstract class CommunityEvent extends Equatable {
  const CommunityEvent();

  @override
  List<Object?> get props => [];
}

class LoadCommunityData extends CommunityEvent {
  final String? sharedPostId;
  const LoadCommunityData({this.sharedPostId});
  @override
  List<Object?> get props => [sharedPostId];
}

class RetryCommunityLikes extends CommunityEvent {
  const RetryCommunityLikes();
}

class UpdateCommunityFeed extends CommunityEvent {
  final List<CommunityPost> posts;
  final int? generation;
  const UpdateCommunityFeed(this.posts, {this.generation});

  @override
  List<Object?> get props => [posts];
}

class UpdateLeaderboard extends CommunityEvent {
  final List<LeaderboardEntry> leaderboard;
  final int? generation;
  const UpdateLeaderboard(this.leaderboard, {this.generation});

  @override
  List<Object?> get props => [leaderboard];
}

class CreatePost extends CommunityEvent {
  final String content;
  const CreatePost(this.content);

  @override
  List<Object?> get props => [content];
}

class LikeCommunityPost extends CommunityEvent {
  final String postId;
  const LikeCommunityPost(this.postId);

  @override
  List<Object?> get props => [postId];
}

class CommunityStreamFailed extends CommunityEvent {
  final int? generation;
  const CommunityStreamFailed({this.generation});
}

class OpenCommunityComments extends CommunityEvent {
  final String postId;
  const OpenCommunityComments(this.postId);
  @override
  List<Object?> get props => [postId];
}

class CloseCommunityComments extends CommunityEvent {
  const CloseCommunityComments();
}

class UpdateCommunityComments extends CommunityEvent {
  final String postId;
  final int generation;
  final List<CommunityComment> comments;
  final bool failed;
  const UpdateCommunityComments(
    this.postId,
    this.generation,
    this.comments, {
    this.failed = false,
  });
  @override
  List<Object?> get props => [postId, generation, comments, failed];
}

class CreateCommunityComment extends CommunityEvent {
  final String postId;
  final String content;
  const CreateCommunityComment(this.postId, this.content);
  @override
  List<Object?> get props => [postId, content];
}
