import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/profile_repository.dart';

void main() {
  test('broker link request accepts only a confirmed account creation', () {
    expect(
      brokerLinkRequestAccepted(
        200,
        '{"status":"success","accountId":"broker-1"}',
      ),
      isTrue,
    );
    expect(
      brokerLinkRequestAccepted(
        200,
        '{"status":"error","message":"unavailable"}',
      ),
      isFalse,
    );
    expect(brokerLinkRequestAccepted(200, '{"status":"success"}'), isFalse);
    expect(brokerLinkRequestAccepted(200, 'invalid JSON'), isFalse);
    expect(
      brokerLinkRequestAccepted(
        403,
        '{"status":"success","accountId":"broker-1"}',
      ),
      isFalse,
    );
  });
}
