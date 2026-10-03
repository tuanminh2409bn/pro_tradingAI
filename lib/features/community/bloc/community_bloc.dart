import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'community_event.dart';
import 'community_state.dart';
import '../../../data/repositories/community_repository.dart';

class CommunityBloc extends Bloc<CommunityEvent, CommunityState> {
  final CommunityRepository _communityRepository;
  StreamSubscription? _feedSubscription;
  StreamSubscription? _leaderboardSubscription;
  StreamSubscription? _commentsSubscription;
  int _loadGeneration = 0;
  int _commentsGeneration = 0;

  CommunityBloc({required CommunityRepository communityRepository})
    : _communityRepository = communityRepository,
      super(CommunityInitial()) {
    on<LoadCommunityData>(_onLoadData);
    on<UpdateCommunityFeed>(_onUpdateFeed);
    on<UpdateLeaderboard>(_onUpdateLeaderboard);
    on<CreatePost>(_onCreatePost);
    on<LikeCommunityPost>(_onLikePost);
    on<CommunityStreamFailed>(_onStreamFailed);
    on<OpenCommunityComments>(_onOpenComments);
    on<CloseCommunityComments>(_onCloseComments);
    on<UpdateCommunityComments>(_onUpdateComments);
    on<CreateCommunityComment>(_onCreateComment);
  }

  Future<void> _onLoadData(
    LoadCommunityData event,
    Emitter<CommunityState> emit,
  ) async {
    final generation = ++_loadGeneration;
    ++_commentsGeneration;
    emit(CommunityLoading());
    try {
      await _feedSubscription?.cancel();
      await _leaderboardSubscription?.cancel();
      await _commentsSubscription?.cancel();
      if (emit.isDone || generation != _loadGeneration) return;
      _feedSubscription = _communityRepository.getCommunityFeed().listen(
        (posts) {
          if (!isClosed && generation == _loadGeneration) {
            add(UpdateCommunityFeed(posts, generation: generation));
          }
        },
        onError: (_) {
          if (!isClosed && generation == _loadGeneration) {
            add(CommunityStreamFailed(generation: generation));
          }
        },
      );

      _leaderboardSubscription = _communityRepository.getLeaderboard().listen(
        (leaderboard) {
          if (!isClosed && generation == _loadGeneration) {
            add(UpdateLeaderboard(leaderboard, generation: generation));
          }
        },
        onError: (_) {
          if (!isClosed && generation == _loadGeneration) {
            add(CommunityStreamFailed(generation: generation));
          }
        },
      );

      // Emit initial Loaded state immediately
      emit(const CommunityLoaded(posts: [], leaderboard: []));
    } catch (_) {
      if (emit.isDone || generation != _loadGeneration) return;
      emit(const CommunityError('common_data_unavailable'));
    }
  }

  void _onStreamFailed(
    CommunityStreamFailed event,
    Emitter<CommunityState> emit,
  ) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    emit(const CommunityError('common_data_unavailable'));
  }

  void _onUpdateFeed(UpdateCommunityFeed event, Emitter<CommunityState> emit) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    if (state is CommunityLoaded) {
      emit((state as CommunityLoaded).copyWith(posts: event.posts));
    }
  }

  void _onUpdateLeaderboard(
    UpdateLeaderboard event,
    Emitter<CommunityState> emit,
  ) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    if (state is CommunityLoaded) {
      emit((state as CommunityLoaded).copyWith(leaderboard: event.leaderboard));
    }
  }

  Future<void> _onCreatePost(
    CreatePost event,
    Emitter<CommunityState> emit,
  ) async {
    final current = state;
    if (current is! CommunityLoaded || current.isPosting) return;
    final generation = _loadGeneration;
    emit(current.copyWith(isPosting: true));
    try {
      await _communityRepository.createPost(event.content);
      final latest = state;
      if (emit.isDone ||
          generation != _loadGeneration ||
          latest is! CommunityLoaded) {
        return;
      }
      emit(
        latest.copyWith(
          isPosting: false,
          postResultNonce: latest.postResultNonce + 1,
          postSucceeded: true,
        ),
      );
    } catch (_) {
      final latest = state;
      if (emit.isDone ||
          generation != _loadGeneration ||
          latest is! CommunityLoaded) {
        return;
      }
      emit(
        latest.copyWith(
          isPosting: false,
          postResultNonce: latest.postResultNonce + 1,
          postSucceeded: false,
        ),
      );
    }
  }

  Future<void> _onLikePost(
    LikeCommunityPost event,
    Emitter<CommunityState> emit,
  ) async {
    final current = state;
    if (current is! CommunityLoaded ||
        current.likedPostIds.contains(event.postId) ||
        current.likingPostIds.contains(event.postId)) {
      return;
    }
    final generation = _loadGeneration;
    emit(
      current.copyWith(likingPostIds: {...current.likingPostIds, event.postId}),
    );
    try {
      await _communityRepository.likePost(event.postId);
      final latest = state;
      if (emit.isDone ||
          generation != _loadGeneration ||
          latest is! CommunityLoaded) {
        return;
      }
      emit(
        latest.copyWith(
          likingPostIds: {...latest.likingPostIds}..remove(event.postId),
          likedPostIds: {...latest.likedPostIds, event.postId},
        ),
      );
    } catch (_) {
      final latest = state;
      if (emit.isDone ||
          generation != _loadGeneration ||
          latest is! CommunityLoaded) {
        return;
      }
      emit(
        latest.copyWith(
          likingPostIds: {...latest.likingPostIds}..remove(event.postId),
          likeFailureNonce: latest.likeFailureNonce + 1,
        ),
      );
    }
  }

  Future<void> _onOpenComments(
    OpenCommunityComments event,
    Emitter<CommunityState> emit,
  ) async {
    final generation = ++_commentsGeneration;
    await _commentsSubscription?.cancel();
    final current = state;
    if (emit.isDone ||
        generation != _commentsGeneration ||
        current is! CommunityLoaded) {
      return;
    }
    emit(
      current.copyWith(
        commentsPostId: event.postId,
        comments: const [],
        commentsLoading: true,
        commentsError: false,
        isCommenting: false,
      ),
    );
    try {
      _commentsSubscription = _communityRepository
          .getComments(event.postId)
          .listen(
            (comments) {
              if (!isClosed && generation == _commentsGeneration) {
                add(
                  UpdateCommunityComments(event.postId, generation, comments),
                );
              }
            },
            onError: (_) {
              if (!isClosed && generation == _commentsGeneration) {
                add(
                  UpdateCommunityComments(
                    event.postId,
                    generation,
                    const [],
                    failed: true,
                  ),
                );
              }
            },
          );
    } catch (_) {
      if (!isClosed && generation == _commentsGeneration) {
        add(
          UpdateCommunityComments(
            event.postId,
            generation,
            const [],
            failed: true,
          ),
        );
      }
    }
  }

  Future<void> _onCloseComments(
    CloseCommunityComments event,
    Emitter<CommunityState> emit,
  ) async {
    final generation = ++_commentsGeneration;
    await _commentsSubscription?.cancel();
    final current = state;
    if (emit.isDone ||
        generation != _commentsGeneration ||
        current is! CommunityLoaded) {
      return;
    }
    emit(current.copyWith(clearComments: true));
  }

  void _onUpdateComments(
    UpdateCommunityComments event,
    Emitter<CommunityState> emit,
  ) {
    final current = state;
    if (current is! CommunityLoaded ||
        current.commentsPostId != event.postId ||
        event.generation != _commentsGeneration) {
      return;
    }
    emit(
      current.copyWith(
        comments: event.comments,
        commentsLoading: false,
        commentsError: event.failed,
      ),
    );
  }

  Future<void> _onCreateComment(
    CreateCommunityComment event,
    Emitter<CommunityState> emit,
  ) async {
    final current = state;
    if (current is! CommunityLoaded ||
        current.commentsPostId != event.postId ||
        current.isCommenting) {
      return;
    }
    final generation = _commentsGeneration;
    emit(current.copyWith(isCommenting: true));
    bool succeeded;
    try {
      await _communityRepository.createComment(event.postId, event.content);
      succeeded = true;
    } catch (_) {
      succeeded = false;
    }
    final latest = state;
    if (emit.isDone ||
        generation != _commentsGeneration ||
        latest is! CommunityLoaded ||
        latest.commentsPostId != event.postId) {
      return;
    }
    emit(
      latest.copyWith(
        isCommenting: false,
        commentSucceeded: succeeded,
        commentResultNonce: latest.commentResultNonce + 1,
      ),
    );
  }

  @override
  Future<void> close() async {
    ++_loadGeneration;
    ++_commentsGeneration;
    await _feedSubscription?.cancel();
    await _leaderboardSubscription?.cancel();
    await _commentsSubscription?.cancel();
    return super.close();
  }
}
