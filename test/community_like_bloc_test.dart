import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/community_models.dart';
import 'package:protrading_ai/data/repositories/community_repository.dart';
import 'package:protrading_ai/features/community/bloc/community_bloc.dart';
import 'package:protrading_ai/features/community/bloc/community_event.dart';
import 'package:protrading_ai/features/community/bloc/community_state.dart';

class _CommunityRepository extends Fake implements CommunityRepository {
  int likeCalls = 0;
  bool failLike = false;

  @override
  Stream<List<CommunityPost>> getCommunityFeed() => const Stream.empty();

  @override
  Stream<List<LeaderboardEntry>> getLeaderboard() => const Stream.empty();

  @override
  Future<void> likePost(String postId) async {
    likeCalls++;
    if (failLike) throw StateError('unavailable');
  }
}

void main() {
  test('repeated like event calls repository only once', () async {
    final repository = _CommunityRepository();
    final bloc = CommunityBloc(communityRepository: repository);
    addTearDown(bloc.close);
    bloc.add(LoadCommunityData());
    await bloc.stream.firstWhere((state) => state is CommunityLoaded);

    bloc.add(const LikeCommunityPost('post123'));
    await bloc.stream.firstWhere(
      (state) =>
          state is CommunityLoaded && state.likedPostIds.contains('post123'),
    );
    bloc.add(const LikeCommunityPost('post123'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.likeCalls, 1);
  });

  test('failed like clears busy state and reports failure', () async {
    final repository = _CommunityRepository()..failLike = true;
    final bloc = CommunityBloc(communityRepository: repository);
    addTearDown(bloc.close);
    bloc.add(LoadCommunityData());
    await bloc.stream.firstWhere((state) => state is CommunityLoaded);

    bloc.add(const LikeCommunityPost('post123'));
    final result =
        await bloc.stream.firstWhere(
              (state) =>
                  state is CommunityLoaded && state.likeFailureNonce == 1,
            )
            as CommunityLoaded;
    expect(result.likingPostIds, isEmpty);
    expect(result.likedPostIds, isEmpty);
    expect(repository.likeCalls, 1);
  });
}
