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
  final bool isPosting;
  final int postResultNonce;
  final bool postSucceeded;
  final Set<String> likedPostIds;
  final Set<String> likingPostIds;
  final int likeFailureNonce;

  const CommunityLoaded({
    required this.posts,
    required this.leaderboard,
    this.isPosting = false,
    this.postResultNonce = 0,
    this.postSucceeded = false,
    this.likedPostIds = const <String>{},
    this.likingPostIds = const <String>{},
    this.likeFailureNonce = 0,
  });

  CommunityLoaded copyWith({
    List<CommunityPost>? posts,
    List<LeaderboardEntry>? leaderboard,
    bool? isPosting,
    int? postResultNonce,
    bool? postSucceeded,
    Set<String>? likedPostIds,
    Set<String>? likingPostIds,
    int? likeFailureNonce,
  }) {
    return CommunityLoaded(
      posts: posts ?? this.posts,
      leaderboard: leaderboard ?? this.leaderboard,
      isPosting: isPosting ?? this.isPosting,
      postResultNonce: postResultNonce ?? this.postResultNonce,
      postSucceeded: postSucceeded ?? this.postSucceeded,
      likedPostIds: likedPostIds ?? this.likedPostIds,
      likingPostIds: likingPostIds ?? this.likingPostIds,
      likeFailureNonce: likeFailureNonce ?? this.likeFailureNonce,
    );
  }

  @override
  List<Object?> get props => [
    posts,
    leaderboard,
    isPosting,
    postResultNonce,
    postSucceeded,
    likedPostIds,
    likingPostIds,
    likeFailureNonce,
  ];
}

class CommunityError extends CommunityState {
  final String message;
  const CommunityError(this.message);

  @override
  List<Object?> get props => [message];
}
