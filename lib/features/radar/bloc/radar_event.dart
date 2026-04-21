import 'package:equatable/equatable.dart';
import '../../../data/models/radar_models.dart';

abstract class RadarEvent extends Equatable {
  const RadarEvent();

  @override
  List<Object?> get props => [];
}

class LoadRadarData extends RadarEvent {}

class UpdateRadarAssets extends RadarEvent {
  final List<RadarAsset> assets;
  const UpdateRadarAssets(this.assets);

  @override
  List<Object?> get props => [assets];
}

class SelectAsset extends RadarEvent {
  final RadarAsset asset;
  const SelectAsset(this.asset);

  @override
  List<Object?> get props => [asset];
}

class ToggleRadarAlert extends RadarEvent {
  final bool enabled;
  const ToggleRadarAlert(this.enabled);

  @override
  List<Object?> get props => [enabled];
}
