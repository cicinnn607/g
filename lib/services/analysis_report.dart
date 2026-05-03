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

class AnalysisReport {
  final List<DailyGlucoseStat> dailyStats;
  final WeeklySummaryMetrics weeklySummaryMetrics;
  final List<FoodImpactSignal> foodSignals;
  final List<EnergyCorrelationItem> energyCorrelation;
  final AnalysisDataQuality dataQuality;
  final String summaryText;

  const AnalysisReport({
    required this.dailyStats,
    required this.weeklySummaryMetrics,
    required this.foodSignals,
    required this.energyCorrelation,
    required this.dataQuality,
    required this.summaryText,
  });

  bool get hasRemoteData =>
      dailyStats.isNotEmpty ||
      foodSignals.isNotEmpty ||
      weeklySummaryMetrics.readingCount > 0;

  factory AnalysisReport.fromMap(Map<String, dynamic> map) {
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
      summaryText: _stringValue(map['summary_text']).trim(),
    );
  }

  static const empty = AnalysisReport(
    dailyStats: [],
    weeklySummaryMetrics: WeeklySummaryMetrics.empty,
    foodSignals: [],
    energyCorrelation: [],
    dataQuality: AnalysisDataQuality.empty,
    summaryText: '',
  );
}
