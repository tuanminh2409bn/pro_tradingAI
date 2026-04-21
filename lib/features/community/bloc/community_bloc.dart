import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'community_event.dart';
import 'community_state.dart';
import '../../../data/repositories/community_repository.dart';
import '../../../data/models/community_models.dart';

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
  }

  Future<void> _onLoadData(LoadCommunityData event, Emitter<CommunityState> emit) async {
    emit(CommunityLoading());
    try {
      _feedSubscription?.cancel();
      _feedSubscription = _communityRepository.getCommunityFeed().listen(
        (posts) => add(UpdateCommunityFeed(posts)),
        onError: (e) => print('CommunityBloc: Feed error: $e'),
      );

      _leaderboardSubscription?.cancel();
      _leaderboardSubscription = _communityRepository.getLeaderboard().listen(
        (leaderboard) => add(UpdateLeaderboard(leaderboard)),
        onError: (e) => print('CommunityBloc: Leaderboard error: $e'),
      );

      // Emit initial Loaded state immediately
      emit(const CommunityLoaded(posts: [], leaderboard: []));
    } catch (e) {
      emit(CommunityError(e.toString()));
    }
  }

  void _onUpdateFeed(UpdateCommunityFeed event, Emitter<CommunityState> emit) {
    if (state is CommunityLoaded) {
      emit((state as CommunityLoaded).copyWith(posts: event.posts));
    }
  }

  void _onUpdateLeaderboard(UpdateLeaderboard event, Emitter<CommunityState> emit) {
    if (state is CommunityLoaded) {
      emit((state as CommunityLoaded).copyWith(leaderboard: event.leaderboard));
    }
  }

  Future<void> _onCreatePost(CreatePost event, Emitter<CommunityState> emit) async {
    final newPost = CommunityPost(
      userName: 'Alex Rivera', 
      avatarUrl: '',
      timeAgo: 'Just now',
      content: event.content,
      tradeInfo: 'Market Analysis',
      profit: 0,
      isProfit: true,
      likes: 0,
      comments: 0,
    );
    await _communityRepository.createPost(newPost);
  }

  @override
  Future<void> close() {
    _feedSubscription?.cancel();
    _leaderboardSubscription?.cancel();
    return super.close();
  }
}
