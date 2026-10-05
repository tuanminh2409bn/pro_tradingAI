import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/utils/push_chart_target.dart';
import 'package:protrading_ai/logic/navigation_cubit.dart';

void main() {
  test(
    'structured push opens the requested chart and normal navigation clears it',
    () async {
      final target = PushChartTarget.fromUri(
        Uri.parse(
          'https://qa.example/?tab=trading_room&symbol=ETHUSD&timeframe=H4&closed_at=1791158400',
        ),
      )!;
      expect(target.closedAt, 1791158400);
      final nav = NavigationCubit.forTradingRoom(
        target.symbol,
        target.timeframe,
      );
      addTearDown(nav.close);
      expect(nav.state, NavbarItem.tradingRoom);
      expect(nav.tradingRoomSymbol, 'ETHUSD');
      expect(nav.tradingRoomTimeframe, 'H4');
      nav.getNavBarItem(NavbarItem.profile);
      expect(nav.tradingRoomSymbol, isNull);
    },
  );
  test('ambiguous, invalid or unstructured links fail closed', () {
    for (final query in [
      'tab=admin&symbol=ETHUSD&timeframe=H4&closed_at=100',
      'tab=trading_room&symbol=ETHUSD&symbol=BTCUSD&timeframe=H4&closed_at=100',
      'tab=trading_room&symbol=ETHUSD&timeframe=M1&closed_at=100',
      'tab=trading_room&symbol=../admin&timeframe=H4&closed_at=100',
      'tab=trading_room&symbol=ETHUSD&timeframe=H4&closed_at=0',
      'symbol=ETHUSD',
    ]) {
      expect(
        PushChartTarget.fromUri(Uri.parse('https://qa.example/?$query')),
        isNull,
      );
    }
  });
}
