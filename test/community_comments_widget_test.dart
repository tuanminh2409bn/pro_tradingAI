import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/community_models.dart';
import 'package:protrading_ai/data/repositories/community_repository.dart';
import 'package:protrading_ai/features/community/web/community_web_page.dart';

const _post = CommunityPost(
  id: 'post123',
  ownerId: 'alice',
  userName: 'QA Emulator',
  avatarUrl: '',
  timeAgo: 'Just now',
  content: 'Local market note',
  tradeInfo: '',
  profit: 0,
  isProfit: false,
  likes: 0,
  comments: 0,
);

class _Repository extends Fake implements CommunityRepository {
  final pending = Completer<void>();
  bool fail = false;
  int calls = 0;
  @override
  Stream<List<CommunityPost>> getCommunityFeed() => Stream.value(const []);
  @override
  Stream<List<LeaderboardEntry>> getLeaderboard() => Stream.value(const []);
  @override
  Stream<CommunityPost?> watchPost(String postId) => Stream.value(_post);
  @override
  Stream<List<CommunityComment>> getComments(String postId) =>
      Stream.value(const []);
  @override
  Future<void> createComment(String postId, String content) async {
    calls++;
    expect(postId, 'post123');
    expect(content, 'Public reply');
    if (fail) throw StateError('offline');
    await pending.future;
  }

  @override
  Future<Set<String>> getLikedPostIds(Iterable<String> postIds) async => {};
}

void main() {
  Future<void> show(WidgetTester tester, _Repository repository) async {
    await tester.pumpWidget(
      RepositoryProvider<CommunityRepository>.value(
        value: repository,
        child: BlocProvider(
          create: (_) => LocaleCubit(),
          child: const MaterialApp(
            home: CommunityWebPage(sharedPostId: 'post123'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('community-comments-post123')),
    );
  }

  testWidgets(
    'Shared post outside feed opens comments; pending send disables and clears only on success',
    (tester) async {
      final repository = _Repository();
      await show(tester, repository);
      expect(find.text('Local market note'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('community-comments-post123')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No comments yet.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('community-comment-draft')),
        'Public reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('community-comment-send')));
      await tester.pump();
      expect(repository.calls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('community-comment-send')),
            )
            .onPressed,
        isNull,
      );
      repository.pending.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('community-comment-draft')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Comment published.'), findsOneWidget);
    },
  );

  testWidgets(
    'Failed comment retains draft; narrow layout exposes real copy link action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = _Repository()..fail = true;
      await show(tester, repository);
      await tester.tap(find.byKey(const ValueKey('community-share-post123')));
      await tester.pumpAndSettle();
      expect(
        copied,
        'https://protrading-ai-2026.web.app/?communityPost=post123',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('community-comments-post123')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('community-comment-draft')),
        'Public reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('community-comment-send')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('community-comment-draft')),
            )
            .controller!
            .text,
        'Public reply',
      );
      expect(
        find.text('Unable to publish. Your draft is kept; please retry.'),
        findsOneWidget,
      );
    },
  );
}
