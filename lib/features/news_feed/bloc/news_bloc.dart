import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'news_event.dart';
import 'news_state.dart';
import '../../../data/repositories/news_repository.dart';
import '../../../data/models/news_models.dart';
import '../../../data/models/trading_models.dart';

class NewsBloc extends Bloc<NewsEvent, NewsState> {
  final NewsRepository _newsRepository;
  StreamSubscription? _newsSubscription;
  StreamSubscription? _pulseSubscription;
  String? _userId;
  int _chatGeneration = 0;
  Future<void> _chatWriteTail = Future.value();

  NewsBloc({required NewsRepository newsRepository})
    : _newsRepository = newsRepository,
      super(NewsInitial()) {
    on<LoadNewsData>(_onLoadNewsData);
    on<UpdateNewsFeed>(_onUpdateNewsFeed);
    on<UpdateSentimentPulse>(_onUpdateSentimentPulse);
    on<AskAIAnalyst>(_onAskAIAnalyst);
    on<LoadNewsChatHistory>(_onLoadNewsChatHistory);
    on<NewsChatHistoryLoaded>(_onNewsChatHistoryLoaded);
    on<ClearNewsChatHistory>(_onClearNewsChatHistory);
    on<NewsStreamFailed>(_onStreamFailed);
  }

  Future<void> _onLoadNewsData(
    LoadNewsData event,
    Emitter<NewsState> emit,
  ) async {
    _chatGeneration++;
    emit(NewsLoading());
    _userId = event.userId;
    try {
      _newsSubscription?.cancel();
      _pulseSubscription?.cancel();

      _newsSubscription = _newsRepository.getNewsFeed().listen(
        (articles) => add(UpdateNewsFeed(articles)),
        onError: (_) => add(const NewsStreamFailed()),
      );

      _pulseSubscription = _newsRepository.getSentimentPulse().listen(
        (pulse) => add(UpdateSentimentPulse(pulse)),
        onError: (_) => add(const NewsStreamFailed()),
      );

      // Emit initial Loaded state with welcome message while streams & history load
      emit(
        const NewsLoaded(
          articles: [],
          pulse: SentimentPulse.unavailable(),
          chatMessages: [],
          isLoadingHistory: true,
        ),
      );

      // Load chat history from Firestore
      add(const LoadNewsChatHistory());
    } catch (_) {
      emit(const NewsError('common_data_unavailable'));
    }
  }

  void _onUpdateNewsFeed(UpdateNewsFeed event, Emitter<NewsState> emit) {
    if (state is NewsLoaded) {
      emit((state as NewsLoaded).copyWith(articles: event.articles));
    }
  }

  void _onUpdateSentimentPulse(
    UpdateSentimentPulse event,
    Emitter<NewsState> emit,
  ) {
    if (state is NewsLoaded) {
      emit((state as NewsLoaded).copyWith(pulse: event.pulse));
    }
  }

  Future<void> _onAskAIAnalyst(
    AskAIAnalyst event,
    Emitter<NewsState> emit,
  ) async {
    if (state is! NewsLoaded) return;
    final current = state as NewsLoaded;
    final userId = _userId;
    final generation = _chatGeneration;
    final query = event.query.trim();
    if (current.isAiThinking ||
        current.isLoadingHistory ||
        query.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }

    emit(
      current.copyWith(
        chatMessages: [
          ...current.chatMessages,
          {'text': query, 'isAi': false},
        ],
        isAiThinking: true,
        chatErrorKey: '',
      ),
    );
    _queueChatMessage(
      userId: userId,
      message: ChatMessage(
        id: 'user_${DateTime.now().microsecondsSinceEpoch}',
        content: query,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );

    String response;
    var succeeded = false;
    try {
      response = await _newsRepository.getAISentimentAnalysis(query);
      succeeded = true;
    } catch (_) {
      response = '__AI_UNAVAILABLE__';
    }
    if (!_isCurrentChat(generation, userId, emit)) return;
    final latest = state as NewsLoaded;
    emit(
      latest.copyWith(
        chatMessages: [
          ...latest.chatMessages,
          {'text': response, 'isAi': true},
        ],
        isAiThinking: false,
      ),
    );
    if (succeeded) {
      _queueChatMessage(
        userId: userId,
        message: ChatMessage(
          id: 'ai_${DateTime.now().microsecondsSinceEpoch}',
          content: response,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  bool _isCurrentChat(
    int generation,
    String? userId,
    Emitter<NewsState> emit,
  ) =>
      !isClosed &&
      !emit.isDone &&
      generation == _chatGeneration &&
      userId == _userId &&
      state is NewsLoaded;

  void _queueChatMessage({
    required String userId,
    required ChatMessage message,
  }) {
    _chatWriteTail = _chatWriteTail.then(
      (_) => _saveChatMessageBestEffort(userId: userId, message: message),
    );
  }

  Future<void> _saveChatMessageBestEffort({
    required String userId,
    required ChatMessage message,
  }) async {
    try {
      await _newsRepository.saveChatMessage(
        userId: userId,
        chatType: 'news_feed',
        message: message,
      );
    } catch (_) {
      // The current response remains useful even if history persistence fails.
    }
  }

  void _onStreamFailed(NewsStreamFailed event, Emitter<NewsState> emit) {
    _chatGeneration++;
    emit(const NewsError('common_data_unavailable'));
  }

  // ─── Chat History Handlers ───

  Future<void> _onLoadNewsChatHistory(
    LoadNewsChatHistory event,
    Emitter<NewsState> emit,
  ) async {
    final userId = _userId;
    final generation = _chatGeneration;
    if (state is NewsLoaded && (state as NewsLoaded).isAiThinking) return;
    if (state is NewsLoaded && userId != null && userId.isNotEmpty) {
      emit((state as NewsLoaded).copyWith(isLoadingHistory: true));
      List<ChatMessage> chatMessages;
      try {
        chatMessages = await _newsRepository.loadChatHistory(
          userId: userId,
          chatType: 'news_feed',
        );
      } catch (_) {
        chatMessages = const [];
      }

      if (_isCurrentChat(generation, userId, emit)) {
        // Convert ChatMessage list back to Map format for UI compatibility
        final mappedMessages = <Map<String, dynamic>>[];
        // Add welcome message if no history
        if (chatMessages.isEmpty) {
          mappedMessages.add({'text': '__WELCOME__', 'isAi': true});
        } else {
          for (final msg in chatMessages) {
            mappedMessages.add({'text': msg.content, 'isAi': !msg.isUser});
          }
        }
        emit(
          (state as NewsLoaded).copyWith(
            chatMessages: mappedMessages,
            isLoadingHistory: false,
          ),
        );
      }
    } else if (state is NewsLoaded) {
      // No userId — show welcome message only
      emit(
        (state as NewsLoaded).copyWith(
          chatMessages: [
            {'text': '__WELCOME__', 'isAi': true},
          ],
          isLoadingHistory: false,
        ),
      );
    }
  }

  void _onNewsChatHistoryLoaded(
    NewsChatHistoryLoaded event,
    Emitter<NewsState> emit,
  ) {
    if (state is NewsLoaded) {
      final mapped = event.messages
          .map((m) => <String, dynamic>{'text': m.content, 'isAi': !m.isUser})
          .toList();
      emit((state as NewsLoaded).copyWith(chatMessages: mapped));
    }
  }

  Future<void> _onClearNewsChatHistory(
    ClearNewsChatHistory event,
    Emitter<NewsState> emit,
  ) async {
    if (state is NewsLoaded) {
      final current = state as NewsLoaded;
      if (current.isAiThinking || current.isLoadingHistory) return;
      final userId = _userId;
      final generation = ++_chatGeneration;
      emit(current.copyWith(isLoadingHistory: true, chatErrorKey: ''));
      final welcomeMsg = [
        {'text': '__WELCOME__', 'isAi': true},
      ];
      if (userId != null && userId.isNotEmpty) {
        try {
          // Drain accepted writes before deleting, so a late save cannot revive history.
          await _chatWriteTail.timeout(const Duration(seconds: 10));
          if (!_isCurrentChat(generation, userId, emit)) return;
          await _newsRepository.clearChatHistory(
            userId: userId,
            chatType: 'news_feed',
          );
        } catch (_) {
          if (_isCurrentChat(generation, userId, emit)) {
            emit(
              (state as NewsLoaded).copyWith(
                isLoadingHistory: false,
                chatErrorKey: 'news_ai_clear_failed',
              ),
            );
          }
          return;
        }
      }
      if (_isCurrentChat(generation, userId, emit)) {
        emit(
          (state as NewsLoaded).copyWith(
            chatMessages: welcomeMsg,
            isLoadingHistory: false,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _chatGeneration++;
    _newsSubscription?.cancel();
    _pulseSubscription?.cancel();
    return super.close();
  }
}
