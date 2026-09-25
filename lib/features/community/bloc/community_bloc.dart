import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'community_event.dart';
import 'community_state.dart';
import '../../../data/repositories/community_repository.dart';

class CommunityBloc extends Bloc<CommunityEvent, CommunityState> {
  final CommunityRepository _communityRepository;
  StreamSubscription? _feedSubscription;
  StreamSubscription? _leaderboardSubscription;

  CommunityBloc({required CommunityRepository communityRepository})
    : _communityRepository = communityRepository,
      super(CommunityInitial()) {
    on<LoadCommunityData>(_onLoadData);
    on<UpdateCommunityFeed>(_onUpdateFeed);
    on<UpdateLeaderboard>(_onUpdateLeaderboard);
    on<CreatePost>(_onCreatePost);
    on<LikeCommunityPost>(_onLikePost);
    on<CommunityStreamFailed>(_onStreamFailed);
  }

  Future<void> _onLoadData(
    LoadCommunityData event,
    Emitter<CommunityState> emit,
  ) async {
    emit(CommunityLoading());
    try {
      _feedSubscription?.cancel();
      _feedSubscription = _communityRepository.getCommunityFeed().listen(
        (posts) => add(UpdateCommunityFeed(posts)),
        onError: (_) => add(const CommunityStreamFailed()),
      );

      _leaderboardSubscription?.cancel();
      _leaderboardSubscription = _communityRepository.getLeaderboard().listen(
        (leaderboard) => add(UpdateLeaderboard(leaderboard)),
        onError: (_) => add(const CommunityStreamFailed()),
      );

      // Emit initial Loaded state immediately
      emit(const CommunityLoaded(posts: [], leaderboard: []));
    } catch (_) {
      emit(const CommunityError('common_data_unavailable'));
    }
  }

  void _onStreamFailed(
    CommunityStreamFailed event,
    Emitter<CommunityState> emit,
  ) {
    emit(const CommunityError('common_data_unavailable'));
  }

  void _onUpdateFeed(UpdateCommunityFeed event, Emitter<CommunityState> emit) {
    if (state is CommunityLoaded) {
      emit((state as CommunityLoaded).copyWith(posts: event.posts));
    }
  }

  void _onUpdateLeaderboard(
    UpdateLeaderboard event,
    Emitter<CommunityState> emit,
  ) {
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
    emit(current.copyWith(isPosting: true));
    try {
      await _communityRepository.createPost(event.content);
      final latest = state is CommunityLoaded
          ? state as CommunityLoaded
          : current;
      emit(
        latest.copyWith(
          isPosting: false,
          postResultNonce: latest.postResultNonce + 1,
          postSucceeded: true,
        ),
      );
    } catch (_) {
      final latest = state is CommunityLoaded
          ? state as CommunityLoaded
          : current;
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
    emit(
      current.copyWith(likingPostIds: {...current.likingPostIds, event.postId}),
    );
    try {
      await _communityRepository.likePost(event.postId);
      final latest = state;
      if (latest is! CommunityLoaded) return;
      emit(
        latest.copyWith(
          likingPostIds: {...latest.likingPostIds}..remove(event.postId),
          likedPostIds: {...latest.likedPostIds, event.postId},
        ),
      );
    } catch (_) {
      final latest = state;
      if (latest is! CommunityLoaded) return;
      emit(
        latest.copyWith(
          likingPostIds: {...latest.likingPostIds}..remove(event.postId),
          likeFailureNonce: latest.likeFailureNonce + 1,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _feedSubscription?.cancel();
    _leaderboardSubscription?.cancel();
    return super.close();
  }
}
