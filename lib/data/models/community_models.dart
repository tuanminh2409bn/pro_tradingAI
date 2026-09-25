import 'package:equatable/equatable.dart';

const int communityPostMaxLength = 2000;

String normalizeCommunityPostContent(String rawContent) => rawContent.trim();

bool isValidCommunityPostContent(String rawContent) {
  final content = normalizeCommunityPostContent(rawContent);
  return content.isNotEmpty && content.length <= communityPostMaxLength;
}

class CommunityPost extends Equatable {
  final String? id;
  final String? ownerId;
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
  final bool tradeVerified;
  final String? verificationReference;

  const CommunityPost({
    this.id,
    this.ownerId,
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
    this.tradeVerified = false,
    this.verificationReference,
  });

  bool get hasVerifiedTrade =>
      tradeVerified &&
      verificationReference?.trim().isNotEmpty == true &&
      tradeInfo.trim().isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    ownerId,
    userName,
    timeAgo,
    content,
    profit,
    likes,
    tradeVerified,
    verificationReference,
  ];
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

class VerifiedTradeShareSource extends Equatable {
  final String accountId;
  final String symbol;
  final String direction;
  final double openingEquity;
  final double netProfit;
  final double unitVolume;
  final DateTime closedAt;
  final String verificationReference;
  final bool isServerVerified;

  const VerifiedTradeShareSource({
    required this.accountId,
    required this.symbol,
    required this.direction,
    required this.openingEquity,
    required this.netProfit,
    required this.unitVolume,
    required this.closedAt,
    required this.verificationReference,
    required this.isServerVerified,
  });

  @override
  List<Object?> get props => [
    accountId,
    symbol,
    direction,
    openingEquity,
    netProfit,
    unitVolume,
    closedAt,
    verificationReference,
    isServerVerified,
  ];
}

class PrivacySafeTradeCard extends Equatable {
  final String symbol;
  final String direction;
  final double growthPercent;
  final double unitVolume;
  final DateTime closedAt;

  const PrivacySafeTradeCard({
    required this.symbol,
    required this.direction,
    required this.growthPercent,
    required this.unitVolume,
    required this.closedAt,
  });

  Map<String, dynamic> toPersistenceMap() => {
    'symbol': symbol,
    'direction': direction,
    'growth_percent': growthPercent,
    'unit_volume': unitVolume,
    'closed_at': closedAt.toUtc().toIso8601String(),
    'is_verified': true,
  };

  @override
  List<Object?> get props => [
    symbol,
    direction,
    growthPercent,
    unitVolume,
    closedAt,
  ];
}

class CommunityPrivacyMasker {
  const CommunityPrivacyMasker._();

  static PrivacySafeTradeCard maskVerifiedTrade(
    VerifiedTradeShareSource source,
  ) {
    if (!source.isServerVerified) {
      throw StateError('Only server-verified trades can be shared');
    }
    final symbol = source.symbol.trim().toUpperCase();
    final direction = source.direction.trim().toUpperCase();
    if (source.accountId.trim().isEmpty ||
        source.verificationReference.trim().isEmpty ||
        symbol.isEmpty ||
        (direction != 'BUY' && direction != 'SELL') ||
        !source.openingEquity.isFinite ||
        source.openingEquity <= 0 ||
        !source.netProfit.isFinite ||
        !source.unitVolume.isFinite ||
        source.unitVolume <= 0) {
      throw ArgumentError('Invalid verified trade share source');
    }
    final rawGrowth = source.netProfit / source.openingEquity * 100;
    final growthPercent = (rawGrowth * 10000).roundToDouble() / 10000;
    return PrivacySafeTradeCard(
      symbol: symbol,
      direction: direction,
      growthPercent: growthPercent,
      unitVolume: source.unitVolume,
      closedAt: source.closedAt.toUtc(),
    );
  }
}

class VerifiedLeaderboardMetric extends Equatable {
  final String publicParticipantId;
  final String displayName;
  final double growthPercent;
  final double unitVolume;
  final bool isServerVerified;

  const VerifiedLeaderboardMetric({
    required this.publicParticipantId,
    required this.displayName,
    required this.growthPercent,
    required this.unitVolume,
    required this.isServerVerified,
  });

  @override
  List<Object?> get props => [
    publicParticipantId,
    displayName,
    growthPercent,
    unitVolume,
    isServerVerified,
  ];
}

class VerifiedLeaderboardEntry extends Equatable {
  final int rank;
  final String publicParticipantId;
  final String displayName;
  final double growthPercent;
  final double unitVolume;

  const VerifiedLeaderboardEntry({
    required this.rank,
    required this.publicParticipantId,
    required this.displayName,
    required this.growthPercent,
    required this.unitVolume,
  });

  @override
  List<Object?> get props => [
    rank,
    publicParticipantId,
    displayName,
    growthPercent,
    unitVolume,
  ];
}

class CommunityLeaderboard {
  const CommunityLeaderboard._();

  static List<VerifiedLeaderboardEntry> rankVerified(
    Iterable<VerifiedLeaderboardMetric> metrics,
  ) {
    final ranked = metrics.toList(growable: false);
    final identities = <String>{};
    for (final metric in ranked) {
      if (!metric.isServerVerified) {
        throw StateError('Leaderboard input must be server-verified');
      }
      final participantId = metric.publicParticipantId.trim();
      if (participantId.isEmpty ||
          metric.displayName.trim().isEmpty ||
          !metric.growthPercent.isFinite ||
          !metric.unitVolume.isFinite ||
          metric.unitVolume < 0) {
        throw ArgumentError('Invalid verified leaderboard metric');
      }
      if (!identities.add(participantId)) {
        throw ArgumentError.value(
          participantId,
          'publicParticipantId',
          'Leaderboard identities must be unique',
        );
      }
    }
    ranked.sort((left, right) {
      final byGrowth = right.growthPercent.compareTo(left.growthPercent);
      if (byGrowth != 0) return byGrowth;
      final byVolume = right.unitVolume.compareTo(left.unitVolume);
      if (byVolume != 0) return byVolume;
      return left.publicParticipantId.trim().compareTo(
        right.publicParticipantId.trim(),
      );
    });
    return List<VerifiedLeaderboardEntry>.unmodifiable(
      ranked.indexed.map(
        (entry) => VerifiedLeaderboardEntry(
          rank: entry.$1 + 1,
          publicParticipantId: entry.$2.publicParticipantId.trim(),
          displayName: entry.$2.displayName.trim(),
          growthPercent: entry.$2.growthPercent,
          unitVolume: entry.$2.unitVolume,
        ),
      ),
    );
  }
}
