import 'package:equatable/equatable.dart';

class NewsArticle extends Equatable {
  final String title;
  final String source;
  final String timeAgo;
  final int sentimentScore;
  final String type; // 'FOREXFACTORY', 'TWITTER', 'ALERT'
  final String impact; // 'HIGH', 'MEDIUM', 'LOW'
  final String summary;
  final String url;
  final String imageUrl;

  const NewsArticle({
    required this.title,
    required this.source,
    required this.timeAgo,
    required this.sentimentScore,
    required this.type,
    this.impact = 'LOW',
    this.summary = '',
    this.url = '',
    this.imageUrl = '',
  });

  @override
  List<Object?> get props => [
        title,
        source,
        timeAgo,
        sentimentScore,
        type,
        impact,
        summary,
        url,
        imageUrl,
      ];
}

class SentimentPulse extends Equatable {
  final int globalScore;
  final double fearPercent;
  final double neutralPercent;
  final double greedPercent;
  final String phase; // 'GREED', 'FEAR', 'NEUTRAL'

  const SentimentPulse({
    required this.globalScore,
    required this.fearPercent,
    required this.neutralPercent,
    required this.greedPercent,
    required this.phase,
  });

  @override
  List<Object?> get props => [globalScore, fearPercent, neutralPercent, greedPercent, phase];
}
