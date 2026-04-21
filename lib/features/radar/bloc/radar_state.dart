import 'package:equatable/equatable.dart';
import '../../../data/models/radar_models.dart';

abstract class RadarState extends Equatable {
  const RadarState();

  @override
  List<Object?> get props => [];
}

class RadarInitial extends RadarState {}

class RadarLoading extends RadarState {}

class RadarLoaded extends RadarState {
  final List<RadarAsset> assets;
  final RadarAsset? selectedAsset;
  final bool alertsEnabled;

  const RadarLoaded({
    required this.assets,
    this.selectedAsset,
    this.alertsEnabled = false,
  });

  RadarLoaded copyWith({
    List<RadarAsset>? assets,
    RadarAsset? selectedAsset,
    bool? alertsEnabled,
  }) {
    return RadarLoaded(
      assets: assets ?? this.assets,
      selectedAsset: selectedAsset ?? this.selectedAsset,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
    );
  }

  @override
  List<Object?> get props => [assets, selectedAsset, alertsEnabled];
}

class RadarError extends RadarState {
  final String message;
  const RadarError(this.message);

  @override
  List<Object?> get props => [message];
}
