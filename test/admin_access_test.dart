import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/security/admin_access.dart';

void main() {
  test('Admin UI fails closed unless the verified claim is exactly true', () {
    expect(hasVerifiedAdminClaim(null), isFalse);
    expect(hasVerifiedAdminClaim(const {}), isFalse);
    expect(hasVerifiedAdminClaim(const {'admin': 'true'}), isFalse);
    for (final role in [
      'standard',
      'verified_partner',
      'professional',
      'enterprise',
      'reserved_fifth',
    ]) {
      expect(hasVerifiedAdminClaim({'role': role}), isFalse);
    }
    expect(hasVerifiedAdminClaim(const {'admin': true}), isFalse);
    expect(
      hasVerifiedAdminClaim(const {'admin': true, 'role': 'standard'}),
      isTrue,
    );
    expect(
      hasVerifiedAdminClaim(const {'admin': true, 'role': 'reserved_fifth'}),
      isFalse,
    );
    expect(
      hasVerifiedAdminClaim(const {'admin': true, 'role': 'undefined'}),
      isFalse,
    );
  });

  testWidgets('Admin page stays hidden for every non-admin role', (
    tester,
  ) async {
    for (final role in [
      'standard',
      'verified_partner',
      'professional',
      'enterprise',
      'reserved_fifth',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminAccessGate(
            hasAccess: () async => hasVerifiedAdminClaim({'role': role}),
            child: const Text('ADMIN CONTENT'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ADMIN ACCESS DENIED'), findsOneWidget);
      expect(find.text('ADMIN CONTENT'), findsNothing);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessGate(
          hasAccess: () async => hasVerifiedAdminClaim(const {
            'admin': true,
            'role': 'reserved_fifth',
          }),
          child: const Text('ADMIN CONTENT'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ADMIN ACCESS DENIED'), findsOneWidget);
    expect(find.text('ADMIN CONTENT'), findsNothing);
  });

  testWidgets('verified Admin claim reveals the guarded page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessGate(
          hasAccess: () async => hasVerifiedAdminClaim(
            const {'admin': true, 'role': 'standard'},
          ),
          child: const Text('ADMIN CONTENT'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ADMIN CONTENT'), findsOneWidget);
    expect(find.text('ADMIN ACCESS DENIED'), findsNothing);
  });
}
