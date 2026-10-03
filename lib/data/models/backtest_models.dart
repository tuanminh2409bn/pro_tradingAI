import 'package:equatable/equatable.dart';

class BacktestBar extends Equatable {
  final int timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final bool isClosed;

  const BacktestBar({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.isClosed,
  });

  BacktestBar copyWith({bool? isClosed}) => BacktestBar(
    timestamp: timestamp,
    open: open,
    high: high,
    low: low,
    close: close,
    volume: volume,
    isClosed: isClosed ?? this.isClosed,
  );

  factory BacktestBar.fromMap(Map<String, dynamic> map) {
    if (map['t'] is! int ||
        map['closed'] != true ||
        ['o', 'h', 'l', 'c', 'v'].any((key) => map[key] is! num)) {
      throw const FormatException('Invalid stored backtest bar');
    }
    final bar = BacktestBar(
      timestamp: map['t'] as int,
      open: (map['o'] as num).toDouble(),
      high: (map['h'] as num).toDouble(),
      low: (map['l'] as num).toDouble(),
      close: (map['c'] as num).toDouble(),
      volume: (map['v'] as num).toDouble(),
      isClosed: true,
    );
    if (!bar.isValid) {
      throw const FormatException('Invalid stored backtest bar');
    }
    return bar;
  }

  Map<String, dynamic> toMap() => {
    't': timestamp,
    'o': open,
    'h': high,
    'l': low,
    'c': close,
    'v': volume,
    'closed': isClosed,
  };

  bool get isValid =>
      timestamp > 0 &&
      open.isFinite &&
      high.isFinite &&
      low.isFinite &&
      close.isFinite &&
      volume.isFinite &&
      volume >= 0 &&
      high >= open &&
      high >= close &&
      low <= open &&
      low <= close &&
      high >= low;

  @override
  List<Object?> get props => [
    timestamp,
    open,
    high,
    low,
    close,
    volume,
    isClosed,
  ];
}

class BacktestReplaySnapshot extends Equatable {
  final String sessionId;
  final String symbol;
  final String sourceId;
  final int cursor;
  final int speed;
  final bool isPlaying;

  const BacktestReplaySnapshot({
    required this.sessionId,
    required this.symbol,
    required this.sourceId,
    required this.cursor,
    required this.speed,
    required this.isPlaying,
  });

  factory BacktestReplaySnapshot.fromMap(Map<String, dynamic> map) {
    final sessionId = map['session_id'];
    final symbol = map['symbol'];
    final sourceId = map['source_id'];
    final cursor = map['cursor'];
    final speed = map['speed'];
    final isPlaying = map['is_playing'];
    if (sessionId is! String ||
        sessionId.trim().isEmpty ||
        symbol is! String ||
        symbol.trim().isEmpty ||
        sourceId is! String ||
        sourceId.trim().isEmpty ||
        cursor is! int ||
        cursor < 0 ||
        speed is! int ||
        !BacktestReplayEngine.allowedSpeeds.contains(speed) ||
        isPlaying is! bool) {
      throw const FormatException('Invalid backtest replay snapshot');
    }
    return BacktestReplaySnapshot(
      sessionId: sessionId,
      symbol: symbol.trim().toUpperCase(),
      sourceId: sourceId,
      cursor: cursor,
      speed: speed,
      isPlaying: isPlaying,
    );
  }

  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'symbol': symbol,
    'source_id': sourceId,
    'cursor': cursor,
    'speed': speed,
    'is_playing': isPlaying,
  };

  @override
  List<Object?> get props => [
    sessionId,
    symbol,
    sourceId,
    cursor,
    speed,
    isPlaying,
  ];
}

class BacktestReplayEngine {
  static const allowedSpeeds = {1, 5, 10};

  final String sessionId;
  final String symbol;
  final String sourceId;
  final List<BacktestBar> _bars;
  int _cursor = 0;
  int _speed = 1;
  bool _isPlaying = false;

  BacktestReplayEngine({
    required this.sessionId,
    required String symbol,
    required this.sourceId,
    required List<BacktestBar> bars,
  }) : symbol = symbol.trim().toUpperCase(),
       _bars = List<BacktestBar>.unmodifiable(bars) {
    _validateIdentity();
    _validateBars();
  }

  factory BacktestReplayEngine.restore({
    required BacktestReplaySnapshot snapshot,
    required List<BacktestBar> bars,
    required String expectedSessionId,
    required String expectedSymbol,
    required String expectedSourceId,
  }) {
    if (snapshot.sessionId != expectedSessionId ||
        snapshot.symbol != expectedSymbol.trim().toUpperCase() ||
        snapshot.sourceId != expectedSourceId) {
      throw ArgumentError(
        'Replay snapshot does not match the requested dataset',
      );
    }
    final engine = BacktestReplayEngine(
      sessionId: snapshot.sessionId,
      symbol: snapshot.symbol,
      sourceId: snapshot.sourceId,
      bars: bars,
    );
    if (snapshot.cursor >= engine._bars.length) {
      throw ArgumentError('Replay cursor is outside the historical dataset');
    }
    engine
      .._cursor = snapshot.cursor
      .._speed = snapshot.speed
      .._isPlaying = snapshot.isPlaying && snapshot.cursor < bars.length - 1;
    return engine;
  }

  int get cursor => _cursor;
  int get totalBars => _bars.length;
  int get speed => _speed;
  bool get isPlaying => _isPlaying;
  BacktestBar get currentBar => _bars[_cursor];
  List<BacktestBar> get visibleBars =>
      List<BacktestBar>.unmodifiable(_bars.getRange(0, _cursor + 1));
  Duration get tickInterval => Duration(milliseconds: 1000 ~/ _speed);

  BacktestReplaySnapshot get snapshot => BacktestReplaySnapshot(
    sessionId: sessionId,
    symbol: symbol,
    sourceId: sourceId,
    cursor: _cursor,
    speed: _speed,
    isPlaying: _isPlaying,
  );

  void resume() {
    if (_cursor < _bars.length - 1) _isPlaying = true;
  }

  void pause() => _isPlaying = false;

  void setSpeed(int value) {
    if (!allowedSpeeds.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Allowed speeds are 1, 5, 10');
    }
    _speed = value;
  }

  bool advanceTick() {
    if (!_isPlaying || _cursor >= _bars.length - 1) {
      _isPlaying = false;
      return false;
    }
    _cursor += 1;
    if (_cursor == _bars.length - 1) _isPlaying = false;
    return true;
  }

  void seek(int value) {
    if (value < 0 || value >= _bars.length) {
      throw RangeError.range(value, 0, _bars.length - 1, 'value');
    }
    _cursor = value;
    _isPlaying = false;
  }

  bool stepBackward() {
    if (_cursor == 0) return false;
    seek(_cursor - 1);
    return true;
  }

  bool stepForward() {
    if (_cursor >= _bars.length - 1) return false;
    seek(_cursor + 1);
    return true;
  }

  void _validateIdentity() {
    if (sessionId.trim().isEmpty || symbol.isEmpty || sourceId.trim().isEmpty) {
      throw ArgumentError('Replay identity must be complete');
    }
  }

  void _validateBars() {
    if (_bars.isEmpty) throw ArgumentError('Replay requires historical bars');
    var previousTimestamp = 0;
    for (final bar in _bars) {
      if (!bar.isClosed || !bar.isValid || bar.timestamp <= previousTimestamp) {
        throw ArgumentError('Replay bars must be valid, closed, and ordered');
      }
      previousTimestamp = bar.timestamp;
    }
  }
}

enum BacktestSide { buy, sell }

class BacktestDecision<T> extends Equatable {
  final int cursor;
  final int candleTimestamp;
  final T value;

  const BacktestDecision({
    required this.cursor,
    required this.candleTimestamp,
    required this.value,
  });

  @override
  List<Object?> get props => [cursor, candleTimestamp, value];
}

class BacktestSimulatedTrade extends Equatable {
  final String id;
  final BacktestSide side;
  final double volume;
  final double contractSize;
  final double entryPrice;
  final int entryTimestamp;
  final double? exitPrice;
  final int? exitTimestamp;

  const BacktestSimulatedTrade({
    required this.id,
    required this.side,
    required this.volume,
    required this.contractSize,
    required this.entryPrice,
    required this.entryTimestamp,
    this.exitPrice,
    this.exitTimestamp,
  });

  factory BacktestSimulatedTrade.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final side = map['side'];
    final volume = map['volume'];
    final contractSize = map['contract_size'];
    final entryPrice = map['entry_price'];
    final entryTimestamp = map['entry_timestamp'];
    final exitPrice = map['exit_price'];
    final exitTimestamp = map['exit_timestamp'];
    if (id is! String ||
        id.trim().isEmpty ||
        (side != 'BUY' && side != 'SELL') ||
        volume is! num ||
        contractSize is! num ||
        entryPrice is! num ||
        entryTimestamp is! int ||
        (exitPrice != null && exitPrice is! num) ||
        (exitTimestamp != null && exitTimestamp is! int) ||
        ((exitPrice == null) != (exitTimestamp == null))) {
      throw const FormatException('Invalid simulated backtest trade');
    }
    final trade = BacktestSimulatedTrade(
      id: id,
      side: side == 'BUY' ? BacktestSide.buy : BacktestSide.sell,
      volume: volume.toDouble(),
      contractSize: contractSize.toDouble(),
      entryPrice: entryPrice.toDouble(),
      entryTimestamp: entryTimestamp,
      exitPrice: (exitPrice as num?)?.toDouble(),
      exitTimestamp: exitTimestamp as int?,
    );
    trade._validate();
    return trade;
  }

  bool get isOpen => exitPrice == null;

  double get realizedPnl {
    if (exitPrice == null) return 0;
    return _pnlAt(exitPrice!);
  }

  double floatingPnl(double markPrice) {
    if (!isOpen) return 0;
    if (!markPrice.isFinite || markPrice <= 0) {
      throw ArgumentError.value(markPrice, 'markPrice');
    }
    return _pnlAt(markPrice);
  }

  BacktestSimulatedTrade closeAt({
    required double price,
    required int timestamp,
  }) {
    if (!isOpen) throw StateError('Backtest trade is already closed');
    if (!price.isFinite || price <= 0 || timestamp < entryTimestamp) {
      throw ArgumentError('Invalid simulated trade exit');
    }
    return BacktestSimulatedTrade(
      id: id,
      side: side,
      volume: volume,
      contractSize: contractSize,
      entryPrice: entryPrice,
      entryTimestamp: entryTimestamp,
      exitPrice: price,
      exitTimestamp: timestamp,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'side': side == BacktestSide.buy ? 'BUY' : 'SELL',
    'volume': volume,
    'contract_size': contractSize,
    'entry_price': entryPrice,
    'entry_timestamp': entryTimestamp,
    'exit_price': exitPrice,
    'exit_timestamp': exitTimestamp,
  };

  double _pnlAt(double price) {
    final direction = side == BacktestSide.buy ? 1.0 : -1.0;
    return (price - entryPrice) * direction * volume * contractSize;
  }

  void _validate() {
    if (id.trim().isEmpty ||
        !volume.isFinite ||
        volume <= 0 ||
        !contractSize.isFinite ||
        contractSize <= 0 ||
        !entryPrice.isFinite ||
        entryPrice <= 0 ||
        entryTimestamp <= 0 ||
        (exitPrice != null && (!exitPrice!.isFinite || exitPrice! <= 0)) ||
        (exitTimestamp != null && exitTimestamp! < entryTimestamp)) {
      throw const FormatException('Invalid simulated backtest trade values');
    }
  }

  @override
  List<Object?> get props => [
    id,
    side,
    volume,
    contractSize,
    entryPrice,
    entryTimestamp,
    exitPrice,
    exitTimestamp,
  ];
}

class BacktestSessionReview extends Equatable {
  final String id;
  final String sessionId;
  final int triggeredAtTimestamp;
  final double lossAmount;
  final int closedTradeCount;
  final String summary;
  final bool isAcknowledged;

  const BacktestSessionReview({
    required this.id,
    required this.sessionId,
    required this.triggeredAtTimestamp,
    required this.lossAmount,
    required this.closedTradeCount,
    required this.summary,
    required this.isAcknowledged,
  });

  factory BacktestSessionReview.triggered({
    required String sessionId,
    required int timestamp,
    required double lossAmount,
    required int closedTradeCount,
  }) {
    final normalizedLoss = lossAmount.toStringAsFixed(2);
    return BacktestSessionReview(
      id: '$sessionId:$timestamp:$normalizedLoss',
      sessionId: sessionId,
      triggeredAtTimestamp: timestamp,
      lossAmount: lossAmount,
      closedTradeCount: closedTradeCount,
      summary:
          'Session locked after a $normalizedLoss loss with '
          '$closedTradeCount closed trade(s). Review risk and execution before continuing.',
      isAcknowledged: false,
    );
  }

  factory BacktestSessionReview.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final sessionId = map['session_id'];
    final timestamp = map['triggered_at_timestamp'];
    final lossAmount = map['loss_amount'];
    final closedTradeCount = map['closed_trade_count'];
    final summary = map['summary'];
    final acknowledged = map['is_acknowledged'];
    if (id is! String ||
        id.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty ||
        timestamp is! int ||
        timestamp <= 0 ||
        lossAmount is! num ||
        !lossAmount.isFinite ||
        lossAmount < 0 ||
        closedTradeCount is! int ||
        closedTradeCount < 0 ||
        summary is! String ||
        summary.isEmpty ||
        acknowledged is! bool) {
      throw const FormatException('Invalid backtest session review');
    }
    return BacktestSessionReview(
      id: id,
      sessionId: sessionId,
      triggeredAtTimestamp: timestamp,
      lossAmount: lossAmount.toDouble(),
      closedTradeCount: closedTradeCount,
      summary: summary,
      isAcknowledged: acknowledged,
    );
  }

  BacktestSessionReview acknowledge() => BacktestSessionReview(
    id: id,
    sessionId: sessionId,
    triggeredAtTimestamp: triggeredAtTimestamp,
    lossAmount: lossAmount,
    closedTradeCount: closedTradeCount,
    summary: summary,
    isAcknowledged: true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'triggered_at_timestamp': triggeredAtTimestamp,
    'loss_amount': lossAmount,
    'closed_trade_count': closedTradeCount,
    'summary': summary,
    'is_acknowledged': isAcknowledged,
  };

  @override
  List<Object?> get props => [
    id,
    sessionId,
    triggeredAtTimestamp,
    lossAmount,
    closedTradeCount,
    summary,
    isAcknowledged,
  ];
}

class BacktestSimulationSnapshot extends Equatable {
  final BacktestReplaySnapshot replay;
  final double initialBalance;
  final double maxLossAmount;
  final double contractSize;
  final double balance;
  final double lossReferenceEquity;
  final List<BacktestSimulatedTrade> trades;
  final bool isLocked;
  final BacktestSessionReview? pendingReview;
  final BacktestSessionReview? lastAcknowledgedReview;

  BacktestSimulationSnapshot({
    required this.replay,
    required this.initialBalance,
    required this.maxLossAmount,
    required this.contractSize,
    required this.balance,
    required this.lossReferenceEquity,
    required List<BacktestSimulatedTrade> trades,
    required this.isLocked,
    required this.pendingReview,
    required this.lastAcknowledgedReview,
  }) : trades = List<BacktestSimulatedTrade>.unmodifiable(trades);

  factory BacktestSimulationSnapshot.fromMap(Map<String, dynamic> map) {
    final replay = map['replay'];
    final initialBalance = map['initial_balance'];
    final maxLossAmount = map['max_loss_amount'];
    final contractSize = map['contract_size'];
    final balance = map['balance'];
    final lossReferenceEquity = map['loss_reference_equity'];
    final trades = map['trades'];
    final isLocked = map['is_locked'];
    final pendingReview = map['pending_review'];
    final lastAcknowledgedReview = map['last_acknowledged_review'];
    if (replay is! Map ||
        initialBalance is! num ||
        maxLossAmount is! num ||
        contractSize is! num ||
        balance is! num ||
        lossReferenceEquity is! num ||
        trades is! List ||
        isLocked is! bool ||
        (pendingReview != null && pendingReview is! Map) ||
        (lastAcknowledgedReview != null && lastAcknowledgedReview is! Map)) {
      throw const FormatException('Invalid backtest simulation snapshot');
    }
    try {
      return BacktestSimulationSnapshot(
        replay: BacktestReplaySnapshot.fromMap(
          Map<String, dynamic>.from(replay),
        ),
        initialBalance: initialBalance.toDouble(),
        maxLossAmount: maxLossAmount.toDouble(),
        contractSize: contractSize.toDouble(),
        balance: balance.toDouble(),
        lossReferenceEquity: lossReferenceEquity.toDouble(),
        trades: trades
            .map(
              (trade) => BacktestSimulatedTrade.fromMap(
                Map<String, dynamic>.from(trade as Map),
              ),
            )
            .toList(growable: false),
        isLocked: isLocked,
        pendingReview: pendingReview == null
            ? null
            : BacktestSessionReview.fromMap(
                Map<String, dynamic>.from(pendingReview),
              ),
        lastAcknowledgedReview: lastAcknowledgedReview == null
            ? null
            : BacktestSessionReview.fromMap(
                Map<String, dynamic>.from(lastAcknowledgedReview),
              ),
      );
    } on TypeError {
      throw const FormatException('Invalid backtest simulation snapshot');
    }
  }

  Map<String, dynamic> toMap() => {
    'replay': replay.toMap(),
    'initial_balance': initialBalance,
    'max_loss_amount': maxLossAmount,
    'contract_size': contractSize,
    'balance': balance,
    'loss_reference_equity': lossReferenceEquity,
    'trades': trades.map((trade) => trade.toMap()).toList(growable: false),
    'is_locked': isLocked,
    'pending_review': pendingReview?.toMap(),
    'last_acknowledged_review': lastAcknowledgedReview?.toMap(),
  };

  @override
  List<Object?> get props => [
    replay,
    initialBalance,
    maxLossAmount,
    contractSize,
    balance,
    lossReferenceEquity,
    trades,
    isLocked,
    pendingReview,
    lastAcknowledgedReview,
  ];
}

class BacktestSimulationEngine {
  final BacktestReplayEngine replay;
  final double initialBalance;
  final double maxLossAmount;
  final double contractSize;
  final List<BacktestSimulatedTrade> _trades = [];
  late double _balance;
  late double _lossReferenceEquity;
  bool _isLocked = false;
  BacktestSessionReview? _pendingReview;
  BacktestSessionReview? _lastAcknowledgedReview;

  BacktestSimulationEngine({
    required this.replay,
    required this.initialBalance,
    required this.maxLossAmount,
    required this.contractSize,
  }) {
    _validateConfiguration();
    _balance = initialBalance;
    _lossReferenceEquity = initialBalance;
  }

  factory BacktestSimulationEngine.restore({
    required BacktestSimulationSnapshot snapshot,
    required List<BacktestBar> bars,
    required String expectedSessionId,
    required String expectedSymbol,
    required String expectedSourceId,
  }) {
    final engine = BacktestSimulationEngine(
      replay: BacktestReplayEngine.restore(
        snapshot: snapshot.replay,
        bars: bars,
        expectedSessionId: expectedSessionId,
        expectedSymbol: expectedSymbol,
        expectedSourceId: expectedSourceId,
      ),
      initialBalance: snapshot.initialBalance,
      maxLossAmount: snapshot.maxLossAmount,
      contractSize: snapshot.contractSize,
    );
    engine
      .._balance = snapshot.balance
      .._lossReferenceEquity = snapshot.lossReferenceEquity
      .._isLocked = snapshot.isLocked
      .._pendingReview = snapshot.pendingReview
      .._lastAcknowledgedReview = snapshot.lastAcknowledgedReview
      .._trades.addAll(snapshot.trades)
      .._validateRestoredState();
    return engine;
  }

  double get balance => _balance;
  double get equity =>
      _balance +
      _trades.fold<double>(
        0,
        (total, trade) => total + trade.floatingPnl(replay.currentBar.close),
      );
  bool get isLocked => _isLocked;
  BacktestSessionReview? get pendingReview => _pendingReview;
  BacktestSessionReview? get lastAcknowledgedReview => _lastAcknowledgedReview;
  List<BacktestSimulatedTrade> get trades =>
      List<BacktestSimulatedTrade>.unmodifiable(_trades);
  List<BacktestSimulatedTrade> get openTrades =>
      List<BacktestSimulatedTrade>.unmodifiable(
        _trades.where((trade) => trade.isOpen),
      );

  BacktestDecision<T> evaluate<T>(
    T Function(List<BacktestBar> visibleBars) evaluator,
  ) {
    final visibleBars = replay.visibleBars;
    return BacktestDecision<T>(
      cursor: replay.cursor,
      candleTimestamp: replay.currentBar.timestamp,
      value: evaluator(visibleBars),
    );
  }

  void openTrade({
    required String id,
    required BacktestSide side,
    required double volume,
  }) {
    if (_isLocked) throw StateError('Backtest session is locked');
    if (id.trim().isEmpty || !volume.isFinite || volume <= 0) {
      throw ArgumentError('Trade ID and volume must be valid');
    }
    if (_trades.any((trade) => trade.id == id)) {
      throw ArgumentError.value(id, 'id', 'Trade ID must be unique');
    }
    _trades.add(
      BacktestSimulatedTrade(
        id: id,
        side: side,
        volume: volume,
        contractSize: contractSize,
        entryPrice: replay.currentBar.close,
        entryTimestamp: replay.currentBar.timestamp,
      ),
    );
  }

  BacktestSimulatedTrade closeTrade(String id) {
    final index = _trades.indexWhere((trade) => trade.id == id && trade.isOpen);
    if (index < 0) throw StateError('Open backtest trade was not found');
    final closed = _trades[index].closeAt(
      price: replay.currentBar.close,
      timestamp: replay.currentBar.timestamp,
    );
    _trades[index] = closed;
    _balance += closed.realizedPnl;
    _enforceLossLock();
    return closed;
  }

  bool advanceTick() {
    if (_isLocked) {
      replay.pause();
      return false;
    }
    final advanced = replay.advanceTick();
    if (advanced) _enforceLossLock();
    return advanced;
  }

  void acknowledgeReview(String reviewId) {
    final review = _pendingReview;
    if (!_isLocked || review == null || review.id != reviewId) {
      throw StateError('The active backtest review must be acknowledged');
    }
    _lastAcknowledgedReview = review.acknowledge();
    _pendingReview = null;
    _isLocked = false;
    _lossReferenceEquity = equity;
  }

  BacktestSimulationSnapshot get snapshot => BacktestSimulationSnapshot(
    replay: replay.snapshot,
    initialBalance: initialBalance,
    maxLossAmount: maxLossAmount,
    contractSize: contractSize,
    balance: _balance,
    lossReferenceEquity: _lossReferenceEquity,
    trades: _trades,
    isLocked: _isLocked,
    pendingReview: _pendingReview,
    lastAcknowledgedReview: _lastAcknowledgedReview,
  );

  void _enforceLossLock() {
    final loss = _lossReferenceEquity - equity;
    if (_isLocked || loss < maxLossAmount) return;
    _isLocked = true;
    replay.pause();
    _pendingReview = BacktestSessionReview.triggered(
      sessionId: replay.sessionId,
      timestamp: replay.currentBar.timestamp,
      lossAmount: loss,
      closedTradeCount: _trades.where((trade) => !trade.isOpen).length,
    );
  }

  void _validateConfiguration() {
    if (!initialBalance.isFinite ||
        initialBalance <= 0 ||
        !maxLossAmount.isFinite ||
        maxLossAmount <= 0 ||
        !contractSize.isFinite ||
        contractSize <= 0) {
      throw ArgumentError('Invalid backtest simulation configuration');
    }
  }

  void _validateRestoredState() {
    if (!_balance.isFinite ||
        !_lossReferenceEquity.isFinite ||
        _trades.any((trade) => trade.contractSize != contractSize) ||
        _trades.map((trade) => trade.id).toSet().length != _trades.length ||
        (_isLocked != (_pendingReview != null)) ||
        (_pendingReview != null &&
            (_pendingReview!.sessionId != replay.sessionId ||
                _pendingReview!.isAcknowledged)) ||
        (_lastAcknowledgedReview != null &&
            (!_lastAcknowledgedReview!.isAcknowledged ||
                _lastAcknowledgedReview!.sessionId != replay.sessionId))) {
      throw const FormatException('Invalid restored backtest simulation state');
    }
    final expectedBalance =
        initialBalance +
        _trades.fold<double>(0, (sum, trade) => sum + trade.realizedPnl);
    if ((_balance - expectedBalance).abs() > 0.0000001) {
      throw const FormatException('Backtest balance does not reconcile');
    }
    final prices = {
      for (final bar in replay.visibleBars) bar.timestamp: bar.close,
    };
    if (_trades.any(
          (trade) =>
              prices[trade.entryTimestamp] != trade.entryPrice ||
              (trade.exitTimestamp != null &&
                  prices[trade.exitTimestamp] != trade.exitPrice),
        ) ||
        (_pendingReview != null &&
            _pendingReview!.triggeredAtTimestamp >
                replay.currentBar.timestamp) ||
        (_lastAcknowledgedReview != null &&
            _lastAcknowledgedReview!.triggeredAtTimestamp >
                replay.currentBar.timestamp)) {
      throw const FormatException(
        'Backtest execution is outside visible history',
      );
    }
  }
}

/// Private training recording; it is not verified broker performance.
class BacktestRecording {
  final List<BacktestBar> bars;
  final BacktestSimulationSnapshot simulation;

  BacktestRecording({required List<BacktestBar> bars, required this.simulation})
    : bars = List<BacktestBar>.unmodifiable(bars);

  factory BacktestRecording.fromMap(
    Map<String, dynamic> map, {
    required String sessionId,
  }) {
    final bars = map['bars'];
    final simulation = map['simulation'];
    if (map['version'] != 1 ||
        bars is! List ||
        bars.isEmpty ||
        bars.length > 3000 ||
        simulation is! Map) {
      throw const FormatException('Invalid backtest recording');
    }
    try {
      final recording = BacktestRecording(
        bars: bars
            .map(
              (bar) =>
                  BacktestBar.fromMap(Map<String, dynamic>.from(bar as Map)),
            )
            .toList(),
        simulation: BacktestSimulationSnapshot.fromMap(
          Map<String, dynamic>.from(simulation),
        ),
      );
      if (recording.simulation.replay.sessionId != sessionId) {
        throw const FormatException('Backtest recording identity mismatch');
      }
      recording.restore();
      return recording;
    } on TypeError {
      throw const FormatException('Invalid backtest recording');
    } on ArgumentError {
      throw const FormatException('Invalid backtest recording');
    }
  }

  BacktestSimulationEngine restore() => BacktestSimulationEngine.restore(
    snapshot: simulation,
    bars: bars,
    expectedSessionId: simulation.replay.sessionId,
    expectedSymbol: simulation.replay.symbol,
    expectedSourceId: simulation.replay.sourceId,
  );

  Map<String, dynamic> toMap() => {
    'version': 1,
    'bars': bars.map((bar) => bar.toMap()).toList(),
    'simulation': simulation.toMap(),
  };
}

class BacktestSession extends Equatable {
  final String? id;
  final String symbol;
  final DateTime startTime;
  final DateTime endTime;
  final double initialBalance;
  final double currentBalance;
  final double equity;
  final double openPL;
  final int speed; // 1, 5, 10
  final bool isPlaying;
  final bool isLocked;

  const BacktestSession({
    this.id,
    required this.symbol,
    required this.startTime,
    required this.endTime,
    required this.initialBalance,
    required this.currentBalance,
    required this.equity,
    required this.openPL,
    required this.speed,
    required this.isPlaying,
    this.isLocked = false,
  });

  @override
  List<Object?> get props => [
    id,
    symbol,
    currentBalance,
    equity,
    speed,
    isPlaying,
    isLocked,
  ];
}

class BacktestTrade extends Equatable {
  final String? id;
  final String symbol;
  final String type; // 'BUY', 'SELL'
  final double entryPrice;
  final double currentPrice;
  final double volume;
  final double profit;
  final DateTime openTime;

  // Legacy field aliases for backward compatibility
  double get openPrice => entryPrice;
  double get lotSize => volume;
  double get currentProfit => profit;

  const BacktestTrade({
    this.id,
    this.symbol = '',
    required this.type,
    required this.entryPrice,
    required this.currentPrice,
    required this.volume,
    required this.profit,
    required this.openTime,
  });

  @override
  List<Object?> get props => [id, type, entryPrice, profit];
}
