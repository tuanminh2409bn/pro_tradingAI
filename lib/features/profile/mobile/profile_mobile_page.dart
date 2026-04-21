import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class ProfileMobilePage extends StatelessWidget {
  const ProfileMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111417),
        elevation: 0,
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: AppColors.surface,
            child: Icon(Icons.person, size: 20, color: Colors.white24),
          ),
        ),
        title: const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF3772FF))),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.sensors, color: Color(0xFF3772FF))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserIdentityCard(),
            const SizedBox(height: 24),
            _buildSubscriptionTier(),
            const SizedBox(height: 24),
            _buildSecuritySection(),
            const SizedBox(height: 24),
            _buildPreferencesSection(),
            const SizedBox(height: 32),
            _buildSignOutBtn(context),
            const SizedBox(height: 100), // Space for unified bottom nav
          ],
        ),
      ),
    );
  }

  Widget _buildUserIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Text('Alex Rivera', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), SizedBox(width: 8), Icon(Icons.verified, size: 16, color: AppColors.primary)]),
                  Text('ID: KINETIC-8829-X', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3))),
                ],
              ),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primary.withOpacity(0.2))), child: const Text('PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary))),
            ],
          ),
          const SizedBox(height: 24),
          const Text('ACHIEVEMENT BADGES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _BadgeCircle(icon: Icons.workspace_premium, color: AppColors.primary),
                _BadgeCircle(icon: Icons.rocket_launch, color: AppColors.secondary, opacity: 0.6),
                _BadgeCircle(icon: Icons.diamond, color: Color(0xFFFFD700)),
                _BadgeCircle(icon: Icons.stars, color: Colors.white24, opacity: 0.4),
                _BadgeCircle(icon: Icons.verified_user, color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTier() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SUBSCRIPTION TIER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: const Border(left: BorderSide(color: AppColors.primary, width: 4))),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Standard Plus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text('Active until Oct 12, 2024', style: TextStyle(fontSize: 10, color: Colors.white24))]),
                  Text('\$24.99/mo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('API REQUEST QUOTA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38)), Text('82% REMAINING', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary))]),
              const SizedBox(height: 8),
              const LinearProgressIndicator(value: 0.82, color: AppColors.primary, backgroundColor: Colors.white10, minHeight: 4),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('UPGRADE TO ENTERPRISE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SECURITY & ACCESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              _buildListTile(Icons.security, 'Google Authenticator', 'Verified & Active', color: AppColors.primary, hasArrow: true),
              const Divider(color: Colors.white10, height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.terminal, color: AppColors.primary, size: 20)),
                        const SizedBox(width: 16),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Primary API Key', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), Text('hk_live_4992...9921', style: TextStyle(fontSize: 10, color: Colors.white24, fontStyle: FontStyle.italic))])),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Text('ROTATE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF0b0e11), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Read-only Permissions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                          Transform.scale(scale: 0.8, child: Switch(value: true, onChanged: (v) {}, activeColor: AppColors.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PREFERENCES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              _buildListTile(Icons.language, 'Interface Language', 'English (US)', hasArrow: false),
              const Divider(color: Colors.white10, height: 1),
              _buildListTile(Icons.notifications, 'Push Notifications', 'Active', hasToggle: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, String subtitle, {Color? color, bool hasArrow = false, bool hasToggle = false}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color ?? Colors.white54, size: 20)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), Text(subtitle, style: TextStyle(fontSize: 10, color: color ?? Colors.white24))])),
          if (hasArrow) const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
          if (hasToggle) Transform.scale(scale: 0.8, child: Switch(value: true, onChanged: (v) {}, activeColor: AppColors.primary)),
        ],
      ),
    );
  }

  Widget _buildSignOutBtn(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          context.read<AuthBloc>().add(AuthLogoutRequested());
        },
        icon: const Icon(Icons.logout, size: 16),
        label: const Text('Sign Out from All Devices', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.bear, side: BorderSide(color: AppColors.bear.withOpacity(0.2)), padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }
}

class _BadgeCircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double opacity;
  const _BadgeCircle({required this.icon, required this.color, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 48, height: 48,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Opacity(opacity: opacity, child: Icon(icon, color: color, size: 20)),
    );
  }
}
