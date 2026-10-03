import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/profile_models.dart';
import 'package:protrading_ai/features/profile/bloc/profile_state.dart';

void main() {
  test('Backtest-only authoritative quota has its own reset metadata', () {
    final quota = AccessQuota(
      apiUsed: 0,
      apiLimit: 0,
      backtestUsed: 1,
      backtestLimit: 2,
      storageUsed: 0,
      storageLimit: 0,
      source: 'server_enforced',
      backtestResetAt: DateTime.utc(2026, 10, 5),
    );
    expect(quota.hasBacktestQuota, isTrue);
    expect(quota.hasApiQuota, isFalse);
    expect(quota.resetAt, isNull);
    final incomplete = AccessQuota(
      apiUsed: 1,
      apiLimit: 2,
      backtestUsed: 1,
      backtestLimit: 2,
      storageUsed: 0,
      storageLimit: 0,
      source: 'server_enforced',
      resetAt: DateTime.utc(2026, 10, 5),
    );
    expect(incomplete.hasApiQuota, isTrue);
    expect(incomplete.hasBacktestQuota, isFalse);
  });
  test('Web privacy preferences default to explicit opt-in', () {
    const state = ProfileLoaded(
      profile: UserProfile(
        username: '',
        email: '',
        tier: 'FREE',
        totalTrades: 0,
        winRate: 0,
        rank: 0,
        avatarUrl: '',
      ),
      quota: AccessQuota.unavailable(),
    );

    expect(state.pushNotificationsEnabled, isFalse);
    expect(state.dataSharingEnabled, isFalse);
  });

  test('missing quota is unavailable instead of a fabricated allowance', () {
    const quota = AccessQuota.unavailable();

    expect(quota.isAuthoritative, isFalse);
    expect(quota.apiRemaining, isNull);
    expect(quota.apiLimit, 0);
    expect(quota.backtestLimit, 0);
    expect(quota.storageLimit, 0);
  });

  test(
    'server-enforced quota exposes bounded authoritative remaining count',
    () {
      final quota = AccessQuota(
        apiUsed: 49,
        apiLimit: 50,
        backtestUsed: 0,
        backtestLimit: 0,
        storageUsed: 0,
        storageLimit: 0,
        source: 'server_enforced',
        resetAt: DateTime.utc(2026, 9, 13),
      );

      expect(quota.isAuthoritative, isTrue);
      expect(quota.apiRemaining, 1);
      expect(quota.hasApiQuota, isTrue);
      expect(quota.hasBacktestQuota, isFalse);
    },
  );
}
