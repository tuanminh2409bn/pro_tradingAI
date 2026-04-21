import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/journal_models.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/journal_bloc.dart';
import '../bloc/journal_event.dart';
import '../bloc/journal_state.dart';

class JournalWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const JournalWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => JournalBloc(
        journalRepository: context.read<JournalRepository>(),
      )..add(LoadJournalData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<JournalBloc, JournalState>(
          builder: (context, state) {
            if (state is JournalLoading || state is JournalInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is JournalError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is JournalLoaded) {
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
                              _buildMetricsGrid(state.stats, isMobile),
                              const SizedBox(height: 24),
                              if (isMobile) ...[
                                _buildEquityCurveCard(state.stats.equityData),
                                const SizedBox(height: 24),
                                _buildAIInsightsCard(),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: _buildEquityCurveCard(state.stats.equityData)),
                                    const SizedBox(width: 24),
                                    Expanded(flex: 1, child: _buildAIInsightsCard()),
                                  ],
                                ),
                              const SizedBox(height: 24),
                              _buildHeatmapCard(isMobile),
                              const SizedBox(height: 24),
                              _buildTradeLogTable(state.trades, isMobile),
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
          'Performance Analytics',
          style: TextStyle(fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          'Real-time trading performance & behavioral insights.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: isMobile ? 12 : 14),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(JournalStats stats, bool isMobile) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: isMobile ? 1.5 : 2.2,
      children: [
        _buildMetricCard('TOTAL NET PROFIT', '+\$${stats.totalProfit}', trend: '+12.5%', isPositive: true),
        _buildMetricCard('WIN RATE', '${stats.winRate}%', hasGauge: true),
        _buildMetricCard('PROFIT FACTOR', '${stats.profitFactor}', hasProgress: true),
        _buildMetricCard('AVG R:R RATIO', stats.rrRatio, subtitle: 'ABOVE TARGET'),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, {String? trend, bool isPositive = true, bool hasGauge = false, bool hasProgress = false, String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isPositive && trend != null ? AppColors.primary : Colors.white,
                    ),
                  ),
                ),
                if (trend != null) ...[
                  const SizedBox(height: 2),
                  Text(trend, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold)),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold)),
                ]
              ],
            ),
          ),
          if (hasGauge) ...[
            const SizedBox(width: 4),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
              ),
              child: Center(
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      value.contains('%') ? value : '64%', 
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEquityCurveCard(List<double> equityData) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EQUITY GROWTH CURVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          const Spacer(),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(painter: _EquityPainter(data: equityData)),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('START', style: TextStyle(fontSize: 9, color: Colors.white24)),
              Text('CURRENT', style: TextStyle(fontSize: 9, color: Colors.white24)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsightsCard() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.smart_toy, color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Text('AI PERFORMANCE INSIGHT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 16),
          const Expanded(
            child: Text(
              '"You are currently showing 12% higher profit variance during the NY open. Suggest waiting for 5-min candle confirmation."',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          const Text('PSYCHOLOGY SCORE', style: TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const _ProgressBar(label: 'DISCIPLINE', value: 0.88, color: AppColors.primary),
          const SizedBox(height: 12),
          const _ProgressBar(label: 'RISK ADHERENCE', value: 0.94, color: AppColors.secondary),
        ],
      ),
    );
  }

  Widget _buildHeatmapCard(bool isMobile) {
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
          const Text('ERROR & LOSS DENSITY HEATMAP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54)),
          const SizedBox(height: 24),
          Row(
            children: [
              const Column(
                children: [
                  Text('MON', style: TextStyle(fontSize: 9, color: Colors.white24)),
                  SizedBox(height: 10),
                  Text('FRI', style: TextStyle(fontSize: 9, color: Colors.white24)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobile ? 12 : 24,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: isMobile ? 12 * 5 : 24 * 5,
                  itemBuilder: (context, index) {
                    bool isHighRisk = index % 7 == 0 || index % 13 == 0;
                    return Container(
                      decoration: BoxDecoration(
                        color: isHighRisk ? AppColors.bear.withOpacity(0.4) : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradeLogTable(List<TradeRecord> trades, bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('GLOBAL TRADE LOG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                if (!isMobile)
                  Row(
                    children: [
                      _buildTableBtn('EXPORT CSV'),
                      const SizedBox(width: 8),
                      _buildTableBtn('FILTER'),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: isMobile ? 600 : 0),
              child: _TradeTable(trades: trades),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70)),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ProgressBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54)),
            Text('${(value * 100).toInt()}%', style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: value, color: color, backgroundColor: Colors.white.withOpacity(0.05), minHeight: 2),
      ],
    );
  }
}

class _EquityPainter extends CustomPainter {
  final List<double> data;
  _EquityPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF3772FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    double minVal = data.reduce(math.min);
    double maxVal = data.reduce(math.max);
    double range = maxVal - minVal;
    if (range == 0) range = 1;

    double dx = size.width / (data.length - 1);
    
    for (int i = 0; i < data.length; i++) {
      double x = i * dx;
      double y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _TradeTable extends StatelessWidget {
  final List<TradeRecord> trades;
  const _TradeTable({required this.trades});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
      },
      children: [
        _buildRow(['SYMBOL', 'ACTION', 'SIZE', 'ENTRY', 'EXIT', 'NET P/L'], isHeader: true),
        ...trades.map((trade) => _buildRow([
          trade.symbol,
          trade.action,
          '${trade.lotSize} Lots',
          trade.entryPrice.toStringAsFixed(2),
          trade.exitPrice.toStringAsFixed(2),
          '${trade.netProfit >= 0 ? '+' : ''}\$${trade.netProfit.toStringAsFixed(2)}',
        ], isPositive: trade.netProfit >= 0)),
      ],
    );
  }

  TableRow _buildRow(List<String> cells, {bool isHeader = false, bool? isPositive}) {
    return TableRow(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      children: cells.map((cell) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            cell,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: isHeader ? 9 : 11,
              fontWeight: isHeader ? FontWeight.w900 : FontWeight.normal,
              color: isHeader ? Colors.white38 : (cell.contains('\$') && isPositive != null ? (isPositive ? AppColors.primary : AppColors.bear) : Colors.white70),
            ),
          ),
        );
      }).toList(),
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
