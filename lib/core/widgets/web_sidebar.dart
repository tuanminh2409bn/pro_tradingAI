import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logic/navigation_cubit.dart';
import '../constants/colors.dart';

class WebSidebar extends StatelessWidget {
  final bool isMobile;
  const WebSidebar({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isMobile ? double.infinity : 260,
      color: const Color(0xFF191c1f),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 40),
          _buildNavItem(context, Icons.show_chart, 'Trading Room', NavbarItem.tradingRoom),
          _buildNavItem(context, Icons.auto_stories, 'Journal', NavbarItem.journal),
          _buildNavItem(context, Icons.dynamic_feed, 'News Feed', NavbarItem.newsFeed),
          _buildNavItem(context, Icons.history_edu, 'Backtest Dojo', NavbarItem.backtestDojo),
          _buildNavItem(context, Icons.groups, 'Community', NavbarItem.community),
          _buildNavItem(context, Icons.radar, 'Market Radar', NavbarItem.radar),
          _buildNavItem(context, Icons.card_giftcard, 'Referral Hub', NavbarItem.referral),
          _buildNavItem(context, Icons.person, 'Profile', NavbarItem.profile),
          const Spacer(),
          _buildNavItem(context, Icons.admin_panel_settings, 'Admin Center', NavbarItem.admin),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, NavbarItem item) {
    return BlocBuilder<NavigationCubit, NavbarItem>(
      builder: (context, currentItem) {
        final isActive = currentItem == item;
        return InkWell(
          onTap: () {
            context.read<NavigationCubit>().getNavBarItem(item);
            if (isMobile) Navigator.pop(context); // Close drawer on mobile
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF1d2023) : Colors.transparent,
              border: isActive ? const Border(right: BorderSide(color: Color(0xFF3772FF), width: 2)) : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: isActive ? const Color(0xFF3772FF) : const Color(0xFFc3c6d8), size: 20),
                const SizedBox(width: 12),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFFc3c6d8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
