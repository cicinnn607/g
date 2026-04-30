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
    List<Map<String, dynamic>> glucoseRecords,
  ) {
    if (mealItems.isEmpty) {
      return const [
        FoodSignal(name: '全麦早餐', level: 'green', reason: '更适合做稳定能量的底子'),
        FoodSignal(name: '盖饭/炒饭', level: 'red', reason: '容易把餐后血糖拉得比较快'),
        FoodSignal(name: '鱼虾蔬菜', level: 'green', reason: '蛋白质和蔬菜更容易扛饿'),
      ];
    }

    final seen = <String>{};
    final result = <FoodSignal>[];
    for (final item in mealItems) {
      final name = '${item['food_name_confirmed'] ?? item['name'] ?? '这餐'}';
      if (seen.contains(name)) continue;
      seen.add(name);
      final calories =
          double.tryParse(
            '${item['calories_final'] ?? item['calories'] ?? 0}',
          ) ??
          0;
      result.add(classifyFood(name, calories));
      if (result.length == 4) break;
    }
    return result;
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
