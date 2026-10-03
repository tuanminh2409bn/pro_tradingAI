import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/news_models.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/news_repository.dart';
import 'package:protrading_ai/features/news_feed/bloc/news_bloc.dart';
import 'package:protrading_ai/features/news_feed/bloc/news_event.dart';
import 'package:protrading_ai/features/news_feed/bloc/news_state.dart';

class _Repository extends Fake implements NewsRepository {
  final replies = <Completer<String>>[];
  final histories = <String, Completer<List<ChatMessage>>>{};
  final saved = <({String userId, ChatMessage message})>[];
  final cleared = <String>[];
  Completer<void>? pendingSave;
  bool clearFails = false;

  @override
  Stream<List<NewsArticle>> getNewsFeed() => const Stream.empty();

  @override
  Stream<SentimentPulse> getSentimentPulse() => const Stream.empty();

  @override
  Future<String> getAISentimentAnalysis(String query) {
    final reply = Completer<String>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<List<ChatMessage>> loadChatHistory({
    required String userId,
    required String chatType,
    int limit = 50,
  }) => histories[userId]?.future ?? Future.value([]);

  @override
  Future<void> saveChatMessage({
    required String userId,
    required String chatType,
    required ChatMessage message,
  }) async {
    saved.add((userId: userId, message: message));
    await pendingSave?.future;
  }

  @override
  Future<void> clearChatHistory({
    required String userId,
    required String chatType,
  }) async {
    if (clearFails) throw StateError('Storage unavailable');
    cleared.add(userId);
  }
}

const _article = NewsArticle(
  title: 'New official release',
  source: 'Federal Reserve Board',
  timeAgo: 'Just now',
  sentimentScore: null,
  type: 'OFFICIAL',
);

Future<NewsLoaded> _load(NewsBloc bloc, String userId) async {
  final loaded = bloc.stream.firstWhere(
    (state) => state is NewsLoaded && !state.isLoadingHistory,
  );
  bloc.add(LoadNewsData(userId: userId));
  return await loaded as NewsLoaded;
}

Future<void> _ask(NewsBloc bloc) async {
  final thinking = bloc.stream.firstWhere(
    (state) => state is NewsLoaded && state.isAiThinking,
  );
  bloc.add(const AskAIAnalyst('Explain the official release'));
  await thinking;
}

Future<void> _dispose(NewsBloc bloc, _Repository repository) async {
  for (final reply in repository.replies) {
    if (!reply.isCompleted) reply.complete('Test cleanup');
  }
  for (final history in repository.histories.values) {
    if (!history.isCompleted) history.complete([]);
  }
  if (repository.pendingSave case final pending? when !pending.isCompleted) {
    pending.complete();
  }
  await bloc.close();
}

void main() {
  test(
    'duplicate requests are ignored and live feed survives the reply',
    () async {
      final repository = _Repository();
      final bloc = NewsBloc(newsRepository: repository);
      addTearDown(() => _dispose(bloc, repository));
      await _load(bloc, 'alice');
      await _ask(bloc);
      bloc.add(const UpdateNewsFeed([_article]));
      bloc.add(const AskAIAnalyst('Repeated click'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.replies, hasLength(1));
      final completed = bloc.stream.firstWhere(
        (state) => state is NewsLoaded && !state.isAiThinking,
      );
      repository.replies.single.complete('Source-based reply');
      final result = await completed as NewsLoaded;
      expect(result.articles, [_article]);
      expect(result.chatMessages.last['text'], 'Source-based reply');
      expect(
        result.chatMessages.where((message) => message['isAi'] == false),
        hasLength(1),
      );
    },
  );

  test('AI failure preserves live updates and ends the spinner', () async {
    final repository = _Repository();
    final bloc = NewsBloc(newsRepository: repository);
    addTearDown(() => _dispose(bloc, repository));
    await _load(bloc, 'alice');
    await _ask(bloc);
    bloc.add(const UpdateNewsFeed([_article]));
    await Future<void>.delayed(Duration.zero);
    final completed = bloc.stream.firstWhere(
      (state) => state is NewsLoaded && !state.isAiThinking,
    );
    repository.replies.single.completeError(StateError('Unavailable'));
    final result = await completed as NewsLoaded;
    expect(result.articles, [_article]);
    expect(result.chatMessages.last['text'], '__AI_UNAVAILABLE__');
  });

  test(
    'a late reply cannot enter or persist in another user session',
    () async {
      final repository = _Repository();
      final bloc = NewsBloc(newsRepository: repository);
      addTearDown(() => _dispose(bloc, repository));
      await _load(bloc, 'alice');
      await _ask(bloc);
      await _load(bloc, 'bob');
      repository.replies.single.complete('Private reply for Alice');
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as NewsLoaded).chatMessages, [
        {'text': '__WELCOME__', 'isAi': true},
      ]);
      expect(repository.saved.any((entry) => !entry.message.isUser), isFalse);
      expect(repository.saved.map((entry) => entry.userId), ['alice']);
    },
  );

  test(
    'a late history load cannot reveal the previous user messages',
    () async {
      final repository = _Repository();
      repository.histories['alice'] = Completer<List<ChatMessage>>();
      final bloc = NewsBloc(newsRepository: repository);
      addTearDown(() => _dispose(bloc, repository));
      final loading = bloc.stream.firstWhere((state) => state is NewsLoaded);
      bloc.add(const LoadNewsData(userId: 'alice'));
      await loading;
      await Future<void>.delayed(Duration.zero);
      await _load(bloc, 'bob');
      repository.histories['alice']!.complete([
        ChatMessage(
          id: 'private',
          content: 'Alice only',
          isUser: true,
          timestamp: DateTime.utc(2026, 10, 3),
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as NewsLoaded).chatMessages, [
        {'text': '__WELCOME__', 'isAi': true},
      ]);
    },
  );

  test(
    'loading history and pending AI prevent destructive chat races',
    () async {
      final repository = _Repository();
      repository.histories['alice'] = Completer<List<ChatMessage>>();
      final bloc = NewsBloc(newsRepository: repository);
      addTearDown(() => _dispose(bloc, repository));
      final loading = bloc.stream.firstWhere((state) => state is NewsLoaded);
      bloc.add(const LoadNewsData(userId: 'alice'));
      await loading;
      bloc.add(const AskAIAnalyst('Before history is ready'));
      bloc.add(const ClearNewsChatHistory());
      await Future<void>.delayed(Duration.zero);
      expect(repository.replies, isEmpty);
      expect(repository.cleared, isEmpty);
      final ready = bloc.stream.firstWhere(
        (state) => state is NewsLoaded && !state.isLoadingHistory,
      );
      repository.histories['alice']!.complete([]);
      await ready;
      await _ask(bloc);
      bloc.add(const ClearNewsChatHistory());
      await Future<void>.delayed(Duration.zero);
      expect(repository.cleared, isEmpty);
      final completed = bloc.stream.firstWhere(
        (state) => state is NewsLoaded && !state.isAiThinking,
      );
      repository.replies.single.complete('Reply');
      await completed;
      final cleared = bloc.stream.firstWhere(
        (state) =>
            state is NewsLoaded &&
            !state.isLoadingHistory &&
            state.chatMessages.length == 1,
      );
      bloc.add(const ClearNewsChatHistory());
      await cleared;
      expect(repository.cleared, ['alice']);
    },
  );

  test('clear waits for accepted saves before deleting history', () async {
    final repository = _Repository()..pendingSave = Completer<void>();
    final bloc = NewsBloc(newsRepository: repository);
    addTearDown(() => _dispose(bloc, repository));
    await _load(bloc, 'alice');
    await _ask(bloc);
    final completed = bloc.stream.firstWhere(
      (state) => state is NewsLoaded && !state.isAiThinking,
    );
    repository.replies.single.complete('Reply');
    await completed;
    final clearing = bloc.stream.firstWhere(
      (state) => state is NewsLoaded && state.isLoadingHistory,
    );
    bloc.add(const ClearNewsChatHistory());
    await clearing;
    expect(repository.cleared, isEmpty);
    final cleared = bloc.stream.firstWhere(
      (state) => state is NewsLoaded && !state.isLoadingHistory,
    );
    repository.pendingSave!.complete();
    await cleared;
    expect(repository.saved.map((entry) => entry.message.isUser), [
      true,
      false,
    ]);
    expect(repository.cleared, ['alice']);
  });

  test(
    'clear failure preserves messages and reports a retryable error',
    () async {
      final repository = _Repository()..clearFails = true;
      final bloc = NewsBloc(newsRepository: repository);
      addTearDown(() => _dispose(bloc, repository));
      final initial = await _load(bloc, 'alice');
      final failed = bloc.stream.firstWhere(
        (state) => state is NewsLoaded && state.chatErrorKey.isNotEmpty,
      );
      bloc.add(const ClearNewsChatHistory());
      final result = await failed as NewsLoaded;
      expect(result.isLoadingHistory, isFalse);
      expect(result.chatMessages, initial.chatMessages);
      expect(result.chatErrorKey, 'news_ai_clear_failed');
    },
  );

  test('closing a page discards a pending reply', () async {
    final repository = _Repository();
    final bloc = NewsBloc(newsRepository: repository);
    await _load(bloc, 'alice');
    await _ask(bloc);
    final closing = bloc.close();
    repository.replies.single.complete('Reply after navigation');
    await closing;
    expect(repository.saved.any((entry) => !entry.message.isUser), isFalse);
  });
}
