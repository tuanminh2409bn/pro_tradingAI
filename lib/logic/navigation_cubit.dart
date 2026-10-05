import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/models/trading_models.dart';

enum NavbarItem {
  tradingRoom,
  journal,
  newsFeed,
  backtestDojo,
  community,
  referral,
  profile,
  radar,
  admin,
}

class NavigationCubit extends Cubit<NavbarItem> {
  NavigationCubit() : super(NavbarItem.tradingRoom);

  NavigationCubit.forTradingRoom(String symbol, String timeframe)
    : super(NavbarItem.tradingRoom) {
    if (!RegExp(r'^[A-Z0-9]{3,16}$').hasMatch(symbol) ||
        !TradingMode.values.any((mode) => mode.allowsTimeframe(timeframe))) {
      throw ArgumentError('Invalid chart target');
    }
    _tradingRoomSymbol = symbol;
    _tradingRoomTimeframe = timeframe;
  }

  String? _tradingRoomSymbol;
  String? _tradingRoomTimeframe;
  String? get tradingRoomSymbol => _tradingRoomSymbol;
  String? get tradingRoomTimeframe => _tradingRoomTimeframe;

  void getNavBarItem(NavbarItem navbarItem) {
    _tradingRoomSymbol = null;
    _tradingRoomTimeframe = null;
    emit(navbarItem);
  }

  /// Page-entry target. An already-open chart uses TradingRoom events.
  bool openTradingRoom(String symbol, {String? timeframe}) {
    final normalizedSymbol = symbol.trim().toUpperCase();
    final normalizedTimeframe = timeframe == null
        ? null
        : TradingMode.scalping.normalizeTimeframe(
            timeframe.trim().toUpperCase(),
          );
    if (state == NavbarItem.tradingRoom ||
        !RegExp(r'^[A-Z0-9]{3,16}$').hasMatch(normalizedSymbol) ||
        (normalizedTimeframe != null &&
            !TradingMode.values.any(
              (mode) => mode.allowsTimeframe(normalizedTimeframe),
            ))) {
      return false;
    }
    _tradingRoomSymbol = normalizedSymbol;
    _tradingRoomTimeframe = normalizedTimeframe;
    emit(NavbarItem.tradingRoom);
    return true;
  }
}
