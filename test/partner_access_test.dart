import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:protrading_ai/core/security/partner_access.dart';

void main() {
  test('broker linking requires the exact Verified Partner claim', () {
    expect(hasVerifiedPartnerClaim(null), isFalse);
    expect(hasVerifiedPartnerClaim(const {}), isFalse);
    for (final role in [
      'standard',
      'professional',
      'enterprise',
      'reserved_fifth',
      'Verified Partner',
    ]) {
      expect(hasVerifiedPartnerClaim({'role': role}), isFalse);
    }
    expect(hasVerifiedPartnerClaim(const {'admin': true}), isFalse);
    expect(hasVerifiedPartnerClaim(const {'role': 'verified_partner'}), isTrue);
  });

  testWidgets('partner action stays hidden until authorization succeeds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PartnerAccessGate(
          authorize: () async => false,
          child: const Text('Link broker'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Link broker'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: PartnerAccessGate(
          key: const ValueKey('partner'),
          authorize: () async => true,
          child: const Text('Link broker'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Link broker'), findsOneWidget);
  });
}
