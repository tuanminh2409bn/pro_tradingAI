import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../logic/navigation_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../trading_room/mobile/trading_room_mobile_page.dart';
import '../../profile/mobile/profile_mobile_page.dart';
// Note: For other mobile pages, we can use placeholders or implement them
// since only Trading Room and Profile were found as _mobile_page.dart

class MobileDashboardShell extends StatelessWidget {
  const MobileDashboardShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => NavigationCubit(),
      child: Scaffold(
        body: BlocBuilder<NavigationCubit, NavbarItem>(
          builder: (context, currentItem) {
            switch (currentItem) {
              case NavbarItem.tradingRoom:
                return const TradingRoomMobilePage();
              case NavbarItem.profile:
                return const ProfileMobilePage();
              default:
                return Scaffold(
                  backgroundColor: AppColors.background,
                  appBar: AppBar(title: Text(currentItem.name.toUpperCase())),
                  body: Center(
                    child: Text(
                      '${currentItem.name} Mobile Page\nComing Soon',
                      style: const TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
            }
          },
        ),
        bottomNavigationBar: BlocBuilder<NavigationCubit, NavbarItem>(
          builder: (context, currentItem) {
            return Theme(
              data: ThemeData(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                currentIndex: _getSelectedIndex(currentItem),
                onTap: (index) {
                  context.read<NavigationCubit>().getNavBarItem(_getItemFromIndex(index));
                },
                backgroundColor: AppColors.background,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: Colors.white24,
                selectedFontSize: 10,
                unselectedFontSize: 10,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.candlestick_chart), label: 'TRADE'),
                  BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'RADAR'),
                  BottomNavigationBarItem(icon: Icon(Icons.newspaper), label: 'NEWS'),
                  BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'SOCIAL'),
                  BottomNavigationBarItem(icon: Icon(Icons.person), label: 'PROFILE'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  int _getSelectedIndex(NavbarItem item) {
    switch (item) {
      case NavbarItem.tradingRoom: return 0;
      case NavbarItem.radar: return 1;
      case NavbarItem.newsFeed: return 2;
      case NavbarItem.community: return 3;
      case NavbarItem.profile: return 4;
      default: return 0;
    }
  }

  NavbarItem _getItemFromIndex(int index) {
    switch (index) {
      case 0: return NavbarItem.tradingRoom;
      case 1: return NavbarItem.radar;
      case 2: return NavbarItem.newsFeed;
      case 3: return NavbarItem.community;
      case 4: return NavbarItem.profile;
      default: return NavbarItem.tradingRoom;
    }
  }
}
