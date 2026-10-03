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
  final String? commentsPostId;
  final List<CommunityComment> comments;
  final bool commentsLoading;
  final bool commentsError;
  final bool isCommenting;
  final int commentResultNonce;
  final bool commentSucceeded;

  const CommunityLoaded({
    required this.posts,
    required this.leaderboard,
    this.isPosting = false,
    this.postResultNonce = 0,
    this.postSucceeded = false,
    this.likedPostIds = const <String>{},
    this.likingPostIds = const <String>{},
    this.likeFailureNonce = 0,
    this.commentsPostId,
    this.comments = const [],
    this.commentsLoading = false,
    this.commentsError = false,
    this.isCommenting = false,
    this.commentResultNonce = 0,
    this.commentSucceeded = false,
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
    String? commentsPostId,
    bool clearComments = false,
    List<CommunityComment>? comments,
    bool? commentsLoading,
    bool? commentsError,
    bool? isCommenting,
    int? commentResultNonce,
    bool? commentSucceeded,
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
      commentsPostId: clearComments
          ? null
          : commentsPostId ?? this.commentsPostId,
      comments: clearComments ? const [] : comments ?? this.comments,
      commentsLoading: clearComments
          ? false
          : commentsLoading ?? this.commentsLoading,
      commentsError: clearComments
          ? false
          : commentsError ?? this.commentsError,
      isCommenting: clearComments ? false : isCommenting ?? this.isCommenting,
      commentResultNonce: commentResultNonce ?? this.commentResultNonce,
      commentSucceeded: commentSucceeded ?? this.commentSucceeded,
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
    commentsPostId,
    comments,
    commentsLoading,
    commentsError,
    isCommenting,
    commentResultNonce,
    commentSucceeded,
  ];
}

class CommunityError extends CommunityState {
  final String message;
  const CommunityError(this.message);

  @override
  List<Object?> get props => [message];
}
