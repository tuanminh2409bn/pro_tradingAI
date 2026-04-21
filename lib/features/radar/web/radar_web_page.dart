import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'dart:ui';
import '../../../core/constants/colors.dart';
import '../../../data/models/radar_models.dart';
import '../../../data/repositories/radar_repository.dart';
import '../bloc/radar_bloc.dart';
import '../bloc/radar_event.dart';
import '../bloc/radar_state.dart';

class RadarWebPage extends StatelessWidget {
  const RadarWebPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RadarBloc(
        radarRepository: context.read<RadarRepository>(),
      )..add(LoadRadarData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<RadarBloc, RadarState>(
          builder: (context, state) {
            if (state is RadarLoading || state is RadarInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is RadarError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is RadarLoaded) {
              return Column(
                children: [
                  const _WebTopNavbar(),
                  _buildFilterHeader(context, state),
                  Expanded(
                    child: Row(
                      children: [
                        // Radar Grid
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.4,
                            ),
                            itemCount: state.assets.length,
                            itemBuilder: (context, index) {
                              final asset = state.assets[index];
                              return InkWell(
                                onTap: () => context.read<RadarBloc>().add(SelectAsset(asset)),
                                child: _RadarAssetCard(
                                  asset: asset,
                                  isSelected: state.selectedAsset?.symbol == asset.symbol,
                                ),
                              );
                            },
                          ),
                        ),
                        // Detail Sidebar
                        if (state.selectedAsset != null)
                          _RadarDetailSidebar(asset: state.selectedAsset!),
                      ],
                    ),
                  ),
                  const _WebTickerFooter(),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context, RadarLoaded state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.3), border: const Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GLOBAL MARKET SCREENER', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), Text('REAL-TIME RADAR MONITORING', style: TextStyle(fontSize: 8, color: Colors.white38, fontWeight: FontWeight.bold))]),
          Row(
            children: [
              _buildFilterChip('VOLUME ANOMALY', Icons.analytics, AppColors.secondary),
              const SizedBox(width: 12),
              _buildFilterChip('DEEPSEEK AI CONFIRMATION', Icons.psychology, AppColors.primary),
              const SizedBox(width: 24),
              const VerticalDivider(color: Colors.white10, indent: 8, endIndent: 8),
              const SizedBox(width: 24),
              Row(
                children: [
                  const Text('PUSH ALERTS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38)),
                  const SizedBox(width: 8),
                  Switch(
                    value: state.alertsEnabled,
                    onChanged: (val) => context.read<RadarBloc>().add(ToggleRadarAlert(val)),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [Icon(icon, color: color, size: 14), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70))]),
    );
  }
}

class _RadarAssetCard extends StatelessWidget {
  final RadarAsset asset;
  final bool isSelected;
  const _RadarAssetCard({required this.asset, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    bool isHighVol = asset.volatilityStatus == 'HIGH';
    Color mainColor = asset.changePercent >= 0 ? AppColors.primary : AppColors.bear;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? mainColor.withOpacity(0.05) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? mainColor : (isHighVol ? mainColor.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(asset.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Colors.white)),
                  if (isHighVol) ...[const SizedBox(width: 8), Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: mainColor, boxShadow: [BoxShadow(color: mainColor, blurRadius: 4)]))],
                ],
              ),
              Text('${asset.changePercent > 0 ? '+' : ''}${asset.changePercent}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: mainColor)),
            ],
          ),
          Text(asset.fullName.toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('\$${asset.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 12),
          if (asset.hasAiConfirmation)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.psychology, size: 10, color: AppColors.primary), SizedBox(width: 4), Text('DEEPSEEK CONFIRMED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary))]),
            ),
        ],
      ),
    );
  }
}

class _RadarDetailSidebar extends StatelessWidget {
  final RadarAsset asset;
  const _RadarDetailSidebar({required this.asset});

  @override
  Widget build(BuildContext context) {
    Color mainColor = asset.changePercent >= 0 ? AppColors.primary : AppColors.bear;

    return Container(
      width: 320,
      decoration: BoxDecoration(color: AppColors.surface.withOpacity(0.5), border: const Border(left: BorderSide(color: Colors.white10))),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('ASSET DETAIL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)), IconButton(onPressed: () {}, icon: const Icon(Icons.close, size: 16, color: Colors.white24))]),
          const SizedBox(height: 32),
          Text(asset.symbol, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          Row(children: [Text('${asset.changePercent > 0 ? '+' : ''}${asset.changePercent}% TODAY', style: TextStyle(color: mainColor, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(width: 12), if (asset.hasAiConfirmation) Text('RADAR ALERT', style: TextStyle(color: mainColor, fontSize: 9, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 32),
          _buildDetailBox('SIGNAL STRENGTH', Row(children: [for(int i=0; i<4; i++) Container(margin: const EdgeInsets.only(right: 4), width: 16, height: 4, decoration: BoxDecoration(color: mainColor, borderRadius: BorderRadius.circular(2))), Container(width: 16, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))] )),
          const SizedBox(height: 16),
          _buildDetailBox('AI SENTIMENT (DEEPSEEK)', Text(
            asset.aiSignal == 'BUY' 
                ? '"High probability breakout identified. Volume confirming accumulation zone. Targeted upside: +2.5%."'
                : asset.aiSignal == 'SELL'
                    ? '"Bearish momentum increasing. Distribution pattern detected near resistance. Suggest caution on longs."'
                    : '"Market consolidating. AI neural networks awaiting clear structural breakout."',
            style: const TextStyle(fontSize: 11, color: Colors.white70, fontStyle: FontStyle.italic, height: 1.4),
          )),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _buildTradeBtn('BUY', AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _buildTradeBtn('SELL', AppColors.bear)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailBox(String label, Widget content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF0b0e11), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1)), const SizedBox(height: 12), content]),
    );
  }

  Widget _buildTradeBtn(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))),
    );
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
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
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
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TickerItem('XAUUSD: 2042.12', AppColors.primary),
          SizedBox(width: 32),
          _TickerItem('BTCUSD: 64210.50', AppColors.bear),
          SizedBox(width: 32),
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
