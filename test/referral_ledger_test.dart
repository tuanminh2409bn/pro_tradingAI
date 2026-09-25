import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/referral_models.dart';

void main() {
  group('Immutable referral ledger', () {
    test('available balance derives only from unique settled entries', () {
      final ledger = ReferralLedger([
        const ReferralLedgerEntry(
          id: 'commission-f1',
          amount: 100,
          currency: 'USD',
          direction: LedgerDirection.credit,
          state: LedgerEntryState.settled,
        ),
        const ReferralLedgerEntry(
          id: 'commission-pending',
          amount: 50,
          currency: 'USD',
          direction: LedgerDirection.credit,
          state: LedgerEntryState.pending,
        ),
        const ReferralLedgerEntry(
          id: 'withdrawal-1',
          amount: 30,
          currency: 'USD',
          direction: LedgerDirection.debit,
          state: LedgerEntryState.settled,
        ),
      ]);

      expect(ledger.availableBalance, 70);
      expect(ledger.currency, 'USD');
      expect(
        () => ledger.entries.add(ledger.entries.first),
        throwsUnsupportedError,
      );
    });

    test('rejects duplicate entries and mixed currencies', () {
      const entry = ReferralLedgerEntry(
        id: 'same-id',
        amount: 100,
        currency: 'USD',
        direction: LedgerDirection.credit,
        state: LedgerEntryState.settled,
      );
      expect(() => ReferralLedger([entry, entry]), throwsArgumentError);
      expect(
        () => ReferralLedger([
          entry,
          const ReferralLedgerEntry(
            id: 'eur-entry',
            amount: 10,
            currency: 'EUR',
            direction: LedgerDirection.credit,
            state: LedgerEntryState.settled,
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('Withdrawal state machine', () {
    test('enforces explicit minimum and available balance', () {
      const policy = WithdrawalPolicy(currency: 'USD', minimumAmount: 50);

      expect(
        () => WithdrawalRequest.create(
          id: 'withdrawal-low',
          ownerUid: 'user-1',
          amount: 40,
          availableBalance: 120,
          policy: policy,
          requestedAt: DateTime.utc(2026, 9, 12),
        ),
        throwsArgumentError,
      );
      expect(
        () => WithdrawalRequest.create(
          id: 'withdrawal-high',
          ownerUid: 'user-1',
          amount: 130,
          availableBalance: 120,
          policy: policy,
          requestedAt: DateTime.utc(2026, 9, 12),
        ),
        throwsStateError,
      );
      final request = WithdrawalRequest.create(
        id: 'withdrawal-ok',
        ownerUid: 'user-1',
        amount: 100,
        availableBalance: 120,
        policy: policy,
        requestedAt: DateTime.utc(2026, 9, 12),
      );
      expect(request.status, WithdrawalStatus.pending);
      expect(request.version, 0);
    });

    test('only Super Admin can decide once with an auditable transition', () {
      final request = WithdrawalRequest.create(
        id: 'withdrawal-1',
        ownerUid: 'user-1',
        amount: 100,
        availableBalance: 120,
        policy: const WithdrawalPolicy(currency: 'USD', minimumAmount: 50),
        requestedAt: DateTime.utc(2026, 9, 12),
      );

      expect(
        () => request.decide(
          decision: WithdrawalStatus.approved,
          actorUid: 'user-1',
          actorRole: WithdrawalActorRole.user,
          expectedVersion: 0,
          decidedAt: DateTime.utc(2026, 9, 12, 1),
        ),
        throwsStateError,
      );
      final approved = request.decide(
        decision: WithdrawalStatus.approved,
        actorUid: 'admin-1',
        actorRole: WithdrawalActorRole.superAdmin,
        expectedVersion: 0,
        decidedAt: DateTime.utc(2026, 9, 12, 1),
      );

      expect(approved.status, WithdrawalStatus.approved);
      expect(approved.version, 1);
      expect(approved.auditTrail, hasLength(1));
      expect(approved.auditTrail.single.from, WithdrawalStatus.pending);
      expect(approved.auditTrail.single.to, WithdrawalStatus.approved);
      expect(approved.auditTrail.single.actorUid, 'admin-1');
      expect(
        () => approved.decide(
          decision: WithdrawalStatus.rejected,
          actorUid: 'admin-2',
          actorRole: WithdrawalActorRole.superAdmin,
          expectedVersion: 0,
          decidedAt: DateTime.utc(2026, 9, 12, 2),
          reason: 'duplicate attempt',
        ),
        throwsStateError,
      );
    });
  });
}
