import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/community_models.dart';
import 'package:protrading_ai/data/repositories/community_repository.dart';
import 'package:protrading_ai/features/community/bloc/community_bloc.dart';
import 'package:protrading_ai/features/community/bloc/community_event.dart';
import 'package:protrading_ai/features/community/bloc/community_state.dart';

class _Repository extends Fake implements CommunityRepository {
  final feed = StreamController<List<CommunityPost>>.broadcast();
  final comments = StreamController<List<CommunityComment>>.broadcast();
  final pendingComment = Completer<void>();
  final pendingPost = Completer<void>();
  int commentCalls = 0;
  @override
  Stream<List<CommunityPost>> getCommunityFeed() => feed.stream;
  @override
  Stream<List<LeaderboardEntry>> getLeaderboard() => const Stream.empty();
  @override
  Stream<List<CommunityComment>> getComments(String postId) => comments.stream;
  @override
  Future<void> createComment(String postId, String content) {
    commentCalls++;
    return pendingComment.future;
  }

  @override
  Future<void> createPost(String content) => pendingPost.future;
}

void main() {
  Future<CommunityBloc> start(_Repository repository) async {
    final bloc = CommunityBloc(communityRepository: repository);
    addTearDown(() async {
      await bloc.close();
      await repository.feed.close();
      await repository.comments.close();
    });
    bloc.add(LoadCommunityData());
    await bloc.stream.firstWhere((state) => state is CommunityLoaded);
    bloc.add(const OpenCommunityComments('post123'));
    await bloc.stream.firstWhere(
      (state) => state is CommunityLoaded && state.commentsPostId == 'post123',
    );
    return bloc;
  }

  test(
    'Concurrent send creates one comment and preserves incoming feed/comments',
    () async {
      final repository = _Repository();
      final bloc = await start(repository);
      bloc.add(const CreateCommunityComment('post123', 'Reply'));
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.isCommenting,
      );
      bloc.add(const CreateCommunityComment('post123', 'Reply'));
      repository.comments.add(const [
        CommunityComment(
          id: 'one',
          ownerId: 'alice',
          userName: 'Alice',
          content: 'Reply',
          timeAgo: 'Just now',
        ),
      ]);
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.comments.length == 1,
      );
      repository.pendingComment.complete();
      final result =
          await bloc.stream.firstWhere(
                (state) =>
                    state is CommunityLoaded && state.commentResultNonce == 1,
              )
              as CommunityLoaded;
      expect(repository.commentCalls, 1);
      expect(result.isCommenting, isFalse);
      expect(result.commentSucceeded, isTrue);
      expect(result.comments.single.content, 'Reply');
    },
  );

  test(
    'Closing/reopening comments ignores late write and stale stream results',
    () async {
      final repository = _Repository();
      final bloc = await start(repository);
      bloc.add(const CreateCommunityComment('post123', 'Reply'));
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.isCommenting,
      );
      bloc.add(const CloseCommunityComments());
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.commentsPostId == null,
      );
      bloc.add(const OpenCommunityComments('post456'));
      await bloc.stream.firstWhere(
        (state) =>
            state is CommunityLoaded && state.commentsPostId == 'post456',
      );
      repository.pendingComment.complete();
      await Future<void>.delayed(Duration.zero);
      final result = bloc.state as CommunityLoaded;
      expect(result.commentsPostId, 'post456');
      expect(result.commentResultNonce, 0);
      expect(result.isCommenting, isFalse);
    },
  );

  test(
    'Failed stream exposes retry; failed send clears pending without claiming success',
    () async {
      final repository = _Repository();
      final bloc = await start(repository);
      repository.comments.addError(StateError('unavailable'));
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.commentsError,
      );
      bloc.add(const CreateCommunityComment('post123', 'Reply'));
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.isCommenting,
      );
      repository.pendingComment.completeError(StateError('unavailable'));
      final result =
          await bloc.stream.firstWhere(
                (state) =>
                    state is CommunityLoaded && state.commentResultNonce == 1,
              )
              as CommunityLoaded;
      expect(result.commentSucceeded, isFalse);
      expect(result.isCommenting, isFalse);
    },
  );

  test(
    'Late post completion cannot replace a feed error with stale loaded state',
    () async {
      final repository = _Repository();
      final bloc = await start(repository);
      bloc.add(const CreatePost('Market note'));
      await bloc.stream.firstWhere(
        (state) => state is CommunityLoaded && state.isPosting,
      );
      repository.feed.addError(StateError('unavailable'));
      await bloc.stream.firstWhere((state) => state is CommunityError);
      repository.pendingPost.complete();
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<CommunityError>());
    },
  );
}
