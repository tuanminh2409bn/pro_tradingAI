import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/referral_models.dart';
import '../../../data/repositories/referral_repository.dart';
import '../bloc/referral_bloc.dart';
import '../bloc/referral_event.dart';
import '../bloc/referral_state.dart';

class ReferralWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const ReferralWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReferralBloc(
        referralRepository: context.read<ReferralRepository>(),
      )..add(LoadReferralData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<ReferralBloc, ReferralState>(
          builder: (context, state) {
            if (state is ReferralLoading || state is ReferralInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is ReferralError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is ReferralLoaded) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return Column(
                    children: [
                      _WebTopNavbar(onMenuPressed: onMenuPressed),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(isMobile),
                              const SizedBox(height: 32),
                              if (isMobile) ...[
                                _buildStatsCard(state.stats),
                                const SizedBox(height: 24),
                                _buildNetworkCard(state.network),
                                const SizedBox(height: 24),
                                _buildHistoryCard(state.history),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildStatsCard(state.stats),
                                          const SizedBox(height: 24),
                                          _buildHistoryCard(state.history),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 1,
                                      child: _buildNetworkCard(state.network),
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
          'Loyalty & Referrals',
          style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          'Earn commissions by inviting other professional traders.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 12 : 14),
        ),
      ],
    );
  }

  Widget _buildStatsCard(ReferralStats stats) {
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
          const Text('YOUR PERFORMANCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('TOTAL EARNINGS', '\$${stats.totalEarnings.toStringAsFixed(2)}', AppColors.primary),
              _buildStatItem('F1 MEMBERS', '${stats.f1Count}', Colors.white),
              _buildStatItem('F2 MEMBERS', '${stats.f2Count}', Colors.white),
            ],
          ),
          const SizedBox(height: 40),
          const Text('REFERRAL LINK', style: TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
            child: Row(
              children: [
                Expanded(child: Text(stats.referralLink, style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                const Icon(Icons.copy, color: AppColors.primary, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildNetworkCard(List<MemberNode> network) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('NETWORK HIERARCHY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (network.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: Text('No network members found.', style: TextStyle(color: Colors.white24, fontSize: 12))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: network.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final member = network[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  leading: CircleAvatar(backgroundColor: Colors.white12, radius: 16, child: Text(member.level, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary))),
                  title: Text(member.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('Contribution: \$${member.earningsContribution.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white12),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(List<RewardTransaction> history) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('REWARD TRANSACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: Text('No transaction history.', style: TextStyle(color: Colors.white24, fontSize: 12))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final tx = history[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Text(tx.title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text(tx.status, style: TextStyle(color: tx.status == 'COMPLETED' ? AppColors.primary : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                  trailing: Text('+\$${tx.amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                );
              },
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
          const Expanded(child: Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13), overflow: TextOverflow.ellipsis)),
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
