import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/models/referral_wallet.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'owner';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'fixture-token';
}

class _Auth extends Fake implements FirebaseAuth {
  User? account = _User();
  @override
  User? get currentUser => account;
}

class _Firestore extends Fake implements FirebaseFirestore {}

void main() {
  test(
    'ledger and withdrawal views reject fractional, unverified and invalid states',
    () {
      final now = DateTime.utc(2026, 10, 5);
      final entry = <String, dynamic>{
        'kind': 'CREDIT',
        'amountMinor': 20001,
        'currency': 'USD',
      };
      expect(RewardTransaction.fromLedger(entry, now)!.amountMinor, 20001);
      expect(
        RewardTransaction.fromLedger({
          ...entry,
          'kind': 'REVERSAL',
        }, now)!.amountMinor,
        -20001,
      );
      for (final patch in [
        {'amountMinor': 2.5},
        {'currency': 'VND'},
        {'kind': 'UNKNOWN'},
      ]) {
        expect(RewardTransaction.fromLedger({...entry, ...patch}, now), isNull);
      }
      final withdrawal = <String, dynamic>{
        'amountMinor': 2000,
        'currency': 'USD',
        'policyVersion': 'manual-subscription-v1',
        'status': 'APPROVED',
      };
      expect(
        ReferralWithdrawal.fromServer('a' * 64, withdrawal, now)!.status,
        'APPROVED',
      );
      expect(
        ReferralWithdrawal.fromServer('a' * 64, {
          ...withdrawal,
          'status': 'TRANSFERRED',
        }, now),
        isNull,
      );
      expect(
        ReferralWithdrawal.fromServer('a' * 64, {
          ...withdrawal,
          'amountMinor': true,
        }, now),
        isNull,
      );
    },
  );
  final base = <String, dynamic>{
    'creditsMinor': 10001,
    'reversedMinor': 1,
    'heldMinor': 2000,
    'paidMinor': 0,
    'currency': 'USD',
    'source': 'admin_verified_receipts',
    'policyVersion': 'manual-subscription-v1',
  };
  test(
    'wallet uses exact cents, requires provenance and reserves one active request',
    () {
      final wallet = ReferralWallet.fromServer(base)!;
      expect(wallet.availableMinor, 8000);
      expect(wallet.canRequestWithdrawal, isTrue);
      expect(ReferralWallet.money(10001), 'USD 100.01');
      expect(ReferralWallet.money(-1), '-USD 0.01');
      expect(
        ReferralWallet.fromServer({
          ...base,
          'pendingRequestId': 'a' * 64,
        })!.canRequestWithdrawal,
        isFalse,
      );
      for (final patch in [
        {'source': 'client'},
        {'creditsMinor': true},
        {'creditsMinor': 1.5},
        {'heldMinor': 20000},
        {'pendingRequestId': 'bad'},
        {'currency': 'VND'},
      ]) {
        expect(ReferralWallet.fromServer({...base, ...patch}), isNull);
      }
    },
  );
  test(
    'withdrawal passes stable intent and cents, never UID or balance',
    () async {
      final auth = _Auth();
      final body = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/referral/withdrawals');
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        body.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({'requestId': 'a' * 64, 'status': 'PENDING'}),
          200,
        );
      });
      addTearDown(client.close);
      final repo = ReferralRepository(
        auth: auth,
        firestore: _Firestore(),
        client: client,
      );
      for (var i = 0; i < 2; i++) {
        expect(
          await repo.requestWithdrawal(
            requestId: 'withdrawal-stable-1234',
            amountMinor: 2000,
          ),
          'PENDING',
        );
      }
      expect(body, [
        {'requestId': 'withdrawal-stable-1234', 'amountMinor': 2000},
        {'requestId': 'withdrawal-stable-1234', 'amountMinor': 2000},
      ]);
      auth.account = null;
      await expectLater(
        repo.requestWithdrawal(
          requestId: 'withdrawal-stable-1234',
          amountMinor: 2000,
        ),
        throwsStateError,
      );
      expect(body.length, 2);
    },
  );
}
