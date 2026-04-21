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

  AdminBloc({required AdminRepository adminRepository})
      : _adminRepository = adminRepository,
        super(AdminInitial()) {
    on<LoadAdminData>(_onLoadData);
    on<UpdateSystemStats>(_onUpdateStats);
    on<UpdatePendingRequests>(_onUpdateRequests);
    on<BroadcastRequested>(_onBroadcast);
    on<HandleRequest>(_onHandleRequest);
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

      // Emit initial Loaded state immediately
      emit(const AdminLoaded(
        stats: SystemStats(dau: 0, mau: 0, growth: 0.0, latency: 0, pendingAlerts: 0),
        requests: [],
      ));
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

  @override
  Future<void> close() {
    _statsSubscription?.cancel();
    _requestsSubscription?.cancel();
    return super.close();
  }
}
