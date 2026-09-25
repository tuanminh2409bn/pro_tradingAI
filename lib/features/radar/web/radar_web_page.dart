import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/models/radar_models.dart';
import '../../../data/repositories/radar_repository.dart';
import '../bloc/radar_bloc.dart';
import '../bloc/radar_event.dart';
import '../bloc/radar_state.dart';
import '../../../logic/navigation_cubit.dart';

class RadarWebPage extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const RadarWebPage({super.key, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          RadarBloc(radarRepository: context.read<RadarRepository>())
            ..add(LoadRadarData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _WebTopNavbar(onMenuPressed: onMenuPressed),
            Expanded(
              child: BlocBuilder<RadarBloc, RadarState>(
                builder: (context, state) {
                  if (state is RadarLoading || state is RadarInitial) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (state is RadarError) {
                    return Center(
                      child: Text(
                        context.tr(state.message),
                        style: const TextStyle(color: AppColors.bear),
                      ),
                    );
                  }

                  if (state is RadarLoaded) {
                    return Column(
                      children: [
                        _buildFilterHeader(context, state),
                        Expanded(
                          child: Row(
                            children: [
                              // Radar Grid
                              Expanded(
                                child: state.assets.isEmpty
                                    ? Center(
                                        child: Text(
                                          context.tr('radar_data_unavailable'),
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : GridView.builder(
                                        padding: const EdgeInsets.all(24),
                                        gridDelegate:
                                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 300,
                                              mainAxisSpacing: 16,
                                              crossAxisSpacing: 16,
                                              childAspectRatio: 1.4,
                                            ),
                                        itemCount: state.assets.length,
                                        itemBuilder: (context, index) {
                                          final asset = state.assets[index];
                                          return InkWell(
                                            onTap: () => context
                                                .read<RadarBloc>()
                                                .add(SelectAsset(asset)),
                                            child: _RadarAssetCard(
                                              asset: asset,
                                              isSelected:
                                                  state.selectedAsset?.symbol ==
                                                  asset.symbol,
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              // Detail Sidebar
                              if (state.selectedAsset != null)
                                _RadarDetailSidebar(
                                  asset: state.selectedAsset!,
                                ),
                            ],
                          ),
                        ),
                        _WebTickerFooter(assets: state.assets),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context, RadarLoaded state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.3),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GLOBAL MARKET SCREENER',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'REAL-TIME RADAR MONITORING',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildFilterChip(
                'VOLUME ANOMALY',
                Icons.analytics,
                AppColors.secondary,
              ),
              const SizedBox(width: 12),
              _buildFilterChip(
                'DEEPSEEK AI CONFIRMATION',
                Icons.psychology,
                AppColors.primary,
              ),
              const SizedBox(width: 24),
              const VerticalDivider(
                color: Colors.white10,
                indent: 8,
                endIndent: 8,
              ),
              const SizedBox(width: 24),
              Row(
                children: [
                  const Text(
                    'PUSH ALERTS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: false,
                    onChanged: null,
                    activeThumbColor: AppColors.primary,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
        ],
      ),
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
    Color mainColor = asset.changePercent >= 0
        ? AppColors.primary
        : AppColors.bear;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? mainColor.withValues(alpha: 0.05)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? mainColor
              : (isHighVol
                    ? mainColor.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05)),
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
                  Text(
                    asset.symbol,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  if (isHighVol) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mainColor,
                        boxShadow: [BoxShadow(color: mainColor, blurRadius: 4)],
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '${asset.changePercent > 0 ? '+' : ''}${asset.changePercent}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: mainColor,
                ),
              ),
            ],
          ),
          Text(
            asset.fullName.toUpperCase(),
            style: const TextStyle(
              fontSize: 8,
              color: Colors.white24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            '\$${asset.price.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          if (asset.hasVerifiedAiConfirmation)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology, size: 10, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'DEEPSEEK CONFIRMED',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
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

class _RadarDetailSidebar extends StatelessWidget {
  final RadarAsset asset;
  const _RadarDetailSidebar({required this.asset});

  @override
  Widget build(BuildContext context) {
    Color mainColor = asset.changePercent >= 0
        ? AppColors.primary
        : AppColors.bear;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        border: const Border(left: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ASSET DETAIL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              IconButton(
                onPressed: () =>
                    context.read<RadarBloc>().add(ClearSelectedAsset()),
                icon: const Icon(Icons.close, size: 16, color: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            asset.symbol,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
            ),
          ),
          Row(
            children: [
              Text(
                '${asset.changePercent > 0 ? '+' : ''}${asset.changePercent}% TODAY',
                style: TextStyle(
                  color: mainColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              if (asset.hasVerifiedAiConfirmation)
                Text(
                  'RADAR ALERT',
                  style: TextStyle(
                    color: mainColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          _buildDetailBox(
            'SIGNAL STRENGTH',
            Row(
              children: [
                for (int i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(
                      color: mainColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Container(
                  width: 16,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailBox(
            asset.hasVerifiedAiConfirmation
                ? 'AI CONFIRMATION · ${asset.model}'
                : 'AI CONFIRMATION',
            Text(
              asset.hasVerifiedAiConfirmation
                  ? '${asset.rationale}\n${asset.provider} · ${asset.timeframe}'
                  : 'No verified AI confirmation is available for this asset.',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.read<NavigationCubit>().getNavBarItem(
                NavbarItem.tradingRoom,
              ),
              icon: const Icon(Icons.show_chart),
              label: const Text('OPEN TRADING ROOM'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailBox(String label, Widget content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0b0e11),
        borderRadius: BorderRadius.circular(12),
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
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          content,
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
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
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

class _WebTickerFooter extends StatelessWidget {
  final List<RadarAsset> assets;
  const _WebTickerFooter({required this.assets});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: const Color(0xFF0b0e11),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: assets
            .where((asset) => asset.price > 0)
            .take(3)
            .map(
              (asset) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TickerItem(
                  '${asset.symbol}: ${asset.price.toStringAsFixed(2)}',
                  asset.changePercent >= 0 ? AppColors.primary : AppColors.bear,
                ),
              ),
            )
            .toList(growable: false),
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
    return Row(
      children: [
        Icon(Icons.trending_up, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
