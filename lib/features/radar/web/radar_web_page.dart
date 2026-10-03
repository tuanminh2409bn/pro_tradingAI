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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr(state.message),
                            style: const TextStyle(color: AppColors.bear),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.read<RadarBloc>().add(LoadRadarData()),
                            child: Text(context.tr('radar_retry')),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state is RadarLoaded) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 900;
                        final gridWidth =
                            constraints.maxWidth -
                            (!compact && state.selectedAsset != null ? 320 : 0);
                        final grid = state.assets.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr('radar_data_unavailable'),
                                  style: const TextStyle(color: Colors.white38),
                                ),
                              )
                            : GridView.builder(
                                shrinkWrap: compact,
                                physics: compact
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                padding: const EdgeInsets.all(24),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: compact
                                          ? 1
                                          : (gridWidth / 320).floor().clamp(
                                              1,
                                              3,
                                            ),
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      mainAxisExtent:
                                          200 *
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) /
                                          14,
                                    ),
                                itemCount: state.assets.length,
                                itemBuilder: (context, index) {
                                  final asset = state.assets[index];
                                  return InkWell(
                                    onTap: () => context.read<RadarBloc>().add(
                                      SelectAsset(asset),
                                    ),
                                    child: _RadarAssetCard(
                                      asset: asset,
                                      isSelected:
                                          state.selectedAsset?.symbol ==
                                          asset.symbol,
                                    ),
                                  );
                                },
                              );
                        return Column(
                          children: [
                            _buildFilterHeader(context),
                            Expanded(
                              child: compact
                                  ? SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          if (state.assets.isEmpty)
                                            SizedBox(height: 180, child: grid)
                                          else
                                            grid,
                                          if (state.selectedAsset != null)
                                            _RadarDetailSidebar(
                                              asset: state.selectedAsset!,
                                              compact: true,
                                            ),
                                        ],
                                      ),
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: grid),
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
                      },
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

  Widget _buildFilterHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.3),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('radar_snapshot_title'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            context.tr('radar_snapshot_status'),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('radar_push_unavailable'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                  ),
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
    );
  }
}

String _radarPrice(double price) =>
    price.isFinite && price > 0 ? price.toString() : '—';

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
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        asset.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
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
                          boxShadow: [
                            BoxShadow(color: mainColor, blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                asset.changePercent.isFinite
                    ? '${asset.changePercent > 0 ? '+' : ''}${asset.changePercent}%'
                    : '—',
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
            _radarPrice(asset.price),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.psychology,
                    size: 10,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      context.tr('radar_confirmation_title'),
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
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

class _RadarDetailSidebar extends StatelessWidget {
  final RadarAsset asset;
  final bool compact;
  const _RadarDetailSidebar({required this.asset, this.compact = false});

  @override
  Widget build(BuildContext context) {
    Color mainColor = asset.changePercent >= 0
        ? AppColors.primary
        : AppColors.bear;

    return Container(
      width: compact ? double.infinity : 320,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        border: const Border(left: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        physics: compact ? const NeverScrollableScrollPhysics() : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    context.tr('radar_asset_detail'),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('radar_close_details'),
                  onPressed: () =>
                      context.read<RadarBloc>().add(ClearSelectedAsset()),
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white24,
                  ),
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
            Text(
              context
                  .tr('radar_reported_change')
                  .replaceAll(
                    '{percent}',
                    asset.changePercent.isFinite
                        ? asset.changePercent.toString()
                        : '—',
                  ),
              style: TextStyle(
                color: mainColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (asset.hasVerifiedAiConfirmation)
              Text(
                context.tr('radar_alert_label'),
                style: TextStyle(
                  color: mainColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            const SizedBox(height: 32),
            _buildDetailBox(
              context.tr('radar_strength_title'),
              Text(
                context.tr('radar_strength_unmeasured'),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailBox(
              asset.hasVerifiedAiConfirmation
                  ? '${context.tr('radar_confirmation_title')} · ${asset.model}'
                  : context.tr('radar_confirmation_title'),
              Text(
                asset.hasVerifiedAiConfirmation
                    ? '${asset.rationale}\n${asset.provider} · ${asset.timeframe}\n${asset.confirmedAt!.toUtc().toIso8601String()}'
                    : context.tr('radar_confirmation_unavailable'),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final opened = context
                      .read<NavigationCubit>()
                      .openTradingRoom(
                        asset.symbol,
                        timeframe: asset.hasVerifiedAiConfirmation
                            ? asset.timeframe
                            : null,
                      );
                  if (!opened) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('radar_data_unavailable')),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.show_chart),
                label: Text(context.tr('radar_open_chart')),
              ),
            ),
          ],
        ),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: assets
              .where((asset) => asset.price.isFinite && asset.price > 0)
              .take(3)
              .map(
                (asset) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TickerItem(
                    '${asset.symbol}: ${_radarPrice(asset.price)}',
                    asset.changePercent >= 0
                        ? AppColors.primary
                        : AppColors.bear,
                  ),
                ),
              )
              .toList(growable: false),
        ),
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
