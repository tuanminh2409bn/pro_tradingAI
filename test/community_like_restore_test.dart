import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/community_models.dart';
import 'package:protrading_ai/data/repositories/community_repository.dart';
import 'package:protrading_ai/features/community/bloc/community_bloc.dart';
import 'package:protrading_ai/features/community/bloc/community_event.dart';
import 'package:protrading_ai/features/community/bloc/community_state.dart';

const _post = CommunityPost(
  id: 'post123',
  userName: 'Alice',
  avatarUrl: '',
  timeAgo: 'Just now',
  content: 'Local note',
  tradeInfo: '',
  profit: 0,
  isProfit: false,
  likes: 1,
  comments: 0,
);

class _Repository extends Fake implements CommunityRepository {
  final feed = StreamController<List<CommunityPost>>.broadcast();
  final restored = Completer<Set<String>>();
  final requested = <Set<String>>[];
  bool fail = false;
  @override
  Stream<List<CommunityPost>> getCommunityFeed() => feed.stream;
  @override
  Stream<List<LeaderboardEntry>> getLeaderboard() => const Stream.empty();
  @override
  Future<Set<String>> getLikedPostIds(Iterable<String> ids) {
    requested.add(ids.toSet());
    if (fail) return Future.error(StateError('unavailable'));
    return restored.future;
  }
}

void main() {
  Future<CommunityBloc> start(_Repository repository) async {
    final bloc = CommunityBloc(communityRepository: repository);
    addTearDown(() async {
      await bloc.close();
      await repository.feed.close();
    });
    bloc.add(const LoadCommunityData(sharedPostId: 'shared-outside-feed'));
    await bloc.stream.firstWhere((state) => state is CommunityLoaded);
    repository.feed.add(const [_post]);
    return bloc;
  }

  test(
    'Own like markers restore once per post, including shared post outside feed',
    () async {
      final repository = _Repository();
      final bloc = await start(repository);
      await bloc.stream.firstWhere(
        (state) =>
            state is CommunityLoaded && state.restoringLikePostIds.isNotEmpty,
      );
      repository.restored.complete({'post123', 'shared-outside-feed'});
      final loaded =
          await bloc.stream.firstWhere(
                (state) =>
                    state is CommunityLoaded && state.likedPostIds.length == 2,
              )
              as CommunityLoaded;
      expect(loaded.restoringLikePostIds, isEmpty);
      expect(repository.requested.single, {'post123', 'shared-outside-feed'});
      repository.feed.add(const [_post]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requested.length, 1);
    },
  );

  test(
    'Like status read failure can retry and cannot apply after reload',
    () async {
      final repository = _Repository()..fail = true;
      final bloc = await start(repository);
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.likeStatusUnavailable,
      );
      repository.fail = false;
      bloc.add(const RetryCommunityLikes());
      await bloc.stream.firstWhere(
        (state) =>
            state is CommunityLoaded && state.restoringLikePostIds.isNotEmpty,
      );
      bloc.add(const LoadCommunityData());
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.posts.isEmpty,
      );
      repository.restored.complete({'post123'});
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as CommunityLoaded).likedPostIds, isEmpty);
      expect(repository.requested.length, 2);
    },
  );
}
