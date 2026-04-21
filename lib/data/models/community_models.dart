import 'package:equatable/equatable.dart';

class CommunityPost extends Equatable {
  final String userName;
  final String avatarUrl;
  final String timeAgo;
  final String content;
  final String tradeInfo; // e.g., 'XAUUSD Long'
  final double profit;
  final bool isProfit;
  final String? chartImageUrl;
  final int likes;
  final int comments;
  final bool isVerified;

  const CommunityPost({
    required this.userName,
    required this.avatarUrl,
    required this.timeAgo,
    required this.content,
    required this.tradeInfo,
    required this.profit,
    required this.isProfit,
    this.chartImageUrl,
    required this.likes,
    required this.comments,
    this.isVerified = false,
  });

  @override
  List<Object?> get props => [userName, timeAgo, content, profit, likes];
}

class LeaderboardEntry extends Equatable {
  final int rank;
  final String name;
  final String avatarUrl;
  final double performance;
  final String volume;

  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.avatarUrl,
    required this.performance,
    required this.volume,
  });

  @override
  List<Object?> get props => [rank, name, performance];
}
