import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/trading_models.dart';
import '../../../../data/repositories/news_repository.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_event.dart';

/// Day 6 — bind latest HIGH-impact news → chart Layer 5 Red Zone.
class NewsRedZoneBinder extends StatefulWidget {
  final Widget child;
  const NewsRedZoneBinder({super.key, required this.child});

  @override
  State<NewsRedZoneBinder> createState() => _NewsRedZoneBinderState();
}

class _NewsRedZoneBinderState extends State<NewsRedZoneBinder> {
  StreamSubscription? _sub;
  RedZoneOverlay? _lastOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bind());
  }

  void _bind() {
    if (!mounted) return;
    NewsRepository? repo;
    try {
      repo = context.read<NewsRepository>();
    } catch (_) {
      return;
    }
    _sub?.cancel();
    _sub = repo.watchNextScheduledHighImpactEvent().listen((overlay) {
      if (!mounted) return;
      final bloc = context.read<TradingRoomBloc>();
      if (overlay == null) {
        if (_lastOverlay != null) {
          _lastOverlay = null;
          bloc.add(const ClearNewsRedZone());
        }
        return;
      }
      if (overlay == _lastOverlay) return;
      _lastOverlay = overlay;
      bloc.add(ApplyNewsRedZone(overlay));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
