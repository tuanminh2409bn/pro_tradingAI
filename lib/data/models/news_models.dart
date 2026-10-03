import 'package:equatable/equatable.dart';

class NewsArticle extends Equatable {
  final String title;
  final String source;
  final String timeAgo;
  final int? sentimentScore;
  final String type; // 'FOREXFACTORY', 'TWITTER', 'ALERT', 'OFFICIAL'
  final String impact; // 'HIGH', 'MEDIUM', 'LOW'
  final String summary;
  final String url;
  final String imageUrl;
  final ScheduledNewsEvent? scheduledEvent;

  const NewsArticle({
    required this.title,
    required this.source,
    required this.timeAgo,
    required this.sentimentScore,
    required this.type,
    this.impact = 'LOW',
    this.summary = '',
    this.url = '',
    this.imageUrl = '',
    this.scheduledEvent,
  });

  @override
  List<Object?> get props => [
    title,
    source,
    timeAgo,
    sentimentScore,
    type,
    impact,
    summary,
    url,
    imageUrl,
    scheduledEvent,
  ];
}

class ScheduledNewsEvent extends Equatable {
  final String eventId;
  final int startTime;
  final double durationMinutes;
  final String label;
  final String color;
  final List<String> currencies;
  final Map<String, dynamic> evidence;

  const ScheduledNewsEvent({
    required this.eventId,
    required this.startTime,
    required this.durationMinutes,
    required this.label,
    required this.color,
    required this.currencies,
    required this.evidence,
  });

  int get endTime => startTime + (durationMinutes * 60).round();

  @override
  List<Object?> get props => [
    eventId,
    startTime,
    durationMinutes,
    label,
    color,
    currencies,
    evidence,
  ];
}

class SentimentPulse extends Equatable {
  final int globalScore;
  final double fearPercent;
  final double neutralPercent;
  final double greedPercent;
  final String phase; // 'GREED', 'FEAR', 'NEUTRAL'
  final bool isAvailable;

  const SentimentPulse({
    required this.globalScore,
    required this.fearPercent,
    required this.neutralPercent,
    required this.greedPercent,
    required this.phase,
    this.isAvailable = true,
  });

  const SentimentPulse.unavailable()
    : globalScore = 0,
      fearPercent = 0,
      neutralPercent = 0,
      greedPercent = 0,
      phase = 'UNAVAILABLE',
      isAvailable = false;

  @override
  List<Object?> get props => [
    globalScore,
    fearPercent,
    neutralPercent,
    greedPercent,
    phase,
    isAvailable,
  ];
}

const _scenarioTradeKeys = {
  'entry',
  'entryprice',
  'sl',
  'stoploss',
  'tp',
  'takeprofit',
  'volume',
  'lot',
  'execute',
  'execution',
  'order',
  'tradeaction',
};

String _normalizedScenarioKey(Object? value) =>
    value.toString().toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

bool _containsScenarioTradeInstruction(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (_scenarioTradeKeys.contains(_normalizedScenarioKey(entry.key)) ||
          _containsScenarioTradeInstruction(entry.value)) {
        return true;
      }
    }
  } else if (value is Iterable) {
    return value.any(_containsScenarioTradeInstruction);
  }
  return false;
}

String? _scenarioText(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

List<String>? _scenarioTextList(Object? value, {required bool allowEmpty}) {
  if (value is! List) return null;
  final result = <String>[];
  for (final item in value) {
    final text = _scenarioText(item);
    if (text == null) return null;
    result.add(text);
  }
  return result.isEmpty && !allowEmpty ? null : result;
}

class NewsScenarioPath extends Equatable {
  final List<String> conditions;
  final List<String> projectedReactions;

  const NewsScenarioPath({
    required this.conditions,
    required this.projectedReactions,
  });

  static NewsScenarioPath? fromMap(Object? value, {required bool fallback}) {
    if (value is! Map) return null;
    final conditions = _scenarioTextList(
      value['conditions'],
      allowEmpty: fallback,
    );
    final reactions = _scenarioTextList(
      value['projected_reactions'],
      allowEmpty: fallback,
    );
    if (conditions == null || reactions == null) return null;
    return NewsScenarioPath(
      conditions: conditions,
      projectedReactions: reactions,
    );
  }

  @override
  List<Object?> get props => [conditions, projectedReactions];
}

class NewsScenario extends Equatable {
  static const emptyPath = NewsScenarioPath(
    conditions: [],
    projectedReactions: [],
  );

  final String scenarioId;
  final List<String> assumptions;
  final List<String> affectedAssets;
  final NewsScenarioPath bullishPath;
  final NewsScenarioPath bearishPath;
  final List<String> invalidation;
  final String riskNotice;
  final bool fallback;
  final String? contractError;

  const NewsScenario({
    required this.scenarioId,
    required this.assumptions,
    required this.affectedAssets,
    required this.bullishPath,
    required this.bearishPath,
    required this.invalidation,
    required this.riskNotice,
    required this.fallback,
    this.contractError,
  });

  bool get isValid => contractError == null;

  factory NewsScenario.fromMap(Map<String, dynamic> map) {
    if (_containsScenarioTradeInstruction(map)) {
      return NewsScenario.invalid('trade_instruction_forbidden');
    }
    final fallback = map['fallback'];
    if (fallback is! bool) {
      return NewsScenario.invalid('invalid_fallback_state');
    }
    final scenarioId = _scenarioText(map['scenario_id']);
    final assumptions = _scenarioTextList(
      map['assumptions'],
      allowEmpty: fallback,
    );
    final rawAssets = map['affected_assets'];
    final affectedAssets = _scenarioTextList(rawAssets, allowEmpty: false);
    final bullishPath = NewsScenarioPath.fromMap(
      map['bullish_path'],
      fallback: fallback,
    );
    final bearishPath = NewsScenarioPath.fromMap(
      map['bearish_path'],
      fallback: fallback,
    );
    final invalidation = _scenarioTextList(
      map['invalidation'],
      allowEmpty: fallback,
    );
    final riskNotice = _scenarioText(map['risk_notice']);
    if (scenarioId == null ||
        assumptions == null ||
        affectedAssets == null ||
        bullishPath == null ||
        bearishPath == null ||
        invalidation == null ||
        riskNotice == null) {
      return NewsScenario.invalid('invalid_response_shape');
    }

    return NewsScenario(
      scenarioId: scenarioId,
      assumptions: assumptions,
      affectedAssets: affectedAssets,
      bullishPath: bullishPath,
      bearishPath: bearishPath,
      invalidation: invalidation,
      riskNotice: riskNotice,
      fallback: fallback,
    );
  }

  factory NewsScenario.invalid(String error) => NewsScenario(
    scenarioId: '',
    assumptions: const [],
    affectedAssets: const [],
    bullishPath: emptyPath,
    bearishPath: emptyPath,
    invalidation: const [],
    riskNotice: '',
    fallback: true,
    contractError: error,
  );

  @override
  List<Object?> get props => [
    scenarioId,
    assumptions,
    affectedAssets,
    bullishPath,
    bearishPath,
    invalidation,
    riskNotice,
    fallback,
    contractError,
  ];
}
