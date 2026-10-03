import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/trading_repository.dart';

void main() {
  test('waits for persisted completion, ignoring pending states', () async {
    final statuses = StreamController<Map<String, dynamic>?>();
    final result = waitForAnalysisRequest(statuses.stream);
    statuses.add({'status': 'PENDING'});
    statuses.add({'status': 'PROCESSING'});
    statuses.add({'status': 'COMPLETED'});
    await result;
    expect(statuses.hasListener, isFalse);
    await statuses.close();
  });

  test('quota rejection reports the actionable translated error', () async {
    await expectLater(
      waitForAnalysisRequest(
        Stream.value({'status': 'ERROR', 'error': 'quota_exhausted'}),
      ),
      throwsA(
        isA<AnalysisRequestFailure>().having(
          (error) => error.messageKey,
          'messageKey',
          'tr_analysis_quota_exhausted',
        ),
      ),
    );
  });

  test('unrecognized backend errors never become product messages', () async {
    await expectLater(
      waitForAnalysisRequest(
        Stream.value({'status': 'ERROR', 'error': 'private provider details'}),
      ),
      throwsA(
        isA<AnalysisRequestFailure>().having(
          (error) => error.messageKey,
          'messageKey',
          'tr_analysis_request_failed',
        ),
      ),
    );
  });

  test(
    'timeout cancels the Firestore listener and exposes a retry message',
    () async {
      final statuses = StreamController<Map<String, dynamic>?>();
      await expectLater(
        waitForAnalysisRequest(
          statuses.stream,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<AnalysisRequestFailure>().having(
            (error) => error.messageKey,
            'messageKey',
            'tr_analysis_timeout',
          ),
        ),
      );
      expect(statuses.hasListener, isFalse);
      await statuses.close();
    },
  );

  test(
    'permission failure cancels the listener without exposing details',
    () async {
      final statuses = StreamController<Map<String, dynamic>?>();
      final result = waitForAnalysisRequest(statuses.stream);
      statuses.addError(StateError('permission denied'));
      await expectLater(result, throwsA(isA<AnalysisRequestFailure>()));
      expect(statuses.hasListener, isFalse);
      await statuses.close();
    },
  );
}
