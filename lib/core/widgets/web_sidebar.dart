import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../logic/navigation_cubit.dart';
import '../localization/app_localizations.dart';
import '../constants/colors.dart';
import 'language_toggle.dart';

import 'package:shared_preferences/shared_preferences.dart';

class WebSidebar extends StatefulWidget {
  final bool isMobile;
  const WebSidebar({super.key, this.isMobile = false});

  @override
  State<WebSidebar> createState() => _WebSidebarState();
}

class _WebSidebarState extends State<WebSidebar> {
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadCollapsedState();
  }

  Future<void> _loadCollapsedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isCollapsed = prefs.getBool('sidebar_collapsed') ?? false;
      });
    } catch (e) {
      print('WebSidebar: Error loading collapsed state: $e');
    }
  }

  Future<void> _saveCollapsedState(bool val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sidebar_collapsed', val);
    } catch (e) {
      print('WebSidebar: Error saving collapsed state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = widget.isMobile;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: isMobile ? double.infinity : (_isCollapsed ? 70 : 260),
      color: const Color(0xFF191c1f),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isCollapsed)
                  const Text(
                    'KINETIC',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  )
                else
                  const Text(
                    'K',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: -1,
                    ),
                  ),
                if (!isMobile) ...[
                  const SizedBox(height: 12),
                  Tooltip(
                    message: _isCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                    child: IconButton(
                      icon: Icon(
                        _isCollapsed
                            ? Icons.chevron_right
                            : Icons.chevron_left,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      onPressed: () {
                        final newVal = !_isCollapsed;
                        setState(() => _isCollapsed = newVal);
                        _saveCollapsedState(newVal);
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                      ),
                      hoverColor: Colors.white12,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 30),
          _buildNavItem(context, Icons.show_chart, context.tr('trading_room'), NavbarItem.tradingRoom),
          _buildNavItem(context, Icons.auto_stories, context.tr('journal'), NavbarItem.journal),
          _buildNavItem(context, Icons.dynamic_feed, context.tr('news_feed'), NavbarItem.newsFeed),
          _buildNavItem(context, Icons.history_edu, context.tr('backtest_dojo'), NavbarItem.backtestDojo),
          _buildNavItem(context, Icons.groups, context.tr('community'), NavbarItem.community),
          _buildNavItem(context, Icons.radar, context.tr('market_radar'), NavbarItem.radar),
          _buildNavItem(context, Icons.card_giftcard, context.tr('referral_hub'), NavbarItem.referral),
          _buildNavItem(context, Icons.person, context.tr('profile'), NavbarItem.profile),
          const Spacer(),
          _buildNavItem(context, Icons.admin_panel_settings, context.tr('admin_center'), NavbarItem.admin),
          const SizedBox(height: 20),
          LanguageToggle(isCollapsed: _isCollapsed && !isMobile),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, NavbarItem item) {
    final bool isMobile = widget.isMobile;
    return BlocBuilder<NavigationCubit, NavbarItem>(
      builder: (context, currentItem) {
        final isActive = currentItem == item;
        return InkWell(
          onTap: () {
            context.read<NavigationCubit>().getNavBarItem(item);
            if (isMobile) Navigator.pop(context); // Close drawer on mobile
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: (_isCollapsed && !isMobile) ? 0 : 20,
              vertical: 12,
            ),
            width: double.infinity,
            alignment: (_isCollapsed && !isMobile) ? Alignment.center : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF1d2023) : Colors.transparent,
              border: isActive ? const Border(right: BorderSide(color: Color(0xFF3772FF), width: 2)) : null,
            ),
            child: (_isCollapsed && !isMobile)
                ? Tooltip(
                    message: label.toUpperCase(),
                    child: Icon(icon, color: isActive ? const Color(0xFF3772FF) : const Color(0xFFc3c6d8), size: 20),
                  )
                : Row(
                    children: [
                      Icon(icon, color: isActive ? const Color(0xFF3772FF) : const Color(0xFFc3c6d8), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFFc3c6d8),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
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
