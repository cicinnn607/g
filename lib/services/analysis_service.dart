class FoodSignal {
  final String name;
  final String level;
  final String reason;

  const FoodSignal({
    required this.name,
    required this.level,
    required this.reason,
  });

  bool get isGreen => level == 'green';
  bool get isYellow => level == 'yellow';
  bool get isRed => level == 'red';
}

class ManualInsight {
  final String headline;
  final String observation;
  final String possibleCause;
  final String nextStep;
  final String exerciseTip;

  const ManualInsight({
    required this.headline,
    required this.observation,
    required this.possibleCause,
    required this.nextStep,
    required this.exerciseTip,
  });
}

class AnalysisService {
  static const List<String> _redKeywords = [
    '奶茶',
    '甜',
    '糖',
    '蛋糕',
    '炒饭',
    '盖饭',
    '白米',
    '米饭',
    '粥',
    '面条',
    '面包',
    '炸',
  ];

  static const List<String> _greenKeywords = [
    '全麦',
    '糙米',
    '燕麦',
    '鱼',
    '虾',
    '鸡胸',
    '豆腐',
    '蔬菜',
    '沙拉',
    '鸡蛋',
    '牛奶',
  ];

  static double calculateMealCalories(num caloriesRaw, num portionSize) {
    final result = caloriesRaw * portionSize;
    return double.parse(result.toStringAsFixed(1));
  }

  static double calculateMealCaloriesByGrams(
    num? caloriesPer100g,
    num? grams,
  ) {
    final calories = (caloriesPer100g ?? 0).toDouble();
    final weight = (grams ?? 0).toDouble();
    if (calories <= 0 || weight <= 0) return 0;
    return double.parse((calories * weight / 100).toStringAsFixed(1));
  }

  static double resolveMealItemCalories({
    num? caloriesPer100g,
    num? grams,
    num? caloriesUserOverride,
  }) {
    final override = caloriesUserOverride?.toDouble();
    if (override != null && override >= 0) {
      return double.parse(override.toStringAsFixed(1));
    }
    return calculateMealCaloriesByGrams(caloriesPer100g, grams);
  }

  static int calculateExerciseCalories(
    num met,
    num weight,
    int durationMinutes,
  ) {
    if (met <= 0 || weight <= 0 || durationMinutes <= 0) return 0;
    return (met * weight * durationMinutes / 60).round();
  }

  static String glucoseStatus(double value) {
    if (value < 3.9) return '偏低';
    if (value > 10.0) return '偏高';
    return '平稳';
  }

  static List<FoodSignal> buildFoodSignals(
    List<Map<String, dynamic>> mealItems,
    List<Map<String, dynamic>> glucoseRecords, [
    List<Map<String, dynamic>> statusRecords = const [],
  ]) {
    if (mealItems.isEmpty) {
      return const [
        FoodSignal(
          name: '继续记录餐食',
          level: 'yellow',
          reason: '数据不足，建议记录餐后血糖以激活分析',
        ),
      ];
    }

    final mealObservations = _buildMealObservations(mealItems);
    if (mealObservations.isEmpty) {
      return const [
        FoodSignal(
          name: '继续记录餐食',
          level: 'yellow',
          reason: '数据不足，建议记录餐后血糖以激活分析',
        ),
      ];
    }

    _attachGlucoseToMeals(mealObservations, glucoseRecords);
    _attachStatusToMeals(mealObservations, statusRecords);

    final foodStats = <String, _FoodStats>{};
    for (final meal in mealObservations) {
      for (final name in meal.foodNames) {
        foodStats.putIfAbsent(name, () => _FoodStats(name)).addMeal(meal);
      }
    }

    final result = foodStats.values.map(_classifyFoodStats).toList()
      ..sort((a, b) {
        final rank = {'red': 0, 'yellow': 1, 'green': 2};
        final levelCompare = (rank[a.level] ?? 3).compareTo(rank[b.level] ?? 3);
        if (levelCompare != 0) return levelCompare;
        return a.name.compareTo(b.name);
      });

    if (result.isEmpty) {
      return const [
        FoodSignal(
          name: '继续记录餐食',
          level: 'yellow',
          reason: '数据不足，建议记录餐后血糖以激活分析',
        ),
      ];
    }
    return result.take(4).toList();
  }

  static List<_MealObservation> _buildMealObservations(
    List<Map<String, dynamic>> mealItems,
  ) {
    final byMeal = <String, _MealObservation>{};
    for (final item in mealItems) {
      final name =
          '${item['food_name_confirmed'] ?? item['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final mealId = '${item['meal_id'] ?? item['id'] ?? item.hashCode}';
      final mealTime = _parseDateTime(item['meal_time']);
      if (mealTime == null) continue;

      byMeal
          .putIfAbsent(mealId, () => _MealObservation(mealId, mealTime))
          .foodNames
          .add(name);
    }
    final meals = byMeal.values.toList()
      ..sort((a, b) => b.mealTime.compareTo(a.mealTime));
    return meals;
  }

  static void _attachGlucoseToMeals(
    List<_MealObservation> meals,
    List<Map<String, dynamic>> glucoseRecords,
  ) {
    for (final record in glucoseRecords) {
      final recordTime = _parseDateTime(record['record_time']);
      final value = double.tryParse('${record['value']}');
      if (recordTime == null || value == null) continue;

      final meal = _nearestMealInWindow(
        meals,
        recordTime,
        minMinutes: 30,
        maxMinutes: 180,
      );
      if (meal == null) continue;
      meal.glucoseCount += 1;
      if (value < 3.9) {
        meal.lowGlucoseCount += 1;
      } else if (value > 10.0) {
        meal.highGlucoseCount += 1;
      } else {
        meal.stableGlucoseCount += 1;
      }
    }
  }

  static void _attachStatusToMeals(
    List<_MealObservation> meals,
    List<Map<String, dynamic>> statusRecords,
  ) {
    final mealsById = {for (final meal in meals) meal.mealId: meal};
    for (final record in statusRecords) {
      final directMealId = record['related_meal_id'];
      var meal = directMealId == null ? null : mealsById['$directMealId'];

      if (meal == null) {
        final recordTime = _parseDateTime(record['record_time']);
        if (recordTime == null) continue;
        meal = _nearestMealInWindow(
          meals,
          recordTime,
          minMinutes: 0,
          maxMinutes: 240,
        );
      }
      if (meal == null) continue;

      final status = '${record['status_level'] ?? ''}';
      if (status == '极度疲劳' || status == '略感疲惫') {
        meal.badStatusCount += 1;
      } else if (status == '感觉不错' || status == '精力充沛') {
        meal.goodStatusCount += 1;
      }
    }
  }

  static _MealObservation? _nearestMealInWindow(
    List<_MealObservation> meals,
    DateTime recordTime, {
    required int minMinutes,
    required int maxMinutes,
  }) {
    _MealObservation? nearest;
    for (final meal in meals) {
      final minutes = recordTime.difference(meal.mealTime).inMinutes;
      if (minutes < minMinutes || minutes > maxMinutes) continue;
      if (nearest == null || meal.mealTime.isAfter(nearest.mealTime)) {
        nearest = meal;
      }
    }
    return nearest;
  }

  static FoodSignal _classifyFoodStats(_FoodStats stats) {
    if (stats.glucoseCount == 0) {
      return FoodSignal(
        name: stats.name,
        level: 'yellow',
        reason: '数据不足，建议记录餐后血糖以激活分析',
      );
    }

    final unstableCount = stats.highGlucoseCount + stats.lowGlucoseCount;
    if (unstableCount >= 2 || (unstableCount >= 1 && stats.badStatusCount >= 2)) {
      return FoodSignal(
        name: stats.name,
        level: 'red',
        reason: '多次关联餐后波动或疲劳，建议减少频率并控制份量',
      );
    }

    if (stats.stableGlucoseCount >= 2 &&
        unstableCount == 0 &&
        stats.badStatusCount == 0) {
      return FoodSignal(
        name: stats.name,
        level: 'green',
        reason: '多次记录后血糖更平稳，可以继续保留',
      );
    }

    return FoodSignal(
      name: stats.name,
      level: 'yellow',
      reason: '可以吃，但不建议常吃，先控制份量并继续观察',
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    return DateTime.tryParse('$value');
  }

  static FoodSignal classifyFood(String name, num calories) {
    final hasRedKeyword = _redKeywords.any(name.contains);
    final hasGreenKeyword = _greenKeywords.any(name.contains);

    if (hasRedKeyword && calories >= 300) {
      return FoodSignal(
        name: name,
        level: 'red',
        reason: '下一次可以少一点主食量，或加点蛋白质和蔬菜',
      );
    }
    if (hasGreenKeyword || calories <= 280) {
      return FoodSignal(name: name, level: 'green', reason: '目前看起来比较稳，可以继续保留');
    }
    return FoodSignal(name: name, level: 'yellow', reason: '影响可能看份量，先观察餐后状态');
  }

  static String buildExerciseSuggestion(
    List<Map<String, dynamic>> glucoseRecords,
    List<Map<String, dynamic>> meals,
    List<Map<String, dynamic>> exercises,
  ) {
    final latestGlucose = glucoseRecords.isEmpty
        ? 0.0
        : double.tryParse('${glucoseRecords.first['value']}') ?? 0.0;
    final recentExerciseMinutes = exercises.fold<int>(
      0,
      (sum, item) => sum + (int.tryParse('${item['duration']}') ?? 0),
    );

    if (latestGlucose >= 7.8) {
      return '最近一次血糖偏高，下一餐后先试 10-15 分钟慢走，重点是让身体动起来。';
    }
    if (recentExerciseMinutes < 30) {
      return '这两天运动记录偏少，可以从饭后散步 12 分钟开始，不需要一下子练很猛。';
    }
    if (meals.isEmpty) {
      return '先补几条饮食记录，后面会更容易看出哪种饭后状态更稳。';
    }
    return '目前节奏不错，继续保留饭后轻活动，重点看下午精力有没有更稳。';
  }

  static ManualInsight buildManualInsight({
    required List<Map<String, dynamic>> glucoseRecords,
    required List<Map<String, dynamic>> meals,
    required List<Map<String, dynamic>> exercises,
    required List<Map<String, dynamic>> statuses,
  }) {
    if (glucoseRecords.isEmpty) {
      return const ManualInsight(
        headline: '先记录几次血糖',
        observation: '现在血糖数据还不够，暂时只能看饮食、运动和状态本身。',
        possibleCause: '手动记录最有价值的点，是固定在早餐后或午餐后 2 小时测几次。',
        nextStep: '这周先选一个固定时段，连续记 3 天。',
        exerciseTip: '饭后轻走 10 分钟就够，先把习惯留下来。',
      );
    }

    final values = glucoseRecords
        .map((e) => double.tryParse('${e['value']}') ?? 0.0)
        .where((value) => value > 0)
        .toList();
    final latest = values.isEmpty ? 0.0 : values.first;
    final max = values.fold<double>(latest, (a, b) => a > b ? a : b);
    final min = values.fold<double>(latest, (a, b) => a < b ? a : b);
    final spread = max - min;
    final latestStatus = glucoseStatus(latest);
    final statusText = statuses.isEmpty
        ? '还没有状态记录'
        : '${statuses.first['status_level']}';

    final headline = latestStatus == '平稳' ? '今天整体比较稳' : '今天有一点波动';
    final observation =
        '最近血糖在 ${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)} mmol/L 之间，最新一次是 ${latest.toStringAsFixed(1)}，状态记录显示$statusText。';
    final cause = spread >= 3
        ? '波动偏大时，通常要回头看上一餐主食量、甜饮和饭后有没有久坐。'
        : '波动不大，说明最近的饮食份量和活动节奏大体能接住。';
    final nextStep = meals.isEmpty
        ? '下一步先把每餐大概吃了什么补上，分析会更准。'
        : '下一次遇到容易困或饿得快的餐，给它打个状态标签，后面就能看出规律。';
    final exerciseTip = buildExerciseSuggestion(
      glucoseRecords,
      meals,
      exercises,
    );

    return ManualInsight(
      headline: headline,
      observation: observation,
      possibleCause: cause,
      nextStep: nextStep,
      exerciseTip: exerciseTip,
    );
  }
}

class _MealObservation {
  final String mealId;
  final DateTime mealTime;
  final Set<String> foodNames = {};
  int glucoseCount = 0;
  int highGlucoseCount = 0;
  int lowGlucoseCount = 0;
  int stableGlucoseCount = 0;
  int badStatusCount = 0;
  int goodStatusCount = 0;

  _MealObservation(this.mealId, this.mealTime);
}

class _FoodStats {
  final String name;
  int glucoseCount = 0;
  int highGlucoseCount = 0;
  int lowGlucoseCount = 0;
  int stableGlucoseCount = 0;
  int badStatusCount = 0;
  int goodStatusCount = 0;

  _FoodStats(this.name);

  void addMeal(_MealObservation meal) {
    glucoseCount += meal.glucoseCount;
    highGlucoseCount += meal.highGlucoseCount;
    lowGlucoseCount += meal.lowGlucoseCount;
    stableGlucoseCount += meal.stableGlucoseCount;
    badStatusCount += meal.badStatusCount;
    goodStatusCount += meal.goodStatusCount;
  }
}
