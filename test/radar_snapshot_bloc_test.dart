import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/radar_models.dart';
import 'package:protrading_ai/data/repositories/radar_repository.dart';
import 'package:protrading_ai/features/radar/bloc/radar_bloc.dart';
import 'package:protrading_ai/features/radar/bloc/radar_event.dart';
import 'package:protrading_ai/features/radar/bloc/radar_state.dart';

class _Repository extends Fake implements RadarRepository {
  final snapshots = StreamController<List<RadarAsset>>.broadcast();
  @override
  Stream<List<RadarAsset>> getRadarAssets() => snapshots.stream;
}

RadarAsset asset(double price) => RadarAsset(
  symbol: 'ETHUSD',
  fullName: 'Ether',
  price: price,
  changePercent: 1,
  volatilityStatus: 'STABLE',
  hasAiConfirmation: false,
  aiSignal: 'NEUTRAL',
  sparklineData: const [],
);

Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'loading waits for a real snapshot and stale generation events are ignored',
    () async {
      final repository = _Repository();
      final bloc = RadarBloc(radarRepository: repository);
      addTearDown(repository.snapshots.close);
      addTearDown(() async {
        if (!bloc.isClosed) await bloc.close();
      });
      bloc.add(LoadRadarData());
      await flush();
      expect(bloc.state, isA<RadarLoading>());
      repository.snapshots.add([asset(2000)]);
      await flush();
      bloc.add(LoadRadarData());
      await flush();
      bloc.add(UpdateRadarAssets([asset(9999)], generation: 1));
      bloc.add(const RadarStreamFailed(1));
      await flush();
      expect(bloc.state, isA<RadarLoading>());
      repository.snapshots.add([asset(2010)]);
      await flush();
      expect((bloc.state as RadarLoaded).assets.single.price, 2010);
      await bloc.close();
      repository.snapshots.addError(StateError('late provider error'));
      await flush();
    },
  );

  test('confirmation provenance changes are part of snapshot equality', () {
    const original = RadarAsset(
      symbol: 'ETHUSD',
      fullName: 'Ether',
      price: 2000,
      changePercent: 1,
      volatilityStatus: 'STABLE',
      hasAiConfirmation: false,
      aiSignal: 'NEUTRAL',
      sparklineData: [],
      provider: 'provider-a',
    );
    const updated = RadarAsset(
      symbol: 'ETHUSD',
      fullName: 'Ether',
      price: 2000,
      changePercent: 1,
      volatilityStatus: 'STABLE',
      hasAiConfirmation: false,
      aiSignal: 'NEUTRAL',
      sparklineData: [],
      provider: 'provider-b',
    );
    expect(original, isNot(updated));
  });

  test(
    'selected detail follows the current snapshot and closes when removed',
    () async {
      final repository = _Repository();
      final bloc = RadarBloc(radarRepository: repository);
      addTearDown(repository.snapshots.close);
      addTearDown(bloc.close);
      bloc.add(LoadRadarData());
      await flush();
      repository.snapshots.add([asset(2000)]);
      await flush();
      repository.snapshots.add([asset(2010)]);
      await flush();
      expect((bloc.state as RadarLoaded).selectedAsset?.price, 2010);
      repository.snapshots.add([]);
      await flush();
      expect((bloc.state as RadarLoaded).selectedAsset, isNull);
    },
  );

  test(
    'clearing selection survives updates; valid snapshots recover stream failure',
    () async {
      final repository = _Repository();
      final bloc = RadarBloc(radarRepository: repository);
      addTearDown(repository.snapshots.close);
      addTearDown(bloc.close);
      bloc.add(LoadRadarData());
      await flush();
      repository.snapshots.add([asset(2000)]);
      await flush();
      bloc.add(ClearSelectedAsset());
      await flush();
      repository.snapshots.add([asset(2020)]);
      await flush();
      expect((bloc.state as RadarLoaded).selectedAsset, isNull);
      repository.snapshots.addError(
        StateError('provider details stay private'),
      );
      await flush();
      expect((bloc.state as RadarError).message, 'common_data_unavailable');
      repository.snapshots.add([asset(2030)]);
      await flush();
      expect(bloc.state, isA<RadarLoaded>());
      expect((bloc.state as RadarLoaded).assets.single.price, 2030);
    },
  );
}
