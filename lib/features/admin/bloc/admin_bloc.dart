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
    on<AdminStreamFailed>(_onStreamFailed);
    on<LoadDailyStats>(_onLoadDailyStats);
    on<UpdateDailyStats>(_onUpdateDailyStats);
    on<LoadRadarConfig>(_onLoadRadarConfig);
    on<UpdateRadarConfig>(_onUpdateRadarConfig);
  }

  Future<void> _onLoadData(
    LoadAdminData event,
    Emitter<AdminState> emit,
  ) async {
    emit(AdminLoading());
    try {
      _statsSubscription?.cancel();
      _statsSubscription = _adminRepository.getSystemStats().listen(
        (stats) => add(UpdateSystemStats(stats)),
        onError: (_) => add(const AdminStreamFailed()),
      );

      _requestsSubscription?.cancel();
      _requestsSubscription = _adminRepository.getPendingRequests().listen(
        (requests) => add(UpdatePendingRequests(requests)),
        onError: (_) => add(const AdminStreamFailed()),
      );

      _killSwitchSubscription?.cancel();
      _killSwitchSubscription = _adminRepository.getKillSwitchState().listen(
        (enabled) => add(UpdateKillSwitch(enabled)),
        onError: (_) => add(const AdminStreamFailed()),
      );

      _serviceStatusSubscription?.cancel();
      _serviceStatusSubscription = _adminRepository.getServiceStatus().listen(
        (statuses) => add(UpdateServiceStatus(statuses)),
        onError: (_) => add(const AdminStreamFailed()),
      );

      _globalRiskSubscription?.cancel();
      _globalRiskSubscription = _adminRepository.getGlobalRisk().listen(
        (config) => add(UpdateGlobalRisk(config)),
        onError: (_) => add(const AdminStreamFailed()),
      );

      emit(
        const AdminLoaded(
          stats: SystemStats(
            dau: 0,
            mau: 0,
            growth: 0.0,
            latency: 0,
            pendingAlerts: 0,
          ),
          requests: [],
        ),
      );

      add(LoadAIConfig());
      add(const LoadDailyStats());
      add(const LoadRadarConfig());
    } catch (_) {
      emit(const AdminError('common_access_denied'));
    }
  }

  Future<void> _onLoadDailyStats(
    LoadDailyStats event,
    Emitter<AdminState> emit,
  ) async {
    try {
      final dailyStats = await _adminRepository.getDailyStats(7);
      add(UpdateDailyStats(dailyStats));
    } catch (_) {
      // Empty analytics state is explicit in the UI.
    }
  }

  void _onUpdateDailyStats(UpdateDailyStats event, Emitter<AdminState> emit) {
    final current = state;
    if (current is AdminLoaded) {
      emit(current.copyWith(dailyStats: event.dailyStats));
    }
  }

  Future<void> _onLoadRadarConfig(
    LoadRadarConfig event,
    Emitter<AdminState> emit,
  ) async {
    try {
      add(UpdateRadarConfig(await _adminRepository.getRadarConfig()));
    } catch (_) {
      add(const UpdateRadarConfig(null));
    }
  }

  void _onUpdateRadarConfig(UpdateRadarConfig event, Emitter<AdminState> emit) {
    final current = state;
    if (current is! AdminLoaded) return;
    emit(
      AdminLoaded(
        stats: current.stats,
        requests: current.requests,
        aiConfig: current.aiConfig,
        aiConfigSaving: current.aiConfigSaving,
        aiConfigLoaded: current.aiConfigLoaded,
        tradingEnabled: current.tradingEnabled,
        serviceStatuses: current.serviceStatuses,
        globalRisk: current.globalRisk,
        actionResultNonce: current.actionResultNonce,
        actionMessageKey: current.actionMessageKey,
        actionSucceeded: current.actionSucceeded,
        dailyStats: current.dailyStats,
        radarConfig: event.config,
        radarConfigLoaded: true,
      ),
    );
  }

  void _onStreamFailed(AdminStreamFailed event, Emitter<AdminState> emit) {
    emit(const AdminError('common_access_denied'));
  }

  void _onUpdateStats(UpdateSystemStats event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(stats: event.stats));
    }
  }

  void _onUpdateRequests(
    UpdatePendingRequests event,
    Emitter<AdminState> emit,
  ) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(requests: event.requests));
    }
  }

  Future<void> _onBroadcast(
    BroadcastRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _adminRepository.broadcastSignal(event.message, event.tier);
      _emitActionResult(emit, true, 'admin_broadcast_sent');
    } catch (_) {
      _emitActionResult(emit, false, 'admin_action_failed');
    }
  }

  Future<void> _onHandleRequest(
    HandleRequest event,
    Emitter<AdminState> emit,
  ) async {
    try {
      if (event.approve) {
        await _adminRepository.approveRequest(event.requestId);
      } else {
        await _adminRepository.rejectRequest(event.requestId);
      }
      _emitActionResult(
        emit,
        true,
        event.approve ? 'admin_request_approved' : 'admin_request_rejected',
      );
    } catch (_) {
      _emitActionResult(emit, false, 'admin_action_failed');
    }
  }

  Future<void> _onLoadAIConfig(
    LoadAIConfig event,
    Emitter<AdminState> emit,
  ) async {
    try {
      final config = await _adminRepository.getAIConfig();
      if (state is AdminLoaded) {
        emit(
          (state as AdminLoaded).copyWith(
            aiConfig: config,
            aiConfigLoaded: true,
          ),
        );
      }
    } catch (_) {
      final current = state;
      if (current is AdminLoaded) {
        emit(current.copyWith(aiConfigLoaded: true));
      }
    }
  }

  Future<void> _onSaveAIConfig(
    SaveAIConfig event,
    Emitter<AdminState> emit,
  ) async {
    final initial = state;
    if (initial is AdminLoaded) {
      emit(initial.copyWith(aiConfigSaving: true));
      try {
        final config = AIConfig(
          masterPrompt: event.masterPrompt,
          lastUpdatedBy: 'admin',
        );
        await _adminRepository.saveAIConfig(config);
        final updated = await _adminRepository.getAIConfig();
        final current = state;
        if (current is! AdminLoaded) return;
        emit(
          current.copyWith(
            aiConfig: updated,
            aiConfigSaving: false,
            aiConfigLoaded: true,
            actionResultNonce: current.actionResultNonce + 1,
            actionMessageKey: 'admin_ai_config_saved',
            actionSucceeded: true,
          ),
        );
      } catch (_) {
        final current = state;
        if (current is AdminLoaded) {
          emit(
            current.copyWith(
              aiConfigSaving: false,
              actionResultNonce: current.actionResultNonce + 1,
              actionMessageKey: 'admin_action_failed',
              actionSucceeded: false,
            ),
          );
        }
      }
    }
  }

  Future<void> _onToggleKillSwitch(
    ToggleKillSwitch event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _adminRepository.toggleKillSwitch(event.enabled);
      _emitActionResult(emit, true, 'admin_kill_switch_saved');
    } catch (_) {
      _emitActionResult(emit, false, 'admin_action_failed');
    }
  }

  void _onUpdateKillSwitch(UpdateKillSwitch event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(tradingEnabled: event.enabled));
    }
  }

  Future<void> _onSaveGlobalRisk(
    SaveGlobalRisk event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _adminRepository.saveGlobalRisk(event.config);
      if (state is AdminLoaded) {
        final current = state as AdminLoaded;
        emit(
          current.copyWith(
            globalRisk: event.config,
            actionResultNonce: current.actionResultNonce + 1,
            actionMessageKey: 'admin_risk_saved',
            actionSucceeded: true,
          ),
        );
      }
    } catch (_) {
      _emitActionResult(emit, false, 'admin_action_failed');
    }
  }

  void _onUpdateGlobalRisk(UpdateGlobalRisk event, Emitter<AdminState> emit) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(globalRisk: event.config));
    }
  }

  void _onUpdateServiceStatus(
    UpdateServiceStatus event,
    Emitter<AdminState> emit,
  ) {
    if (state is AdminLoaded) {
      emit((state as AdminLoaded).copyWith(serviceStatuses: event.statuses));
    }
  }

  Future<void> _onSaveRadarConfig(
    SaveRadarConfig event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await _adminRepository.saveRadarConfig(event.symbols, event.sensitivity);
      final current = state;
      if (current is AdminLoaded) {
        emit(
          current.copyWith(
            radarConfig: RadarAdminConfig(
              symbols: List<String>.unmodifiable(event.symbols),
              sensitivity: event.sensitivity,
            ),
            radarConfigLoaded: true,
            actionResultNonce: current.actionResultNonce + 1,
            actionMessageKey: 'admin_radar_saved',
            actionSucceeded: true,
          ),
        );
      }
    } catch (_) {
      _emitActionResult(emit, false, 'admin_action_failed');
    }
  }

  void _emitActionResult(
    Emitter<AdminState> emit,
    bool succeeded,
    String messageKey,
  ) {
    final current = state;
    if (current is! AdminLoaded) return;
    emit(
      current.copyWith(
        actionResultNonce: current.actionResultNonce + 1,
        actionMessageKey: messageKey,
        actionSucceeded: succeeded,
      ),
    );
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
