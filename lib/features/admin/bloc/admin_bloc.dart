import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'admin_event.dart';
import 'admin_state.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/models/admin_models.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final AdminRepository _adminRepository;
  StreamSubscription? _statsSubscription;
  StreamSubscription? _requestsSubscription;
  StreamSubscription? _killSwitchSubscription;
  StreamSubscription? _serviceStatusSubscription;
  StreamSubscription? _globalRiskSubscription;

  AdminBloc({required AdminRepository adminRepository})
      : _adminRepository = adminRepository,
        super(AdminInitial()) {
    on<LoadAdminData>(_onLoadData);
    on<UpdateSystemStats>(_onUpdateStats);
    on<UpdatePendingRequests>(_onUpdateRequests);
    on<BroadcastRequested>(_onBroadcast);
    on<HandleRequest>(_onHandleRequest);
    on<LoadAIConfig>(_onLoadAIConfig);
    on<SaveAIConfig>(_onSaveAIConfig);
    on<ToggleKillSwitch>(_onToggleKillSwitch);
    on<UpdateKillSwitch>(_onUpdateKillSwitch);
    on<SaveGlobalRisk>(_onSaveGlobalRisk);
    on<UpdateGlobalRisk>(_onUpdateGlobalRisk);
    on<UpdateServiceStatus>(_onUpdateServiceStatus);
    on<SaveRadarConfig>(_onSaveRadarConfig);
  }

  Future<void> _onLoadData(LoadAdminData event, Emitter<AdminState> emit) async {
    emit(AdminLoading());
    try {
      _statsSubscription?.cancel();
      _statsSubscription = _adminRepository.getSystemStats().listen(
        (stats) => add(UpdateSystemStats(stats)),
        onError: (e) => print('AdminBloc: Stats error: $e'),
      );

      _requestsSubscription?.cancel();
      _requestsSubscription = _adminRepository.getPendingRequests().listen(
        (requests) => add(UpdatePendingRequests(requests)),
        onError: (e) => print('AdminBloc: Requests error: $e'),
      );

      _killSwitchSubscription?.cancel();
      _killSwitchSubscription = _adminRepository.getKillSwitchState().listen(
        (enabled) => add(UpdateKillSwitch(enabled)),
        onError: (e) => print('AdminBloc: KillSwitch error: $e'),
      );

      _serviceStatusSubscription?.cancel();
      _serviceStatusSubscription = _adminRepository.getServiceStatus().listen(
        (statuses) => add(UpdateServiceStatus(statuses)),
        onError: (e) => print('AdminBloc: ServiceStatus error: $e'),
      );

      _globalRiskSubscription?.cancel();
      _globalRiskSubscription = _adminRepository.getGlobalRisk().listen(
        (config) => add(UpdateGlobalRisk(config)),
        onError: (e) => print('AdminBloc: GlobalRisk error: $e'),
      );

      emit(const AdminLoaded(
        stats: SystemStats(dau: 0, mau: 0, growth: 0.0, latency: 0, pendingAlerts: 0),
        requests: [],
      ));

      add(LoadAIConfig());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  void _onUpdateStats(UpdateSystemStats event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(stats: event.stats));
    }
  }

  void _onUpdateRequests(UpdatePendingRequests event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(requests: event.requests));
    }
  }

  Future<void> _onBroadcast(BroadcastRequested event, Emitter<AdminState> emit) async {
    await _adminRepository.broadcastSignal(event.message, event.tier);
  }

  Future<void> _onHandleRequest(HandleRequest event, Emitter<AdminState> emit) async {
    if (event.approve) {
      await _adminRepository.approveRequest(event.requestId);
    } else {
      await _adminRepository.rejectRequest(event.requestId);
    }
  }

  Future<void> _onLoadAIConfig(LoadAIConfig event, Emitter<AdminState> emit) async {
    try {
      final config = await _adminRepository.getAIConfig();
      if (state is AdminLoaded) {
        emit((state as AdminLoaded).copyWith(aiConfig: config));
      }
    } catch (e) {
      print('AdminBloc: AI Config load error: $e');
    }
  }

  Future<void> _onSaveAIConfig(SaveAIConfig event, Emitter<AdminState> emit) async {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(aiConfigSaving: true));
      try {
        final config = AIConfig(masterPrompt: event.masterPrompt, lastUpdatedBy: 'admin');
        await _adminRepository.saveAIConfig(config);
        final updated = await _adminRepository.getAIConfig();
        emit((state as AdminLoaded).copyWith(aiConfig: updated, aiConfigSaving: false));
      } catch (e) {
        emit((state as AdminLoaded).copyWith(aiConfigSaving: false));
        print('AdminBloc: AI Config save error: $e');
      }
    }
  }

  Future<void> _onToggleKillSwitch(ToggleKillSwitch event, Emitter<AdminState> emit) async {
    try {
      await _adminRepository.toggleKillSwitch(event.enabled);
      // State cập nhật qua stream _killSwitchSubscription
    } catch (e) {
      print('AdminBloc: KillSwitch toggle error: $e');
    }
  }

  void _onUpdateKillSwitch(UpdateKillSwitch event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(tradingEnabled: event.enabled));
    }
  }

  Future<void> _onSaveGlobalRisk(SaveGlobalRisk event, Emitter<AdminState> emit) async {
    try {
      await _adminRepository.saveGlobalRisk(event.config);
      if (state is AdminLoaded) {
        emit((state as AdminLoaded).copyWith(globalRisk: event.config));
      }
    } catch (e) {
      print('AdminBloc: GlobalRisk save error: $e');
    }
  }

  void _onUpdateGlobalRisk(UpdateGlobalRisk event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(globalRisk: event.config));
    }
  }

  void _onUpdateServiceStatus(UpdateServiceStatus event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(serviceStatuses: event.statuses));
    }
  }

  Future<void> _onSaveRadarConfig(SaveRadarConfig event, Emitter<AdminState> emit) async {
    try {
      await _adminRepository.saveRadarConfig(event.symbols, event.sensitivity);
    } catch (e) {
      print('AdminBloc: RadarConfig save error: $e');
    }
  }

  @override
  Future<void> close() {
    _statsSubscription?.cancel();
    _requestsSubscription?.cancel();
    _killSwitchSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _globalRiskSubscription?.cancel();
    return super.close();
  }
}
