import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'radar_event.dart';
import 'radar_state.dart';
import '../../../data/repositories/radar_repository.dart';

class RadarBloc extends Bloc<RadarEvent, RadarState> {
  final RadarRepository _radarRepository;
  StreamSubscription? _assetsSubscription;

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
    emit(RadarLoading());
    try {
      _assetsSubscription?.cancel();
      _assetsSubscription = _radarRepository.getRadarAssets().listen(
        (assets) => add(UpdateRadarAssets(assets)),
        onError: (_) => add(const RadarStreamFailed()),
      );

      // Emit initial Loaded state immediately to avoid infinite spinner
      emit(const RadarLoaded(assets: [], selectedAsset: null));
    } catch (_) {
      emit(const RadarError('common_data_unavailable'));
    }
  }

  void _onStreamFailed(RadarStreamFailed event, Emitter<RadarState> emit) {
    emit(const RadarError('common_data_unavailable'));
  }

  void _onUpdateAssets(UpdateRadarAssets event, Emitter<RadarState> emit) {
    if (state is RadarLoaded) {
      final current = state as RadarLoaded;
      emit(
        current.copyWith(
          assets: event.assets,
          selectedAsset:
              current.selectedAsset ??
              (event.assets.isNotEmpty ? event.assets.first : null),
        ),
      );
    }
  }

  void _onSelectAsset(SelectAsset event, Emitter<RadarState> emit) {
    if (state is RadarLoaded) {
      emit((state as RadarLoaded).copyWith(selectedAsset: event.asset));
    }
  }

  void _onClearSelectedAsset(
    ClearSelectedAsset event,
    Emitter<RadarState> emit,
  ) {
    if (state case final RadarLoaded current) {
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
  Future<void> close() {
    _assetsSubscription?.cancel();
    return super.close();
  }
}
