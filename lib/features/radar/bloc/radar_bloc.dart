import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'radar_event.dart';
import 'radar_state.dart';
import '../../../data/repositories/radar_repository.dart';
import '../../../data/models/radar_models.dart';

class RadarBloc extends Bloc<RadarEvent, RadarState> {
  final RadarRepository _radarRepository;
  StreamSubscription<List<RadarAsset>>? _assetsSubscription;
  int _generation = 0;
  bool _selectionInitialized = false;
  String? _selectedSymbol;

  RadarBloc({required RadarRepository radarRepository})
    : _radarRepository = radarRepository,
      super(RadarInitial()) {
    on<LoadRadarData>(_onLoadData);
    on<UpdateRadarAssets>(_onUpdateAssets);
    on<SelectAsset>(_onSelectAsset);
    on<ClearSelectedAsset>(_onClearSelectedAsset);
    on<ToggleRadarAlert>(_onToggleAlert);
    on<RadarStreamFailed>(_onStreamFailed);
  }

  Future<void> _onLoadData(
    LoadRadarData event,
    Emitter<RadarState> emit,
  ) async {
    final generation = ++_generation;
    _selectionInitialized = false;
    _selectedSymbol = null;
    emit(RadarLoading());
    try {
      final previous = _assetsSubscription;
      _assetsSubscription = null;
      await previous?.cancel();
      if (isClosed || emit.isDone || generation != _generation) return;
      _assetsSubscription = _radarRepository.getRadarAssets().listen(
        (assets) {
          if (!isClosed && generation == _generation) {
            add(
              UpdateRadarAssets(
                List.unmodifiable(assets),
                generation: generation,
              ),
            );
          }
        },
        onError: (_) {
          if (!isClosed && generation == _generation) {
            add(RadarStreamFailed(generation));
          }
        },
      );
    } catch (_) {
      if (!isClosed && !emit.isDone && generation == _generation) {
        emit(const RadarError('common_data_unavailable'));
      }
    }
  }

  void _onStreamFailed(RadarStreamFailed event, Emitter<RadarState> emit) {
    if (event.generation != _generation) return;
    emit(const RadarError('common_data_unavailable'));
  }

  void _onUpdateAssets(UpdateRadarAssets event, Emitter<RadarState> emit) {
    if (event.generation != _generation) return;
    final assets = List<RadarAsset>.unmodifiable(event.assets);
    if (!_selectionInitialized && assets.isNotEmpty) {
      _selectedSymbol = assets.first.symbol;
      _selectionInitialized = true;
    }
    final selected = assets
        .where((asset) => asset.symbol == _selectedSymbol)
        .firstOrNull;
    _selectedSymbol = selected?.symbol;
    emit(RadarLoaded(assets: assets, selectedAsset: selected));
  }

  void _onSelectAsset(SelectAsset event, Emitter<RadarState> emit) {
    if (state case final RadarLoaded current) {
      final asset = current.assets
          .where((item) => item.symbol == event.asset.symbol)
          .firstOrNull;
      if (asset == null) return;
      _selectedSymbol = asset.symbol;
      _selectionInitialized = true;
      emit(current.copyWith(selectedAsset: asset));
    }
  }

  void _onClearSelectedAsset(
    ClearSelectedAsset event,
    Emitter<RadarState> emit,
  ) {
    if (state case final RadarLoaded current) {
      _selectedSymbol = null;
      _selectionInitialized = true;
      emit(
        RadarLoaded(
          assets: current.assets,
          selectedAsset: null,
          alertsEnabled: current.alertsEnabled,
        ),
      );
    }
  }

  void _onToggleAlert(ToggleRadarAlert event, Emitter<RadarState> emit) {
    if (state is RadarLoaded) {
      emit((state as RadarLoaded).copyWith(alertsEnabled: event.enabled));
    }
  }

  @override
  Future<void> close() async {
    ++_generation;
    try {
      await _assetsSubscription?.cancel();
    } finally {
      await super.close();
    }
  }
}
