import 'package:equatable/equatable.dart';
import '../../../data/models/news_models.dart';

abstract class NewsState extends Equatable {
  const NewsState();

  @override
  List<Object?> get props => [];
}

class NewsInitial extends NewsState {}

class NewsLoading extends NewsState {}

class NewsLoaded extends NewsState {
  final List<NewsArticle> articles;
  final SentimentPulse pulse;
  final List<Map<String, dynamic>> chatMessages;
  final bool isAiThinking;

  const NewsLoaded({
    required this.articles,
    required this.pulse,
    this.chatMessages = const [],
    this.isAiThinking = false,
  });

  NewsLoaded copyWith({
    List<NewsArticle>? articles,
    SentimentPulse? pulse,
    List<Map<String, dynamic>>? chatMessages,
    bool? isAiThinking,
  }) {
    return NewsLoaded(
      articles: articles ?? this.articles,
      pulse: pulse ?? this.pulse,
      chatMessages: chatMessages ?? this.chatMessages,
      isAiThinking: isAiThinking ?? this.isAiThinking,
    );
  }

  @override
  List<Object?> get props => [articles, pulse, chatMessages, isAiThinking];
}

class NewsError extends NewsState {
  final String message;
  const NewsError(this.message);

  @override
  List<Object?> get props => [message];
}
