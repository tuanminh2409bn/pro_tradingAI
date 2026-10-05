import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/sync_gate_modal.dart';
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
import '../../auth/bloc/auth_event.dart';
import '../../../core/security/admin_access.dart';
import '../../../core/utils/community_post_link.dart';
import '../../../core/utils/push_chart_target.dart';

class WebDashboardShell extends StatefulWidget {
  const WebDashboardShell({super.key});

  @override
  State<WebDashboardShell> createState() => _WebDashboardShellState();
}

class _WebDashboardShellState extends State<WebDashboardShell> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final String? userId = authState.user?.uid;
    final sharedPostId = sharedCommunityPostId(Uri.base);
    final pushTarget = PushChartTarget.fromUri(Uri.base);

    return BlocProvider(
      create: (context) => pushTarget != null
          ? NavigationCubit.forTradingRoom(
              pushTarget.symbol,
              pushTarget.timeframe,
            )
          : (NavigationCubit()..getNavBarItem(
              sharedPostId == null
                  ? NavbarItem.tradingRoom
                  : NavbarItem.community,
            )),
      child: SyncGateHost(
        userId: userId,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;

            return Scaffold(
              key: scaffoldKey,
              drawer: isMobile
                  ? const Drawer(child: WebSidebar(isMobile: true))
                  : null,
              body: Row(
                children: [
                  if (!isMobile) const WebSidebar(),
                  Expanded(
                    child: BlocBuilder<NavigationCubit, NavbarItem>(
                      builder: (context, currentItem) {
                        final VoidCallback? onMenuPressed = isMobile
                            ? () => scaffoldKey.currentState?.openDrawer()
                            : null;

                        switch (currentItem) {
                          case NavbarItem.tradingRoom:
                            return TradingRoomWebPage(
                              userId: userId,
                              initialSymbol: context
                                  .read<NavigationCubit>()
                                  .tradingRoomSymbol,
                              initialTimeframe: context
                                  .read<NavigationCubit>()
                                  .tradingRoomTimeframe,
                              onMenuPressed: onMenuPressed,
                            );
                          case NavbarItem.journal:
                            return JournalWebPage(
                              userId: userId,
                              onMenuPressed: onMenuPressed,
                            );
                          case NavbarItem.newsFeed:
                            return NewsFeedWebPage(
                              userId: userId,
                              onMenuPressed: onMenuPressed,
                            );
                          case NavbarItem.backtestDojo:
                            return BacktestWebPage(
                              userId: userId,
                              onMenuPressed: onMenuPressed,
                            );
                          case NavbarItem.community:
                            return CommunityWebPage(
                              onMenuPressed: onMenuPressed,
                              sharedPostId: sharedPostId,
                            );
                          case NavbarItem.radar:
                            return RadarWebPage(onMenuPressed: onMenuPressed);
                          case NavbarItem.referral:
                            return ReferralWebPage(
                              userId: userId,
                              onMenuPressed: onMenuPressed,
                              registrationPending:
                                  authState.registrationReferralPending,
                              registrationMessageKey:
                                  authState.registrationReferralMessageKey,
                              onRegistrationRetry:
                                  authState.registrationReferralRetryable
                                  ? () => context.read<AuthBloc>().add(
                                      const AuthRegistrationReferralRequested(),
                                    )
                                  : null,
                            );
                          case NavbarItem.profile:
                            return ProfileWebPage(
                              userId: userId,
                              onMenuPressed: onMenuPressed,
                            );
                          case NavbarItem.admin:
                            return const AdminAccessGate(child: AdminWebPage());
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
