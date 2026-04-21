import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'news_event.dart';
import 'news_state.dart';
import '../../../data/repositories/news_repository.dart';
import '../../../data/models/news_models.dart';

class NewsBloc extends Bloc<NewsEvent, NewsState> {
  final NewsRepository _newsRepository;
  StreamSubscription? _newsSubscription;
  StreamSubscription? _pulseSubscription;

  NewsBloc({required NewsRepository newsRepository})
      : _newsRepository = newsRepository,
        super(NewsInitial()) {
    on<LoadNewsData>(_onLoadNewsData);
    on<UpdateNewsFeed>(_onUpdateNewsFeed);
    on<UpdateSentimentPulse>(_onUpdateSentimentPulse);
    on<AskAIAnalyst>(_onAskAIAnalyst);
  }

  Future<void> _onLoadNewsData(LoadNewsData event, Emitter<NewsState> emit) async {
    emit(NewsLoading());
    try {
      _newsSubscription?.cancel();
      _pulseSubscription?.cancel();

      // For News, we can show public news even without a userId
      _newsSubscription = _newsRepository.getNewsFeed().listen(
        (articles) => add(UpdateNewsFeed(articles)),
        onError: (e) => print('NewsBloc: NewsFeed error: $e'),
      );

      _pulseSubscription = _newsRepository.getSentimentPulse().listen(
        (pulse) => add(UpdateSentimentPulse(pulse)),
        onError: (e) => print('NewsBloc: SentimentPulse error: $e'),
      );

      // Emit initial Loaded state with default data
      emit(const NewsLoaded(
        articles: [],
        pulse: SentimentPulse(
          globalScore: 71,
          fearPercent: 12.4,
          neutralPercent: 16.6,
          greedPercent: 71.0,
          phase: 'GREED',
        ),
        chatMessages: [
          {'text': 'Hello Trader. I\'ve scanned the macro data. How can I assist?', 'isAi': true}
        ],
      ));
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
      final updatedMessages = List<Map<String, dynamic>>.from(currentState.chatMessages)
        ..add({'text': event.query, 'isAi': false});
      
      emit(currentState.copyWith(
        chatMessages: updatedMessages,
        isAiThinking: true,
      ));

      try {
        final aiResponse = await _newsRepository.getAISentimentAnalysis(event.query);
        
        final finalMessages = List<Map<String, dynamic>>.from(updatedMessages)
          ..add({'text': aiResponse, 'isAi': true});
        
        emit(currentState.copyWith(
          chatMessages: finalMessages,
          isAiThinking: false,
        ));
      } catch (e) {
        emit(currentState.copyWith(isAiThinking: false));
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
