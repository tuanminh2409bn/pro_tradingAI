import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/web_sidebar.dart';
import '../../../logic/navigation_cubit.dart';
import '../../trading_room/web/trading_room_web_page.dart';
import '../../journal/web/journal_web_page.dart';
import '../../news_feed/web/news_feed_web_page.dart';
import '../../backtest/web/backtest_web_page.dart';
import '../../community/web/community_web_page.dart';
import '../../radar/web/radar_web_page.dart';
import '../../referral/web/referral_web_page.dart';
import '../../profile/web/profile_web_page.dart';
import '../../admin/web/admin_web_page.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';

class WebDashboardShell extends StatelessWidget {
  const WebDashboardShell({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final String? userId = authState.user?.uid;
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

    return BlocProvider(
      create: (context) => NavigationCubit(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          
          return Scaffold(
            key: scaffoldKey,
            drawer: isMobile ? const Drawer(child: WebSidebar(isMobile: true)) : null,
            body: Row(
              children: [
                if (!isMobile) const WebSidebar(),
                Expanded(
                  child: BlocBuilder<NavigationCubit, NavbarItem>(
                    builder: (context, currentItem) {
                      final VoidCallback? onMenuPressed = isMobile ? () => scaffoldKey.currentState?.openDrawer() : null;
                      
                      switch (currentItem) {
                        case NavbarItem.tradingRoom:
                          return TradingRoomWebPage(userId: userId, onMenuPressed: onMenuPressed);
                        case NavbarItem.journal:
                          return JournalWebPage(userId: userId, onMenuPressed: onMenuPressed);
                        case NavbarItem.newsFeed:
                          return NewsFeedWebPage(userId: userId, onMenuPressed: onMenuPressed);
                        case NavbarItem.backtestDojo:
                          return const BacktestWebPage();
                        case NavbarItem.community:
                          return const CommunityWebPage();
                        case NavbarItem.radar:
                          return const RadarWebPage();
                        case NavbarItem.referral:
                          return ReferralWebPage(userId: userId, onMenuPressed: onMenuPressed);
                        case NavbarItem.profile:
                          return ProfileWebPage(userId: userId, onMenuPressed: onMenuPressed);
                        case NavbarItem.admin:
                          return const AdminWebPage();
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
