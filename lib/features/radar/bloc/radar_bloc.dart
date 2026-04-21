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
    on<ToggleRadarAlert>(_onToggleAlert);
  }

  Future<void> _onLoadData(LoadRadarData event, Emitter<RadarState> emit) async {
    emit(RadarLoading());
    try {
      _assetsSubscription?.cancel();
      _assetsSubscription = _radarRepository.getRadarAssets().listen(
        (assets) => add(UpdateRadarAssets(assets)),
      );

      // Emit initial Loaded state immediately to avoid infinite spinner
      emit(const RadarLoaded(assets: [], selectedAsset: null));
    } catch (e) {
      emit(RadarError(e.toString()));
    }
  }

  void _onUpdateAssets(UpdateRadarAssets event, Emitter<RadarState> emit) {
    if (state is RadarLoaded) {
      final current = state as RadarLoaded;
      emit(current.copyWith(
        assets: event.assets,
        selectedAsset: current.selectedAsset ?? (event.assets.isNotEmpty ? event.assets.first : null),
      ));
    }
  }

  void _onSelectAsset(SelectAsset event, Emitter<RadarState> emit) {
    if (state is RadarLoaded) {
      emit((state as RadarLoaded).copyWith(selectedAsset: event.asset));
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
