import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';
import 'package:protrading_ai/features/referral/web/referral_web_page.dart';

final _identity = ReferralIdentity.fromServerLink(
  code: 'abcdefghijklmnopqrstuvwx',
  link: 'https://protrading-ai-2026.web.app/?ref=abcdefghijklmnopqrstuvwx',
);

class _Repository extends Fake implements ReferralRepository {
  bool fail = false;
  @override
  Future<ReferralIdentity> provisionIdentity() async {
    if (fail) throw StateError('unavailable');
    return _identity;
  }

  @override
  Stream<ReferralStats> getReferralStats(String uid) => Stream.value(
    ReferralStats.fromJson({
      'referralCode': _identity.code,
      'referralLink': _identity.qrPayload,
    }),
  );
  @override
  Stream<List<MemberNode>> getNetwork(String uid) => Stream.value(const []);
  @override
  Stream<List<RewardTransaction>> getRewardHistory(String uid) =>
      Stream.value(const []);
}

Widget _page(_Repository repository) =>
    RepositoryProvider<ReferralRepository>.value(
      value: repository,
      child: BlocProvider(
        create: (_) => LocaleCubit()..setLanguage('vi'),
        child: const MaterialApp(home: ReferralWebPage(userId: 'alice')),
      ),
    );

void main() {
  testWidgets(
    '390px Referral shows real QR/link, copies it and labels money unavailable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_page(_Repository()));
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có ledger phần thưởng và số thành viên được xác minh.'),
        findsOneWidget,
      );
      expect(find.text('USD 0.00'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
      final copy = find.byTooltip('Sao chép link giới thiệu');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, _identity.qrPayload);
      expect(find.text('Đã sao chép liên kết giới thiệu.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provision failure exposes retry instead of a fake code', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(_page(repository));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    repository.fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
