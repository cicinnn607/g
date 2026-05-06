double? _optionalDouble(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return null;
  return double.tryParse('$value');
}

int _intValue(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return 0;
  return int.tryParse('$value') ?? (double.tryParse('$value')?.round() ?? 0);
}

String _stringValue(Object? value) => value == null ? '' : '$value';

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _mapListValue(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

bool _hasForbiddenMedicalText(String value) {
  return RegExp(r'糖尿病|确诊|诊断|服药|用药|药物|胰岛素|就医|医院|治疗|处方').hasMatch(value);
}

String _safeText(Object? value, [String fallback = '']) {
  final text = _stringValue(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty || _hasForbiddenMedicalText(text)) return fallback;
  return text;
}

class DailyGlucoseStat {
  final String recordDate;
  final int readingCount;
  final double? avgGlucose;
  final double? stdGlucose;
  final double? cv;
  final double? inRangeRatio;
  final double? rangeGlucose;
  final double? minGlucose;
  final double? maxGlucose;

  const DailyGlucoseStat({
    required this.recordDate,
    required this.readingCount,
    this.avgGlucose,
    this.stdGlucose,
    this.cv,
    this.inRangeRatio,
    this.rangeGlucose,
    this.minGlucose,
    this.maxGlucose,
  });

  factory DailyGlucoseStat.fromMap(Map<String, dynamic> map) {
    return DailyGlucoseStat(
      recordDate: _stringValue(map['record_date']),
      readingCount: _intValue(map['reading_count']),
      avgGlucose: _optionalDouble(map['avg_glucose']),
      stdGlucose: _optionalDouble(map['std_glucose']),
      cv: _optionalDouble(map['cv']),
      inRangeRatio: _optionalDouble(map['in_range_ratio']),
      rangeGlucose: _optionalDouble(map['range_glucose']),
      minGlucose: _optionalDouble(map['min_glucose']),
      maxGlucose: _optionalDouble(map['max_glucose']),
    );
  }
}

class WeeklySummaryMetrics {
  final int readingCount;
  final int validDayCount;
  final double? avgGlucose;
  final double? stdGlucose;
  final double? cv;
  final double? inRangeRatio;
  final double? rangeGlucose;
  final double? minGlucose;
  final double? maxGlucose;

  const WeeklySummaryMetrics({
    required this.readingCount,
    required this.validDayCount,
    this.avgGlucose,
    this.stdGlucose,
    this.cv,
    this.inRangeRatio,
    this.rangeGlucose,
    this.minGlucose,
    this.maxGlucose,
  });

  factory WeeklySummaryMetrics.fromMap(Map<String, dynamic> map) {
    return WeeklySummaryMetrics(
      readingCount: _intValue(map['reading_count']),
      validDayCount: _intValue(map['valid_day_count']),
      avgGlucose: _optionalDouble(map['avg_glucose']),
      stdGlucose: _optionalDouble(map['std_glucose']),
      cv: _optionalDouble(map['cv']),
      inRangeRatio: _optionalDouble(map['in_range_ratio']),
      rangeGlucose: _optionalDouble(map['range_glucose']),
      minGlucose: _optionalDouble(map['min_glucose']),
      maxGlucose: _optionalDouble(map['max_glucose']),
    );
  }

  static const empty = WeeklySummaryMetrics(readingCount: 0, validDayCount: 0);
}

class FoodImpactSignal {
  final String foodName;
  final String signalLevel;
  final double? avgExcursion;
  final int mealCount;
  final String reason;

  const FoodImpactSignal({
    required this.foodName,
    required this.signalLevel,
    this.avgExcursion,
    required this.mealCount,
    required this.reason,
  });

  bool get isRed => signalLevel == 'red';
  bool get isYellow => signalLevel == 'yellow';
  bool get isGreen => signalLevel == 'green';

  factory FoodImpactSignal.fromMap(Map<String, dynamic> map) {
    return FoodImpactSignal(
      foodName: _stringValue(map['food_name']).trim(),
      signalLevel: _stringValue(map['signal_level']).trim().isEmpty
          ? 'yellow'
          : _stringValue(map['signal_level']).trim(),
      avgExcursion: _optionalDouble(map['avg_excursion']),
      mealCount: _intValue(map['meal_count']),
      reason: _stringValue(map['reason']).trim(),
    );
  }
}

class EnergyCorrelationItem {
  final String cvCategory;
  final double? avgEnergy;
  final int dayCount;
  final String insight;

  const EnergyCorrelationItem({
    required this.cvCategory,
    this.avgEnergy,
    required this.dayCount,
    required this.insight,
  });

  factory EnergyCorrelationItem.fromMap(Map<String, dynamic> map) {
    return EnergyCorrelationItem(
      cvCategory: _stringValue(map['cv_category']),
      avgEnergy: _optionalDouble(map['avg_energy']),
      dayCount: _intValue(map['day_count']),
      insight: _stringValue(map['insight']),
    );
  }
}

class AnalysisDataQuality {
  final int readingCount;
  final int validDayCount;
  final bool hasEnoughGlucose;
  final bool hasEnoughFoodSignals;
  final List<String> messages;

  const AnalysisDataQuality({
    required this.readingCount,
    required this.validDayCount,
    required this.hasEnoughGlucose,
    required this.hasEnoughFoodSignals,
    required this.messages,
  });

  factory AnalysisDataQuality.fromMap(Map<String, dynamic> map) {
    final rawMessages = map['messages'];
    return AnalysisDataQuality(
      readingCount: _intValue(map['reading_count']),
      validDayCount: _intValue(map['valid_day_count']),
      hasEnoughGlucose:
          map['has_enough_glucose'] == true ||
          '${map['has_enough_glucose']}'.toLowerCase() == 'true',
      hasEnoughFoodSignals:
          map['has_enough_food_signals'] == true ||
          '${map['has_enough_food_signals']}'.toLowerCase() == 'true',
      messages: rawMessages is List
          ? rawMessages.map((item) => '$item').toList()
          : const [],
    );
  }

  static const empty = AnalysisDataQuality(
    readingCount: 0,
    validDayCount: 0,
    hasEnoughGlucose: false,
    hasEnoughFoodSignals: false,
    messages: ['记录几次血糖和餐食后，这里会给出趋势分析。'],
  );
}

class AnalysisCardsOverall {
  final String title;
  final String summary;
  final String confidence;
  final String confidenceReason;

  const AnalysisCardsOverall({
    required this.title,
    required this.summary,
    required this.confidence,
    required this.confidenceReason,
  });

  factory AnalysisCardsOverall.fromMap(Map<String, dynamic> map) {
    final confidence = _stringValue(map['confidence']);
    return AnalysisCardsOverall(
      title: _safeText(map['title'], '本周重点'),
      summary: _safeText(map['summary'], '样本还少，建议继续记录餐食、血糖和状态来观察趋势。'),
      confidence: const ['low', 'medium', 'high'].contains(confidence)
          ? confidence
          : 'low',
      confidenceReason: _safeText(map['confidence_reason'], '基于当前记录完整度'),
    );
  }
}

class AnalysisDietCard {
  final String title;
  final String signal;
  final String evidence;
  final String suggestion;
  final String nextRecord;

  const AnalysisDietCard({
    required this.title,
    required this.signal,
    required this.evidence,
    required this.suggestion,
    required this.nextRecord,
  });

  factory AnalysisDietCard.fromMap(Map<String, dynamic> map) {
    final signal = _stringValue(map['signal']);
    return AnalysisDietCard(
      title: _safeText(map['title'], '饮食观察'),
      signal: const ['green', 'yellow', 'red', 'observe'].contains(signal)
          ? signal
          : 'observe',
      evidence: _safeText(map['evidence'], '样本还少，建议继续配对记录。'),
      suggestion: _safeText(map['suggestion'], '先控制份量，搭配蛋白质和蔬菜继续观察。'),
      nextRecord: _safeText(map['next_record'], '下次补餐后2小时血糖'),
    );
  }
}

class AnalysisExerciseCard {
  final String title;
  final String evidence;
  final String suggestion;

  const AnalysisExerciseCard({
    required this.title,
    required this.evidence,
    required this.suggestion,
  });

  factory AnalysisExerciseCard.fromMap(Map<String, dynamic> map) {
    return AnalysisExerciseCard(
      title: _safeText(map['title'], '饭后轻动'),
      evidence: _safeText(map['evidence'], '本周运动记录还可以继续补充。'),
      suggestion: _safeText(map['suggestion'], '先从饭后轻走10分钟开始观察状态。'),
    );
  }
}

class AnalysisNextStep {
  final String type;
  final String task;

  const AnalysisNextStep({required this.type, required this.task});

  factory AnalysisNextStep.fromMap(Map<String, dynamic> map) {
    final type = _stringValue(map['type']);
    return AnalysisNextStep(
      type: const ['glucose', 'diet', 'exercise', 'status'].contains(type)
          ? type
          : 'diet',
      task: _safeText(map['task'], '继续补充一条记录'),
    );
  }
}

class AnalysisCards {
  final AnalysisCardsOverall overall;
  final List<AnalysisDietCard> dietCards;
  final AnalysisExerciseCard exerciseCard;
  final List<AnalysisNextStep> nextSteps;
  final String safetyNote;
  final String source;
  final String? error;
  final String? cacheKey;

  const AnalysisCards({
    required this.overall,
    required this.dietCards,
    required this.exerciseCard,
    required this.nextSteps,
    required this.safetyNote,
    this.source = 'template',
    this.error,
    this.cacheKey,
  });

  bool get isLlm => source == 'llm';

  factory AnalysisCards.fromMap(Map<String, dynamic> map) {
    final rawCards = map['analysis_cards'];
    final cards = rawCards is Map && rawCards.isNotEmpty
        ? Map<String, dynamic>.from(rawCards)
        : map;
    final source = _stringValue(map['analysis_cards_source']).trim();
    final error = _stringValue(map['analysis_cards_error']).trim();
    final dietCards = _mapListValue(
      cards['diet_cards'],
    ).map(AnalysisDietCard.fromMap).toList();
    final nextSteps = _mapListValue(
      cards['next_steps'],
    ).map(AnalysisNextStep.fromMap).toList();
    return AnalysisCards(
      overall: AnalysisCardsOverall.fromMap(_mapValue(cards['overall'])),
      dietCards: dietCards.isEmpty
          ? const [
              AnalysisDietCard(
                title: '饮食观察',
                signal: 'observe',
                evidence: '样本还少，暂时看不出稳定规律。',
                suggestion: '先选择一餐固定记录餐后血糖和状态。',
                nextRecord: '餐后2小时补血糖',
              ),
            ]
          : dietCards,
      exerciseCard: AnalysisExerciseCard.fromMap(
        _mapValue(cards['exercise_card']),
      ),
      nextSteps: nextSteps.isEmpty
          ? const [AnalysisNextStep(type: 'glucose', task: '餐后2小时补血糖')]
          : nextSteps,
      safetyNote: _safeText(cards['safety_note'], '仅供生活习惯参考，不替代医疗建议。'),
      source: source.isEmpty ? _stringValue(cards['source']).trim() : source,
      error: error.isEmpty ? null : error,
      cacheKey: _stringValue(map['evidence_cache_key']).trim().isEmpty
          ? null
          : _stringValue(map['evidence_cache_key']).trim(),
    );
  }

  static const empty = AnalysisCards(
    overall: AnalysisCardsOverall(
      title: '本周重点',
      summary: '样本还少，建议继续记录餐食、血糖和状态来观察趋势。',
      confidence: 'low',
      confidenceReason: '样本还少',
    ),
    dietCards: [
      AnalysisDietCard(
        title: '饮食观察',
        signal: 'observe',
        evidence: '样本还少，暂时看不出稳定规律。',
        suggestion: '先选择一餐固定记录餐后血糖和状态。',
        nextRecord: '餐后2小时补血糖',
      ),
    ],
    exerciseCard: AnalysisExerciseCard(
      title: '饭后轻动',
      evidence: '本周运动记录还可以继续补充。',
      suggestion: '先从饭后轻走10分钟开始观察状态。',
    ),
    nextSteps: [AnalysisNextStep(type: 'glucose', task: '餐后2小时补血糖')],
    safetyNote: '仅供生活习惯参考，不替代医疗建议。',
  );
}

class AnalysisReport {
  final List<DailyGlucoseStat> dailyStats;
  final WeeklySummaryMetrics weeklySummaryMetrics;
  final List<FoodImpactSignal> foodSignals;
  final List<EnergyCorrelationItem> energyCorrelation;
  final AnalysisDataQuality dataQuality;
  final String summaryText;
  final String summarySource;
  final String? summaryError;

  const AnalysisReport({
    required this.dailyStats,
    required this.weeklySummaryMetrics,
    required this.foodSignals,
    required this.energyCorrelation,
    required this.dataQuality,
    required this.summaryText,
    required this.summarySource,
    this.summaryError,
  });

  bool get hasRemoteData =>
      dailyStats.isNotEmpty ||
      foodSignals.isNotEmpty ||
      weeklySummaryMetrics.readingCount > 0;

  factory AnalysisReport.fromMap(Map<String, dynamic> map) {
    final summaryText = _stringValue(map['summary_text']).trim();
    final source = _stringValue(map['summary_source']).trim();
    final error = _stringValue(map['summary_error']).trim();
    return AnalysisReport(
      dailyStats: _mapListValue(
        map['daily_stats'],
      ).map(DailyGlucoseStat.fromMap).toList(),
      weeklySummaryMetrics: WeeklySummaryMetrics.fromMap(
        _mapValue(map['weekly_summary_metrics']),
      ),
      foodSignals: _mapListValue(map['food_signals'])
          .map(FoodImpactSignal.fromMap)
          .where((item) {
            return item.foodName.isNotEmpty;
          })
          .toList(),
      energyCorrelation: _mapListValue(
        map['energy_correlation'],
      ).map(EnergyCorrelationItem.fromMap).toList(),
      dataQuality: AnalysisDataQuality.fromMap(_mapValue(map['data_quality'])),
      summaryText: summaryText,
      summarySource: source.isEmpty
          ? (summaryText.isEmpty ? 'template' : 'llm')
          : source,
      summaryError: error.isEmpty ? null : error,
    );
  }

  static const empty = AnalysisReport(
    dailyStats: [],
    weeklySummaryMetrics: WeeklySummaryMetrics.empty,
    foodSignals: [],
    energyCorrelation: [],
    dataQuality: AnalysisDataQuality.empty,
    summaryText: '',
    summarySource: 'template',
  );
}
