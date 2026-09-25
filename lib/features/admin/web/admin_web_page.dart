import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/models/admin_models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AdminWebPage extends StatelessWidget {
  const AdminWebPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          AdminBloc(adminRepository: context.read<AdminRepository>())
            ..add(LoadAdminData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocConsumer<AdminBloc, AdminState>(
          listenWhen: (previous, current) =>
              previous is AdminLoaded &&
              current is AdminLoaded &&
              previous.actionResultNonce != current.actionResultNonce,
          listener: (context, state) {
            if (state is! AdminLoaded || state.actionMessageKey.isEmpty) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr(state.actionMessageKey)),
                backgroundColor: state.actionSucceeded
                    ? AppColors.primary
                    : AppColors.bear,
              ),
            );
          },
          builder: (context, state) {
            if (state is AdminLoading || state is AdminInitial) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (state is AdminError) {
              return Center(
                child: Text(
                  context.tr(state.message),
                  style: const TextStyle(color: AppColors.bear),
                ),
              );
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
                          // ── Header ──────────────────────────────────────
                          _buildHeader(state.stats, state.serviceStatuses),
                          const SizedBox(height: 24),

                          // ── KPI Cards (NEW) ──────────────────────────────
                          _buildKpiCards(
                            context,
                            state.stats,
                            state.tradingEnabled,
                          ),
                          const SizedBox(height: 24),

                          // ── Analytics Hub + Global Access ────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 8,
                                child: _AnalyticsHub(
                                  stats: state.stats,
                                  dailyStats: state.dailyStats,
                                ),
                              ),
                              const SizedBox(width: 24),
                              const Expanded(
                                flex: 4,
                                child: _GlobalAccessCard(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Services Status (NEW) ────────────────────────
                          _buildServicesStatus(state.serviceStatuses),
                          const SizedBox(height: 24),

                          // ── Global Risk Config (NEW) ─────────────────────
                          _buildGlobalRiskConfig(context, state.globalRisk),
                          const SizedBox(height: 24),

                          // ── Pending Approvals + Radar Config ─────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _buildPendingApprovals(
                                  context,
                                  state.requests,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 5,
                                child: _RadarConfig(
                                  config: state.radarConfig,
                                  isLoaded: state.radarConfigLoaded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── AI Config ────────────────────────────────────
                          _AIConfigCard(
                            aiConfig: state.aiConfig,
                            isSaving: state.aiConfigSaving,
                            isLoaded: state.aiConfigLoaded,
                          ),
                          const SizedBox(height: 24),

                          // ── Signal Blast ─────────────────────────────────
                          const _SignalBlastPanel(),
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

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(SystemStats stats, List<ServiceStatus> services) {
    final systemStatus = services.isEmpty
        ? 'UNAVAILABLE'
        : '${services.where((service) => service.isOnline).length}/${services.length} ONLINE';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ADMIN CONTROL CENTER',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            Text(
              'Operational oversight and system configuration.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _buildHeaderStat('SYSTEM STATUS', systemStatus, AppColors.primary),
            const SizedBox(width: 16),
            _buildHeaderStat(
              'PENDING ALERTS',
              stats.isAvailable ? '${stats.pendingAlerts}' : '—',
              AppColors.secondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderStat(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ─── KPI Cards (NEW) ──────────────────────────────────────────────────────

  Widget _buildKpiCards(
    BuildContext context,
    SystemStats stats,
    bool tradingEnabled,
  ) {
    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            'ACTIVE USERS',
            stats.isAvailable ? '${stats.dau}' : '—',
            Icons.people,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            'TRADES 24H',
            stats.isAvailable ? '${stats.totalTrades}' : '—',
            Icons.swap_horiz,
            AppColors.secondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            'GLOBAL P&L',
            !stats.isAvailable
                ? '—'
                : stats.globalPnl >= 0
                ? '+\$${stats.globalPnl.toStringAsFixed(0)}'
                : '-\$${stats.globalPnl.abs().toStringAsFixed(0)}',
            Icons.trending_up,
            !stats.isAvailable
                ? Colors.white38
                : stats.globalPnl >= 0
                ? Colors.green
                : AppColors.bear,
          ),
        ),
        const SizedBox(width: 16),
        // Kill Switch card
        Expanded(
          child: GestureDetector(
            onTap: () => _showKillSwitchDialog(context, tradingEnabled),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: tradingEnabled
                    ? AppColors.bear.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: tradingEnabled
                      ? AppColors.bear.withValues(alpha: 0.4)
                      : Colors.green.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    tradingEnabled ? Icons.power_settings_new : Icons.power_off,
                    color: tradingEnabled ? AppColors.bear : Colors.green,
                    size: 24,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tradingEnabled ? 'KILL SWITCH' : 'TRADING PAUSED',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tradingEnabled ? 'PAUSE ALL' : 'RESUME ALL',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: tradingEnabled ? AppColors.bear : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showKillSwitchDialog(BuildContext context, bool currentlyEnabled) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          currentlyEnabled ? '⚠ PAUSE ALL TRADING?' : '▶ RESUME ALL TRADING?',
          style: TextStyle(
            color: currentlyEnabled ? AppColors.bear : Colors.green,
          ),
        ),
        content: Text(
          currentlyEnabled
              ? 'This will immediately stop all trading signals and block new trade executions for ALL users.'
              : 'This will re-enable trading signals and trade executions for all users.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyEnabled ? AppColors.bear : Colors.green,
            ),
            onPressed: () {
              context.read<AdminBloc>().add(
                ToggleKillSwitch(!currentlyEnabled),
              );
              Navigator.pop(ctx);
            },
            child: Text(
              currentlyEnabled ? 'PAUSE ALL' : 'RESUME ALL',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Services Status (NEW) ────────────────────────────────────────────────

  Widget _buildServicesStatus(List<ServiceStatus> services) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart, color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Text(
                'SERVICES STATUS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (services.isEmpty)
            const Text(
              'SERVICE HEALTH DATA UNAVAILABLE',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            )
          else
            Row(
              children: services.map((svc) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: svc.isOnline
                          ? Colors.green.withValues(alpha: 0.05)
                          : AppColors.bear.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: svc.isOnline
                            ? Colors.green.withValues(alpha: 0.2)
                            : AppColors.bear.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              color: svc.isOnline
                                  ? Colors.green
                                  : AppColors.bear,
                              size: 8,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              svc.isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: svc.isOnline
                                    ? Colors.green
                                    : AppColors.bear,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          svc.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${svc.latencyMs}ms',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ─── Global Risk Config (NEW) ─────────────────────────────────────────────

  Widget _buildGlobalRiskConfig(BuildContext context, GlobalRiskConfig config) {
    return _GlobalRiskCard(config: config);
  }

  // ─── Pending Approvals ────────────────────────────────────────────────────

  Widget _buildPendingApprovals(
    BuildContext context,
    List<PendingRequest> requests,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PENDING APPROVALS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          if (requests.isEmpty)
            const Text(
              'NO PENDING REQUESTS',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            )
          else
            ...requests.map((req) => _buildApprovalRow(context, req)),
        ],
      ),
    );
  }

  Widget _buildApprovalRow(BuildContext context, PendingRequest req) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                req.username,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              Text(
                req.type,
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            req.amount,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    context.read<AdminBloc>().add(HandleRequest(req.id, true)),
                icon: const Icon(
                  Icons.check,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              IconButton(
                onPressed: () =>
                    context.read<AdminBloc>().add(HandleRequest(req.id, false)),
                icon: const Icon(Icons.close, color: AppColors.bear, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlobalRiskCard — StatefulWidget
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalRiskCard extends StatefulWidget {
  final GlobalRiskConfig config;
  const _GlobalRiskCard({required this.config});

  @override
  State<_GlobalRiskCard> createState() => _GlobalRiskCardState();
}

class _GlobalRiskCardState extends State<_GlobalRiskCard> {
  late String _leverage;
  late bool _newsGuard;
  late double _maxDrawdown;

  @override
  void initState() {
    super.initState();
    _leverage = widget.config.maxLeverage;
    _newsGuard = widget.config.newsGuardEnabled;
    _maxDrawdown = widget.config.maxDrawdownPct;
  }

  @override
  void didUpdateWidget(covariant _GlobalRiskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _leverage = widget.config.maxLeverage;
      _newsGuard = widget.config.newsGuardEnabled;
      _maxDrawdown = widget.config.maxDrawdownPct;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.isAvailable) {
      return Container(
        height: 180,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text(
          'GLOBAL RISK CONFIGURATION UNAVAILABLE',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield, color: AppColors.secondary, size: 16),
              SizedBox(width: 8),
              Text(
                'GLOBAL RISK CONFIG',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              // Leverage selector
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MAX ACCOUNT LEVERAGE',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['1:100', '1:500', '1:1000'].map((lev) {
                        final selected = _leverage == lev;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _leverage = lev),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.secondary.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.secondary
                                      : Colors.white10,
                                ),
                              ),
                              child: Text(
                                lev,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.secondary
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // News guard toggle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HIGH IMPACT NEWS GUARD',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tự động tăng Spread / Block trade trước tin đỏ',
                      style: TextStyle(fontSize: 10, color: Colors.white24),
                    ),
                    const SizedBox(height: 8),
                    Switch(
                      value: _newsGuard,
                      onChanged: (v) => setState(() => _newsGuard = v),
                      activeThumbColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // Max drawdown slider
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MAX DRAWDOWN DAILY: ${_maxDrawdown.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: _maxDrawdown,
                      min: 1,
                      max: 20,
                      divisions: 19,
                      activeColor: AppColors.bear,
                      inactiveColor: Colors.white10,
                      onChanged: (v) => setState(() => _maxDrawdown = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                context.read<AdminBloc>().add(
                  SaveGlobalRisk(
                    GlobalRiskConfig(
                      maxLeverage: _leverage,
                      newsGuardEnabled: _newsGuard,
                      maxDrawdownPct: _maxDrawdown,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.secondary, Color(0xFF4B0082)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SAVE RISK CONFIG',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AnalyticsHub — StatefulWidget with real LineChart
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsHub extends StatefulWidget {
  final SystemStats stats;
  final List<Map<String, dynamic>> dailyStats;
  const _AnalyticsHub({required this.stats, required this.dailyStats});

  @override
  State<_AnalyticsHub> createState() => _AnalyticsHubState();
}

class _AnalyticsHubState extends State<_AnalyticsHub> {
  bool _showDau = true;

  @override
  Widget build(BuildContext context) {
    final dataPoints = widget.dailyStats
        .map((row) => ((row[_showDau ? 'dau' : 'mau'] as num?) ?? 0).toDouble())
        .toList(growable: false);
    final labels = widget.dailyStats
        .map((row) => (row['date'] ?? '').toString())
        .toList(growable: false);
    final activeColor = _showDau ? AppColors.primary : AppColors.secondary;

    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ANALYTICS HUB',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white54,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _showDau = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _showDau
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'DAU',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: _showDau
                                ? AppColors.primary
                                : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showDau = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: !_showDau
                              ? AppColors.secondary.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'MAU',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: !_showDau
                                ? AppColors.secondary
                                : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          Expanded(
            child: dataPoints.isEmpty
                ? const Center(
                    child: Text(
                      'ANALYTICS DATA UNAVAILABLE',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval:
                            (dataPoints.reduce((a, b) => a > b ? a : b) / 4)
                                .clamp(1, 1000000),
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Colors.white.withValues(alpha: 0.05),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (val, meta) {
                              final idx = val.toInt();
                              if (idx < 0 || idx >= labels.length) {
                                return const SizedBox();
                              }
                              final label = labels[idx];
                              return Text(
                                label.length >= 5
                                    ? label.substring(label.length - 5)
                                    : label,
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 9,
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (val, meta) => Text(
                              '${val.toInt()}',
                              style: const TextStyle(
                                color: Colors.white24,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: dataPoints
                              .asMap()
                              .entries
                              .map((e) => FlSpot(e.key.toDouble(), e.value))
                              .toList(),
                          isCurved: true,
                          color: activeColor,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                                  radius: 3,
                                  color: activeColor,
                                  strokeWidth: 0,
                                ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                activeColor.withValues(alpha: 0.2),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(
                label: 'GROWTH',
                val: widget.stats.isAvailable
                    ? '+${widget.stats.growth}%'
                    : '—',
                color: AppColors.primary,
              ),
              _StatItem(
                label: 'SESSIONS',
                val: widget.stats.isAvailable
                    ? '${widget.stats.dau} / min'
                    : '—',
              ),
              _StatItem(
                label: 'LATENCY',
                val: widget.stats.isAvailable
                    ? '${widget.stats.latency}ms'
                    : '—',
                color: AppColors.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RadarConfig — StatefulWidget
// ─────────────────────────────────────────────────────────────────────────────

class _RadarConfig extends StatefulWidget {
  final RadarAdminConfig? config;
  final bool isLoaded;
  const _RadarConfig({required this.config, required this.isLoaded});

  @override
  State<_RadarConfig> createState() => _RadarConfigState();
}

class _RadarConfigState extends State<_RadarConfig> {
  double _sensitivity = 0;
  final List<String> _watchlist = [];
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _applyConfig(widget.config);
  }

  @override
  void didUpdateWidget(covariant _RadarConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _applyConfig(widget.config);
  }

  void _applyConfig(RadarAdminConfig? config) {
    if (config == null) return;
    _watchlist
      ..clear()
      ..addAll(config.symbols);
    _sensitivity = config.sensitivity;
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoaded) {
      return _buildUnavailableCard(
        const CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (widget.config == null) {
      return _buildUnavailableCard(
        const Text(
          'RADAR CONFIGURATION UNAVAILABLE',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RADAR CONFIGURATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'GLOBAL WATCHLIST ASSETS',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white24,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._watchlist.map(
                (s) => Chip(
                  label: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: Colors.white10,
                  side: BorderSide.none,
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 12,
                    color: Colors.white38,
                  ),
                  onDeleted: () => setState(() => _watchlist.remove(s)),
                ),
              ),
              // Add symbol button
              ActionChip(
                label: const Icon(
                  Icons.add,
                  size: 12,
                  color: AppColors.primary,
                ),
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                onPressed: () => _showAddSymbolDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SYSTEM SENSITIVITY',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white24,
                ),
              ),
              Text(
                '${(_sensitivity * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _sensitivity,
            onChanged: (v) => setState(() => _sensitivity = v),
            activeColor: AppColors.primary,
            inactiveColor: Colors.white10,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONSERVATIVE',
                style: TextStyle(fontSize: 8, color: Colors.white24),
              ),
              Text(
                'AGGRESSIVE',
                style: TextStyle(fontSize: 8, color: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                context.read<AdminBloc>().add(
                  SaveRadarConfig(_watchlist, _sensitivity),
                );
              },
              child: const Text(
                'SAVE CONFIG',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableCard(Widget child) {
    return Container(
      height: 260,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  void _showAddSymbolDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add Symbol', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _addCtrl,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Symbol (e.g. GBPUSD)',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final sym = _addCtrl.text.trim().toUpperCase();
              if (sym.isNotEmpty && !_watchlist.contains(sym)) {
                setState(() => _watchlist.add(sym));
                _addCtrl.clear();
              }
              Navigator.pop(ctx);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TierSelector — StatefulWidget with real DropdownButton
// ─────────────────────────────────────────────────────────────────────────────

class _TierSelector extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _TierSelector({required this.onChanged});

  @override
  State<_TierSelector> createState() => _TierSelectorState();
}

class _TierSelectorState extends State<_TierSelector> {
  String _selected = 'All Users';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0b0e11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: _selected,
        dropdownColor: AppColors.surface,
        underline: const SizedBox(),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        icon: const Icon(Icons.expand_more, size: 16, color: Colors.white24),
        isExpanded: true,
        items: const [
          DropdownMenuItem(
            value: 'All Users',
            child: Text('All Users (Global)'),
          ),
          DropdownMenuItem(value: 'FREE', child: Text('FREE Tier')),
          DropdownMenuItem(value: 'VIP', child: Text('VIP Tier')),
          DropdownMenuItem(value: 'ENTERPRISE', child: Text('Enterprise')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _selected = v);
            widget.onChanged(v);
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SignalBlastPanel — StatefulWidget
// ─────────────────────────────────────────────────────────────────────────────

class _SignalBlastPanel extends StatefulWidget {
  const _SignalBlastPanel();

  @override
  State<_SignalBlastPanel> createState() => _SignalBlastPanelState();
}

class _SignalBlastPanelState extends State<_SignalBlastPanel> {
  String _selectedTier = 'All Users';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.broadcast_on_home,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'SIGNAL BLAST',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Send high-priority notifications to specific user tiers.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                const SizedBox(height: 24),
                const Text(
                  'TARGET TIER',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white24,
                  ),
                ),
                const SizedBox(height: 8),
                _TierSelector(
                  onChanged: (tier) => setState(() => _selectedTier = tier),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'MESSAGE CONTENT',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white24,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    fillColor: const Color(0xFF0b0e11),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'Enter broadcast message...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.15),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (_controller.text.isNotEmpty) {
                      context.read<AdminBloc>().add(
                        BroadcastRequested(_controller.text, _selectedTier),
                      );
                      _controller.clear();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.secondary, Color(0xFF004b00)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'BROADCAST NOW',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _GlobalAccessCard
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalAccessCard extends StatelessWidget {
  const _GlobalAccessCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GLOBAL ACCESS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.public_off, color: Colors.white24, size: 64),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'REGIONAL ACCESS DATA UNAVAILABLE',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatItem
// ─────────────────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String label;
  final String val;
  final Color color;
  const _StatItem({
    required this.label,
    required this.val,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          val,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WebTopNavbar
// ─────────────────────────────────────────────────────────────────────────────

class _WebTopNavbar extends StatelessWidget {
  const _WebTopNavbar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 40),
          const Text(
            'ADMIN PANEL v2.1',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AIConfigCard — StatefulWidget (unchanged logic, kept intact)
// ─────────────────────────────────────────────────────────────────────────────

class _AIConfigCard extends StatefulWidget {
  final AIConfig? aiConfig;
  final bool isSaving;
  final bool isLoaded;

  const _AIConfigCard({
    required this.aiConfig,
    required this.isSaving,
    required this.isLoaded,
  });

  @override
  State<_AIConfigCard> createState() => _AIConfigCardState();
}

class _AIConfigCardState extends State<_AIConfigCard> {
  late TextEditingController _promptController;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    final initialText = widget.aiConfig?.masterPrompt ?? '';
    _promptController = TextEditingController(text: initialText);
    _charCount = initialText.length;
    _promptController.addListener(() {
      setState(() {
        _charCount = _promptController.text.length;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _AIConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.aiConfig != oldWidget.aiConfig && widget.aiConfig != null) {
      final newText = widget.aiConfig!.masterPrompt;
      if (_promptController.text != newText) {
        _promptController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoaded) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (widget.aiConfig == null) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text(
          'AI CONFIGURATION UNAVAILABLE',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI CONFIGURATION ENGINE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Master Prompt controls all AI analysis logic',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
              if (widget.aiConfig?.lastUpdatedAt != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Last updated: ${_formatDate(widget.aiConfig!.lastUpdatedAt!)}',
                    style: const TextStyle(fontSize: 10, color: Colors.white24),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Label
          const Text(
            'MASTER PROMPT',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white24,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),

          // TextFormField
          TextFormField(
            controller: _promptController,
            maxLines: 8,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.6,
            ),
            decoration: InputDecoration(
              fillColor: const Color(0xFF0b0e11),
              filled: true,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
              hintText: 'Enter the AI master prompt...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.15),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Character count
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_charCount characters',
              style: const TextStyle(fontSize: 10, color: Colors.white24),
            ),
          ),
          const SizedBox(height: 20),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Reset button
              TextButton.icon(
                onPressed: widget.isSaving
                    ? null
                    : () {
                        _promptController.text =
                            widget.aiConfig?.masterPrompt ?? '';
                      },
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text(
                  'REVERT CHANGES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.white38),
              ),

              // Save button
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.isSaving
                    ? null
                    : () {
                        if (_promptController.text.trim().isNotEmpty) {
                          context.read<AdminBloc>().add(
                            SaveAIConfig(_promptController.text.trim()),
                          );
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.isSaving
                          ? [Colors.white12, Colors.white10]
                          : [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.7),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: widget.isSaving
                        ? []
                        : [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: widget.isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.save, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'SAVE & APPLY',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
