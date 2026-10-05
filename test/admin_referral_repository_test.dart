import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/repositories/admin_repository.dart';

class _Claims extends Fake implements IdTokenResult {
  final bool admin;
  _Claims(this.admin);
  @override
  Map<String, dynamic>? get claims => {'role': 'standard', 'admin': admin};
}

class _User extends Fake implements User {
  bool admin = true;
  @override
  String get uid => 'admin-fixture';
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      _Claims(admin);
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'fixture-token';
}

class _Auth extends Fake implements FirebaseAuth {
  final account = _User();
  @override
  User? get currentUser => account;
}

class _Firestore extends Fake implements FirebaseFirestore {}

void main() {
  test(
    'receipt, reversal and payout use bearer token and exact server contracts',
    () async {
      final auth = _Auth();
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('admin'), isFalse);
        expect(body.containsKey('actorUid'), isFalse);
        bodies.add(body);
        final operation = request.url.path.split('/').last;
        return http.Response(
          jsonEncode(
            operation == 'receipts'
                ? {'status': 'recorded', 'receiptId': 'a' * 64}
                : {'status': operation == 'reversals' ? 'reversed' : 'PAID'},
          ),
          200,
        );
      });
      addTearDown(client.close);
      final repo = AdminRepository(
        auth: auth,
        firestore: _Firestore(),
        client: client,
      );
      expect(
        await repo.importReferralReceipt(
          receiptId: 'fixture-receipt-0001',
          payerUid: 'payer-fixture',
          netMinor: 10001,
          settledAt: DateTime.utc(2026, 9, 10),
        ),
        'a' * 64,
      );
      expect(bodies.single['netMinor'], 10001);
      expect(bodies.single['settledAt'], '2026-09-10T00:00:00.000Z');
      await repo.reverseReferralReceipt('a' * 64);
      await repo.reviewReferralWithdrawal(
        requestId: 'b' * 64,
        action: 'paid',
        paymentReference: 'external-fixture-0001',
      );
      expect(bodies.last['paymentReference'], 'external-fixture-0001');
      auth.account.admin = false;
      await expectLater(
        repo.reverseReferralReceipt('a' * 64),
        throwsStateError,
      );
      expect(bodies, hasLength(3));
    },
  );
}
