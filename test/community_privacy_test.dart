import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/community_models.dart';

void main() {
  group('Community post content', () {
    test('trims surrounding whitespace before persistence', () {
      expect(normalizeCommunityPostContent('  Gold setup  '), 'Gold setup');
    });

    test('rejects empty and oversized content', () {
      expect(isValidCommunityPostContent('   '), isFalse);
      expect(
        isValidCommunityPostContent('x' * (communityPostMaxLength + 1)),
        isFalse,
      );
    });

    test('accepts content at the exact supported limit', () {
      expect(isValidCommunityPostContent('x' * communityPostMaxLength), isTrue);
    });
  });

  test('community trade facts fail closed without server verification', () {
    const genericPost = CommunityPost(
      userName: 'Trader',
      avatarUrl: '',
      timeAgo: 'now',
      content: 'Market note',
      tradeInfo: 'XAUUSD BUY',
      profit: 250,
      isProfit: true,
      likes: 0,
      comments: 0,
    );
    const verifiedPost = CommunityPost(
      userName: 'Trader',
      avatarUrl: '',
      timeAgo: 'now',
      content: 'Market note',
      tradeInfo: 'XAUUSD BUY',
      profit: 250,
      isProfit: true,
      likes: 0,
      comments: 0,
      tradeVerified: true,
      verificationReference: 'server-trade-1',
    );

    expect(genericPost.hasVerifiedTrade, isFalse);
    expect(verifiedPost.hasVerifiedTrade, isTrue);
  });

  group('Community privacy masker', () {
    test(
      'removes account identity and monetary amounts from shared payload',
      () {
        final source = VerifiedTradeShareSource(
          accountId: 'broker-account-secret-123',
          symbol: 'XAUUSD',
          direction: 'BUY',
          openingEquity: 10000,
          netProfit: 1250,
          unitVolume: 42000,
          closedAt: DateTime.utc(2026, 9, 12, 8, 30),
          verificationReference: 'server-verification-1',
          isServerVerified: true,
        );

        final card = CommunityPrivacyMasker.maskVerifiedTrade(source);
        final payload = card.toPersistenceMap();
        final encoded = jsonEncode(payload);

        expect(card.growthPercent, 12.5);
        expect(payload.keys, {
          'symbol',
          'direction',
          'growth_percent',
          'unit_volume',
          'closed_at',
          'is_verified',
        });
        expect(encoded, isNot(contains(source.accountId)));
        expect(encoded, isNot(contains(source.verificationReference)));
        expect(encoded, isNot(contains('10000')));
        expect(encoded, isNot(contains('1250')));
      },
    );

    test('fails closed for unverified or invalid source results', () {
      expect(
        () => CommunityPrivacyMasker.maskVerifiedTrade(
          VerifiedTradeShareSource(
            accountId: 'account-1',
            symbol: 'XAUUSD',
            direction: 'BUY',
            openingEquity: 1000,
            netProfit: 100,
            unitVolume: 10,
            closedAt: DateTime.utc(2026, 9, 12),
            verificationReference: 'verification-1',
            isServerVerified: false,
          ),
        ),
        throwsStateError,
      );
      expect(
        () => CommunityPrivacyMasker.maskVerifiedTrade(
          VerifiedTradeShareSource(
            accountId: 'account-1',
            symbol: 'XAUUSD',
            direction: 'BUY',
            openingEquity: 0,
            netProfit: 100,
            unitVolume: 10,
            closedAt: DateTime.utc(2026, 9, 12),
            verificationReference: 'verification-1',
            isServerVerified: true,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Verified community leaderboard', () {
    test('ranks verified growth then real unit volume deterministically', () {
      final entries = CommunityLeaderboard.rankVerified([
        const VerifiedLeaderboardMetric(
          publicParticipantId: 'trader-b',
          displayName: 'Trader B',
          growthPercent: 10,
          unitVolume: 500,
          isServerVerified: true,
        ),
        const VerifiedLeaderboardMetric(
          publicParticipantId: 'trader-c',
          displayName: 'Trader C',
          growthPercent: 12,
          unitVolume: 100,
          isServerVerified: true,
        ),
        const VerifiedLeaderboardMetric(
          publicParticipantId: 'trader-a',
          displayName: 'Trader A',
          growthPercent: 10,
          unitVolume: 800,
          isServerVerified: true,
        ),
      ]);

      expect(entries.map((entry) => entry.publicParticipantId), [
        'trader-c',
        'trader-a',
        'trader-b',
      ]);
      expect(entries.map((entry) => entry.rank), [1, 2, 3]);
      expect(entries[1].unitVolume, 800);
    });

    test('rejects unverified and duplicate leaderboard identities', () {
      expect(
        () => CommunityLeaderboard.rankVerified([
          const VerifiedLeaderboardMetric(
            publicParticipantId: 'trader-a',
            displayName: 'Trader A',
            growthPercent: 10,
            unitVolume: 100,
            isServerVerified: false,
          ),
        ]),
        throwsStateError,
      );
      expect(
        () => CommunityLeaderboard.rankVerified([
          const VerifiedLeaderboardMetric(
            publicParticipantId: 'trader-a',
            displayName: 'Trader A',
            growthPercent: 10,
            unitVolume: 100,
            isServerVerified: true,
          ),
          const VerifiedLeaderboardMetric(
            publicParticipantId: 'trader-a',
            displayName: 'Duplicate',
            growthPercent: 20,
            unitVolume: 200,
            isServerVerified: true,
          ),
        ]),
        throwsArgumentError,
      );
    });
  });
}
