import 'package:flutter_bloc/flutter_bloc.dart';

enum NavbarItem {
  tradingRoom,
  journal,
  newsFeed,
  backtestDojo,
  community,
  referral,
  profile,
  radar,
  admin
}

class NavigationCubit extends Cubit<NavbarItem> {
  NavigationCubit() : super(NavbarItem.tradingRoom);

  void getNavBarItem(NavbarItem navbarItem) => emit(navbarItem);
}
