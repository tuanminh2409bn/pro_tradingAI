import 'package:equatable/equatable.dart';
import '../../../data/models/news_models.dart';

abstract class NewsEvent extends Equatable {
  const NewsEvent();

  @override
  List<Object?> get props => [];
}

class LoadNewsData extends NewsEvent {
  final String? userId;
  const LoadNewsData({this.userId});

  @override
  List<Object?> get props => [userId];
}

class UpdateNewsFeed extends NewsEvent {
  final List<NewsArticle> articles;
  const UpdateNewsFeed(this.articles);

  @override
  List<Object?> get props => [articles];
}

class UpdateSentimentPulse extends NewsEvent {
  final SentimentPulse pulse;
  const UpdateSentimentPulse(this.pulse);

  @override
  List<Object?> get props => [pulse];
}

class AskAIAnalyst extends NewsEvent {
  final String query;
  const AskAIAnalyst(this.query);

  @override
  List<Object?> get props => [query];
}
