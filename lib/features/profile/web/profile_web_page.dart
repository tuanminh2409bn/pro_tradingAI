import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/profile_models.dart';
import '../../../data/repositories/profile_repository.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import '../bloc/profile_state.dart';

class ProfileWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const ProfileWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileBloc(
        profileRepository: context.read<ProfileRepository>(),
      )..add(LoadProfileData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is ProfileError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is ProfileLoaded) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return Column(
                    children: [
                      _WebTopNavbar(onMenuPressed: onMenuPressed),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 24.0 : 40.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(isMobile),
                              const SizedBox(height: 32),
                              if (isMobile) ...[
                                _buildProfileInfoCard(state.profile),
                                const SizedBox(height: 24),
                                _buildBrokerAccountsCard(context, state.brokerAccounts),
                                const SizedBox(height: 24),
                                _buildQuotaGrid(state.quota, isMobile),
                                const SizedBox(height: 24),
                                _buildSecurityCard(state.is2FAEnabled),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildProfileInfoCard(state.profile),
                                          const SizedBox(height: 24),
                                          _buildBrokerAccountsCard(context, state.brokerAccounts),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildQuotaGrid(state.quota, isMobile),
                                          const SizedBox(height: 24),
                                          _buildSecurityCard(state.is2FAEnabled),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security & Profile',
          style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage your identity, broker accounts and API quotas.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 12 : 14),
        ),
      ],
    );
  }

  Widget _buildProfileInfoCard(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: const Icon(Icons.person, color: AppColors.primary, size: 40),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(profile.email, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(profile.tier, style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat('TRADES', '${profile.totalTrades}'),
              _buildSimpleStat('WIN RATE', '${profile.winRate}%'),
              _buildSimpleStat('RANK', '#${profile.rank}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrokerAccountsCard(BuildContext context, List<BrokerAccount> accounts) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('BROKER ACCOUNTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () => _showLinkAccountDialog(context),
                icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
                label: const Text('LINK NEW', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (accounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('No accounts linked yet.', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12)),
              ),
            )
          else
            ...accounts.map((acc) => _buildBrokerItem(acc)),
        ],
      ),
    );
  }

  Widget _buildBrokerItem(BrokerAccount acc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(acc.platform == 'mt5' ? Icons.looks_5 : Icons.looks_4, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${acc.platform.toUpperCase()} - ${acc.login}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(acc.server, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: acc.status == 'CONNECTED' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              acc.status,
              style: TextStyle(
                color: acc.status == 'CONNECTED' ? Colors.green : Colors.orange,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinkAccountDialog(BuildContext context) {
    final platformController = TextEditingController(text: 'mt4');
    final serverController = TextEditingController();
    final loginController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Link Broker Account', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: 'mt4',
              dropdownColor: AppColors.surface,
              decoration: const InputDecoration(labelText: 'Platform', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'mt4', child: Text('MT4')),
                DropdownMenuItem(value: 'mt5', child: Text('MT5')),
              ],
              onChanged: (v) => platformController.text = v ?? 'mt4',
            ),
            TextField(
              controller: serverController,
              decoration: const InputDecoration(labelText: 'Broker Server (e.g. Exness-Real10)', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: loginController,
              decoration: const InputDecoration(labelText: 'Login ID', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Trading Password', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              context.read<ProfileBloc>().add(LinkBrokerAccountRequested(
                platform: platformController.text,
                server: serverController.text,
                login: loginController.text,
                password: passwordController.text,
              ));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Linking request sent. Check status in a few moments.')),
              );
            },
            child: const Text('LINK ACCOUNT'),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _buildQuotaGrid(AccessQuota quota, bool isMobile) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 1 : 1,
      mainAxisSpacing: 16,
      childAspectRatio: 4,
      children: [
        _buildQuotaCard('API REQUESTS', quota.apiUsed, quota.apiLimit, AppColors.primary),
        _buildQuotaCard('BACKTEST SESSIONS', quota.backtestUsed, quota.backtestLimit, AppColors.secondary),
        _buildQuotaCard('NEURAL STORAGE', quota.storageUsed.toInt(), quota.storageLimit.toInt(), AppColors.accent),
      ],
    );
  }

  Widget _buildQuotaCard(String label, int used, int limit, Color color) {
    double progress = used / limit;
progress = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
              Text('$used / $limit', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress, color: color, backgroundColor: Colors.white.withOpacity(0.03), minHeight: 4),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(bool is2FA) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SECURITY SETTINGS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phonelink_lock, color: AppColors.primary),
            title: const Text('Two-Factor Authentication', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Protect your account with 2FA.', style: TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: Switch(value: is2FA, onChanged: (v) {}, activeColor: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key, color: Colors.white38),
            title: const Text('Change Access Key', style: TextStyle(color: Colors.white, fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          ),
        ],
      ),
    );
  }
}

class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const _WebTopNavbar({this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Color(0xFF111417), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          Expanded(
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                // In a real app, this would use a dedicated Bloc for global account info
                // For now we just show a placeholder or link it to Profile state if available
                return const Text('KINETIC QUANT SYSTEM ONLINE', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1));
              },
            ),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
