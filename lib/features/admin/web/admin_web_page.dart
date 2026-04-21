import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'dart:ui';
import '../../../core/constants/colors.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';

class AdminWebPage extends StatelessWidget {
  const AdminWebPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AdminBloc(
        adminRepository: context.read<AdminRepository>(),
      )..add(LoadAdminData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<AdminBloc, AdminState>(
          builder: (context, state) {
            if (state is AdminLoading || state is AdminInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is AdminError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is AdminLoaded) {
              return Column(
                children: [
                  const _WebTopNavbar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(state.stats),
                          const SizedBox(height: 32),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 8, child: _buildAnalyticsHub(state.stats)),
                              const SizedBox(width: 24),
                              Expanded(flex: 4, child: const _GlobalAccessCard()),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: _buildPendingApprovals(context, state.requests)),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: const _RadarConfig()),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildSignalBlast(context),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(SystemStats stats) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('ADMIN CONTROL CENTER', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)), Text('Operational oversight and system configuration.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14))]),
        Row(
          children: [
            _buildHeaderStat('SYSTEM STATUS', 'ACTIVE - 60 FPS', AppColors.primary),
            const SizedBox(width: 16),
            _buildHeaderStat('PENDING ALERTS', '${stats.pendingAlerts}', AppColors.secondary),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderStat(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: color, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38)), const SizedBox(height: 4), Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))]),
    );
  }

  Widget _buildAnalyticsHub(SystemStats stats) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ANALYTICS HUB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)), Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)), child: const Row(children: [Text(' DAU ', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)), Text(' MAU ', style: TextStyle(fontSize: 8, color: Colors.white24))]))]),
          const Spacer(),
          const Center(child: Icon(Icons.show_chart, color: AppColors.primary, size: 120)),
          const Spacer(),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(label: 'GROWTH', val: '+${stats.growth}%', color: AppColors.primary),
              _StatItem(label: 'SESSIONS', val: '${stats.dau} / min'),
              _StatItem(label: 'LATENCY', val: '${stats.latency}ms', color: AppColors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApprovals(BuildContext context, List<PendingRequest> requests) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PENDING APPROVALS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)), Text('VIEW ALL', style: TextStyle(fontSize: 8, color: AppColors.primary, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 24),
          ...requests.map((req) => _buildApprovalRow(context, req)),
        ],
      ),
    );
  }

  Widget _buildApprovalRow(BuildContext context, PendingRequest req) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.02)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(req.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)), Text(req.type, style: const TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold))]),
          Text(req.amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          Row(children: [IconButton(onPressed: () => context.read<AdminBloc>().add(HandleRequest(req.userId, true)), icon: const Icon(Icons.check, color: AppColors.primary, size: 18)), IconButton(onPressed: () => context.read<AdminBloc>().add(HandleRequest(req.userId, false)), icon: const Icon(Icons.close, color: AppColors.bear, size: 18))]),
        ],
      ),
    );
  }

  Widget _buildSignalBlast(BuildContext context) {
    final controller = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.broadcast_on_home, color: AppColors.primary, size: 18), SizedBox(width: 12), Text('SIGNAL BLAST', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))]),
                SizedBox(height: 8),
                Text('Send high-priority notifications to specific user tiers.', style: TextStyle(fontSize: 12, color: Colors.white38)),
                SizedBox(height: 24),
                Text('TARGET TIER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white24)),
                SizedBox(height: 8),
                _TierSelector(),
              ],
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('MESSAGE CONTENT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white24)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 3, 
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(fillColor: const Color(0xFF0b0e11), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    if (controller.text.isNotEmpty) {
                      context.read<AdminBloc>().add(BroadcastRequested(controller.text, 'Global'));
                      controller.clear();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast sent!'), backgroundColor: AppColors.primary));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12), 
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.secondary, Color(0xFF004b00)]), borderRadius: BorderRadius.circular(8)), 
                    child: const Text('BROADCAST NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11))
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierSelector extends StatelessWidget {
  const _TierSelector();
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF0b0e11), borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('All Users (Global)', style: TextStyle(fontSize: 12, color: Colors.white)), Icon(Icons.expand_more, size: 16, color: Colors.white24)]));
  }
}

class _RadarConfig extends StatelessWidget {
  const _RadarConfig();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RADAR CONFIGURATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          const SizedBox(height: 24),
          const Text('GLOBAL WATCHLIST ASSETS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white24)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: ['XAUUSD', 'BTCUSD', 'EURUSD'].map((s) => Chip(label: Text(s, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.white10, side: BorderSide.none)).toList()),
          const SizedBox(height: 32),
          const Text('SYSTEM SENSITIVITY', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white24)),
          Slider(value: 0.7, onChanged: (v) {}, activeColor: AppColors.primary, inactiveColor: Colors.white10),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('CONSERVATIVE', style: TextStyle(fontSize: 8, color: Colors.white24)), Text('AGGRESSIVE', style: TextStyle(fontSize: 8, color: Colors.white24))]),
        ],
      ),
    );
  }
}

class _GlobalAccessCard extends StatelessWidget {
  const _GlobalAccessCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GLOBAL ACCESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          const SizedBox(height: 24),
          Expanded(child: Container(decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: const Center(child: Icon(Icons.public, color: AppColors.secondary, size: 80)))),
          const SizedBox(height: 24),
          _buildRegionBar('North America', 0.48),
          const SizedBox(height: 12),
          _buildRegionBar('Europe', 0.32),
        ],
      ),
    );
  }
  Widget _buildRegionBar(String label, double val) {
    return Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)), Text('${(val*100).toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))]), const SizedBox(height: 4), LinearProgressIndicator(value: val, color: AppColors.primary, backgroundColor: Colors.white10, minHeight: 2)]);
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String val;
  final Color color;
  const _StatItem({required this.label, required this.val, this.color = Colors.white});
  @override
  Widget build(BuildContext context) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38)), const SizedBox(height: 4), Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))]);
  }
}

class _WebTopNavbar extends StatelessWidget {
  const _WebTopNavbar();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Color(0xFF111417), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          const Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13)),
          const Spacer(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8))),
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications, color: Color(0xFFc3c6d8))),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}

class _WebTickerFooter extends StatelessWidget {
  const _WebTickerFooter();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: const Color(0xFF0b0e11),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TickerItem('XAUUSD: 2042.12', AppColors.primary),
          const SizedBox(width: 32),
          _TickerItem('BTCUSD: 64210.50', AppColors.bear),
          const SizedBox(width: 32),
          _TickerItem('EURUSD: 1.0821', Colors.white54),
        ],
      ),
    );
  }
}

class _TickerItem extends StatelessWidget {
  final String text;
  final Color color;
  const _TickerItem(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(Icons.trending_up, color: color, size: 14), const SizedBox(width: 4), Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))]);
  }
}
