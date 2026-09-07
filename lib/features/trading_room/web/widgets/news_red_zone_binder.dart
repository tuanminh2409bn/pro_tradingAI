import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  String? _lastLabel;

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
    _sub = repo.watchLatestHighImpactNews().listen((article) {
      if (!mounted) return;
      final bloc = context.read<TradingRoomBloc>();
      if (article == null) {
        if (_lastLabel != null) {
          _lastLabel = null;
          bloc.add(const ClearNewsRedZone());
        }
        return;
      }
      final label = 'NEWS ${article.title}';
      if (label == _lastLabel) return;
      _lastLabel = label;
      bloc.add(ApplyNewsRedZone(label));
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
