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
  }

  Future<void> _onLoadNewsData(LoadNewsData event, Emitter<NewsState> emit) async {
    emit(NewsLoading());
    _userId = event.userId;
    try {
      _newsSubscription?.cancel();
      _pulseSubscription?.cancel();

      _newsSubscription = _newsRepository.getNewsFeed().listen(
        (articles) => add(UpdateNewsFeed(articles)),
        onError: (e) => print('NewsBloc: NewsFeed error: $e'),
      );

      _pulseSubscription = _newsRepository.getSentimentPulse().listen(
        (pulse) => add(UpdateSentimentPulse(pulse)),
        onError: (e) => print('NewsBloc: SentimentPulse error: $e'),
      );

      // Emit initial Loaded state with welcome message while streams & history load
      emit(const NewsLoaded(
        articles: [],
        pulse: SentimentPulse(
          globalScore: 0,
          fearPercent: 0.0,
          neutralPercent: 0.0,
          greedPercent: 0.0,
          phase: 'LOADING',
        ),
        chatMessages: [],
        isLoadingHistory: true,
      ));

      // Load chat history from Firestore
      add(const LoadNewsChatHistory());
    } catch (e) {
      emit(NewsError(e.toString()));
    }
  }

  void _onUpdateNewsFeed(UpdateNewsFeed event, Emitter<NewsState> emit) {
    if (state is NewsLoaded) {
      emit((state as NewsLoaded).copyWith(articles: event.articles));
    }
  }

  void _onUpdateSentimentPulse(UpdateSentimentPulse event, Emitter<NewsState> emit) {
    if (state is NewsLoaded) {
      emit((state as NewsLoaded).copyWith(pulse: event.pulse));
    }
  }

  Future<void> _onAskAIAnalyst(AskAIAnalyst event, Emitter<NewsState> emit) async {
    if (state is NewsLoaded) {
      final currentState = state as NewsLoaded;

      // Build user message map
      final userMsgMap = {'text': event.query, 'isAi': false};
      final updatedMessages = List<Map<String, dynamic>>.from(currentState.chatMessages)
        ..add(userMsgMap);
      
      emit(currentState.copyWith(
        chatMessages: updatedMessages,
        isAiThinking: true,
      ));

      // Persist user message to Firestore
      if (_userId != null && _userId!.isNotEmpty) {
        final userChatMsg = ChatMessage(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          content: event.query,
          isUser: true,
          timestamp: DateTime.now(),
        );
        _newsRepository.saveChatMessage(
          userId: _userId!,
          chatType: 'news_feed',
          message: userChatMsg,
        );
      }

      try {
        final aiResponse = await _newsRepository.getAISentimentAnalysis(event.query);
        
        final aiMsgMap = {'text': aiResponse, 'isAi': true};
        final finalMessages = List<Map<String, dynamic>>.from(updatedMessages)
          ..add(aiMsgMap);
        
        emit(currentState.copyWith(
          chatMessages: finalMessages,
          isAiThinking: false,
        ));

        // Persist AI response to Firestore
        if (_userId != null && _userId!.isNotEmpty) {
          final aiChatMsg = ChatMessage(
            id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
            content: aiResponse,
            isUser: false,
            timestamp: DateTime.now(),
          );
          _newsRepository.saveChatMessage(
            userId: _userId!,
            chatType: 'news_feed',
            message: aiChatMsg,
          );
        }
      } catch (e) {
        final errorMsg = {'text': 'Error connecting to DeepSeek AI: ${e.toString()}', 'isAi': true};
        final errorMessages = List<Map<String, dynamic>>.from(updatedMessages)
          ..add(errorMsg);
        
        emit(currentState.copyWith(
          chatMessages: errorMessages,
          isAiThinking: false,
        ));
      }
    }
  }

  // ─── Chat History Handlers ───

  Future<void> _onLoadNewsChatHistory(LoadNewsChatHistory event, Emitter<NewsState> emit) async {
    if (state is NewsLoaded && _userId != null && _userId!.isNotEmpty) {
      emit((state as NewsLoaded).copyWith(isLoadingHistory: true));
      final chatMessages = await _newsRepository.loadChatHistory(
        userId: _userId!,
        chatType: 'news_feed',
      );

      if (state is NewsLoaded) {
        // Convert ChatMessage list back to Map format for UI compatibility
        final mappedMessages = <Map<String, dynamic>>[];
        // Add welcome message if no history
        if (chatMessages.isEmpty) {
          mappedMessages.add({
            'text': '__WELCOME__',
            'isAi': true,
          });
        } else {
          for (final msg in chatMessages) {
            mappedMessages.add({'text': msg.content, 'isAi': !msg.isUser});
          }
        }
        emit((state as NewsLoaded).copyWith(
          chatMessages: mappedMessages,
          isLoadingHistory: false,
        ));
      }
    } else if (state is NewsLoaded) {
      // No userId — show welcome message only
      emit((state as NewsLoaded).copyWith(
        chatMessages: [
          {'text': '__WELCOME__', 'isAi': true},
        ],
        isLoadingHistory: false,
      ));
    }
  }

  void _onNewsChatHistoryLoaded(NewsChatHistoryLoaded event, Emitter<NewsState> emit) {
    if (state is NewsLoaded) {
      final mapped = event.messages
          .map((m) => <String, dynamic>{'text': m.content, 'isAi': !m.isUser})
          .toList();
      emit((state as NewsLoaded).copyWith(chatMessages: mapped));
    }
  }

  Future<void> _onClearNewsChatHistory(ClearNewsChatHistory event, Emitter<NewsState> emit) async {
    if (state is NewsLoaded) {
      final welcomeMsg = [
        {'text': '__WELCOME__', 'isAi': true},
      ];
      emit((state as NewsLoaded).copyWith(chatMessages: welcomeMsg));
      if (_userId != null && _userId!.isNotEmpty) {
        await _newsRepository.clearChatHistory(
          userId: _userId!,
          chatType: 'news_feed',
        );
      }
    }
  }

  @override
  Future<void> close() {
    _newsSubscription?.cancel();
    _pulseSubscription?.cancel();
    return super.close();
  }
}
