import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:glucose_assistant/core/app_messages.dart';
import 'package:glucose_assistant/pages/exercise_page.dart';
import 'package:glucose_assistant/provider/health_provider.dart';
import 'package:glucose_assistant/services/analysis_service.dart';
import 'package:glucose_assistant/services/health_repository.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('按份量系数计算饮食热量', () {
    expect(AnalysisService.calculateMealCalories(430, 1.2), 516.0);
  });

  test('按每100g热量和克重计算饮食热量', () {
    expect(AnalysisService.calculateMealCaloriesByGrams(116, 150), 174.0);
    expect(AnalysisService.calculateMealCaloriesByGrams(null, 150), 0);
    expect(AnalysisService.calculateMealCaloriesByGrams(116, null), 0);
    expect(AnalysisService.calculateMealCaloriesByGrams(116, 0), 0);
  });

  test('用户覆盖热量优先于每100g公式', () {
    expect(
      AnalysisService.resolveMealItemCalories(
        caloriesPer100g: 116,
        grams: 150,
        caloriesUserOverride: 200,
      ),
      200.0,
    );
    expect(
      AnalysisService.resolveMealItemCalories(caloriesPer100g: 116, grams: 150),
      174.0,
    );
  });

  test('常见份量摘要优先显示份量标签', () {
    final summary = HealthRepository.formatMealItemServingSummary({
      'food_name_confirmed': '米饭',
      'grams': 150,
      'serving_unit': '1标准碗',
      'calories_final': 174,
    });

    expect(summary, '米饭 · 1标准碗 · 174 kcal');
  });

  test('手动克重摘要显示克重', () {
    final summary = HealthRepository.formatMealItemServingSummary({
      'food_name_confirmed': '米饭',
      'grams': 150,
      'serving_unit': 'g',
      'calories_final': 174,
    });

    expect(summary, '米饭 · 150g · 174 kcal');
  });

  test('食物库行解析支持模糊命中煎牛排', () {
    final item = FoodCalorieCatalogItem.fromMap({
      'id': 'food_1',
      'name': '煎牛排',
      'aliases': ['牛排'],
      'calories_per_100g': 180,
      'serving_options': {'1掌心': 100, '半掌心': 50},
      'similarity_score': 0.7,
    });

    expect(item.name, '煎牛排');
    expect(item.aliases, contains('牛排'));
    expect(item.servingOptions['1掌心'], 100);
    expect(item.caloriesPer100g, 180);
  });

  test('meal_items 升级 migration 保留旧最终热量并重建公式', () {
    final migration = _readMealUpgradeMigration();

    expect(migration, contains('set calories_user_override = calories_final'));
    expect(
      migration,
      contains('coalesce(calories_raw, 0) * coalesce(grams, 0) / 100'),
    );
  });

  test('Bucket not found 显示明确的 meal-images 配置提示', () {
    expect(
      friendlyMealRecognitionError(Exception('Bucket not found: meal-images')),
      contains('食物图片存储桶未配置'),
    );
  });

  test('百度 secrets 缺失显示识别服务配置提示', () {
    expect(
      friendlyMealRecognitionError(Exception('Missing env: BAIDU_API_KEY')),
      contains('识别服务缺少百度 API 配置'),
    );
  });

  test('按 MET、体重和分钟计算运动消耗', () {
    expect(AnalysisService.calculateExerciseCalories(4.3, 65, 30), 140);
  });

  test('红绿灯食物分类更偏日常建议', () {
    final red = AnalysisService.classifyFood('炒饭', 650);
    final green = AnalysisService.classifyFood('鸡胸肉沙拉', 260);

    expect(red.isRed, isTrue);
    expect(green.isGreen, isTrue);
  });

  test('无配对血糖时食物先标记为黄灯', () {
    final signals = AnalysisService.buildFoodSignals([
      _mealItem('meal_1', '米饭', DateTime(2026, 4, 30, 12)),
    ], const []);

    expect(signals.single.isYellow, isTrue);
    expect(signals.single.reason, contains('数据不足'));
  });

  test('重叠餐次窗口内血糖归因给最近一餐', () {
    final day1Lunch = DateTime(2026, 4, 29, 12);
    final day1Snack = DateTime(2026, 4, 29, 13, 30);
    final day2Lunch = DateTime(2026, 4, 30, 12);
    final day2Snack = DateTime(2026, 4, 30, 13, 30);

    final signals = AnalysisService.buildFoodSignals(
      [
        _mealItem('lunch_1', '米饭', day1Lunch),
        _mealItem('snack_1', '蛋糕', day1Snack),
        _mealItem('lunch_2', '米饭', day2Lunch),
        _mealItem('snack_2', '蛋糕', day2Snack),
      ],
      [
        _glucose(12.1, DateTime(2026, 4, 29, 14)),
        _glucose(11.8, DateTime(2026, 4, 30, 14)),
      ],
    );

    final cake = signals.firstWhere((signal) => signal.name == '蛋糕');
    final rice = signals.firstWhere((signal) => signal.name == '米饭');
    expect(cake.isRed, isTrue);
    expect(rice.isYellow, isTrue);
  });

  test('多次平稳血糖和好状态关联时标记为绿灯', () {
    final day1 = DateTime(2026, 4, 29, 8);
    final day2 = DateTime(2026, 4, 30, 8);

    final signals = AnalysisService.buildFoodSignals(
      [
        _mealItem('breakfast_1', '燕麦牛奶', day1),
        _mealItem('breakfast_2', '燕麦牛奶', day2),
      ],
      [
        _glucose(6.2, DateTime(2026, 4, 29, 9, 30)),
        _glucose(6.5, DateTime(2026, 4, 30, 9, 30)),
      ],
      [
        _status('感觉不错', DateTime(2026, 4, 29, 10)),
        _status('精力充沛', DateTime(2026, 4, 30, 10)),
      ],
    );

    expect(signals.single.isGreen, isTrue);
  });

  test('极端血糖值参与红黄绿分析时不抛异常', () {
    final mealTime = DateTime(2026, 4, 30, 12);

    final signals = AnalysisService.buildFoodSignals(
      [_mealItem('meal_1', '奶茶', mealTime)],
      [
        _glucose(0.6, DateTime(2026, 4, 30, 13)),
        _glucose(33.3, DateTime(2026, 4, 30, 14)),
      ],
    );

    expect(signals.single.isRed, isTrue);
  });

  test('首页红绿灯无餐食时返回通用饮食建议', () {
    final signals = AnalysisService.buildHomeFoodSignals(const [], const []);

    expect(signals.length, 4);
    expect(signals.where((signal) => signal.isGreen), hasLength(2));
    expect(signals.where((signal) => signal.isYellow), hasLength(1));
    expect(signals.where((signal) => signal.isRed), hasLength(1));
    expect(
      signals.map((signal) => signal.reason).join(),
      isNot(contains('数据不足')),
    );
  });

  test('首页红绿灯少量餐食时混合用户食物和通用补位', () {
    final signals = AnalysisService.buildHomeFoodSignals([
      _mealItem('meal_1', '苹果', DateTime(2026, 4, 30, 12)),
      _mealItem('meal_2', '鸡蛋', DateTime(2026, 5, 1, 8)),
      _mealItem('meal_3', '面条', DateTime(2026, 5, 1, 12)),
    ], const []);

    expect(signals.length, 4);
    expect(
      signals.any((signal) => ['苹果', '鸡蛋', '面条'].contains(signal.name)),
      isTrue,
    );
    expect(signals.any((signal) => signal.name == '燕麦牛奶'), isTrue);
    expect(
      signals.map((signal) => signal.reason).join(),
      isNot(contains('数据不足')),
    );
    expect(signals.any((signal) => signal.reason.contains('已经记录过它')), isFalse);
  });

  test('首页红绿灯水果类会给自然建议', () {
    final signals = AnalysisService.buildHomeFoodSignals([
      _mealItem('meal_1', '苹果', DateTime(2026, 4, 30, 12)),
    ], const []);

    expect(signals.first.name, '苹果');
    expect(signals.first.reason, contains('别单吃'));
  });

  test('首页红绿灯足够数据时优先返回个人结果', () {
    final signals = AnalysisService.buildHomeFoodSignals(
      [
        _mealItem('oat_1', '燕麦牛奶', DateTime(2026, 4, 28, 8)),
        _mealItem('oat_2', '燕麦牛奶', DateTime(2026, 4, 29, 8)),
        _mealItem('cake_1', '蛋糕', DateTime(2026, 4, 28, 13)),
        _mealItem('cake_2', '蛋糕', DateTime(2026, 4, 29, 13)),
        _mealItem('rice_1', '米饭', DateTime(2026, 4, 30, 12)),
        _mealItem('noodle_1', '面条', DateTime(2026, 5, 1, 12)),
      ],
      [
        _glucose(6.2, DateTime(2026, 4, 28, 9, 30)),
        _glucose(6.4, DateTime(2026, 4, 29, 9, 30)),
        _glucose(11.5, DateTime(2026, 4, 28, 14)),
        _glucose(11.2, DateTime(2026, 4, 29, 14)),
      ],
    );

    expect(signals.first.name, '蛋糕');
    expect(signals.any((signal) => signal.name == '燕麦牛奶'), isTrue);
    expect(signals.first.reason, contains('波动'));
  });

  test('首页红绿灯长期单一饮食时补充多样化建议', () {
    final signals = AnalysisService.buildHomeFoodSignals(
      [
        _mealItem('rice_1', '米饭', DateTime(2026, 4, 25, 12)),
        _mealItem('rice_2', '米饭', DateTime(2026, 4, 26, 12)),
        _mealItem('rice_3', '米饭', DateTime(2026, 4, 27, 12)),
        _mealItem('rice_4', '米饭', DateTime(2026, 4, 28, 12)),
        _mealItem('rice_5', '米饭', DateTime(2026, 4, 29, 12)),
        _mealItem('rice_6', '米饭', DateTime(2026, 4, 30, 12)),
      ],
      [
        _glucose(6.2, DateTime(2026, 4, 29, 13, 30)),
        _glucose(6.4, DateTime(2026, 4, 30, 13, 30)),
      ],
    );

    expect(
      signals.any(
        (signal) =>
            signal.reason.contains('多样') || signal.reason.contains('均衡'),
      ),
      isTrue,
    );
  });

  test('首页红绿灯补位建议不会重复展示同名食物', () {
    final signals = AnalysisService.buildHomeFoodSignals([
      _mealItem('meal_1', '燕麦牛奶', DateTime(2026, 4, 30, 8)),
      _mealItem('meal_2', '白米饭', DateTime(2026, 4, 30, 12)),
      _mealItem('meal_3', '奶茶甜点', DateTime(2026, 4, 30, 15)),
    ], const []);

    final uniqueNames = signals.map((signal) => signal.name).toSet();
    expect(uniqueNames.length, signals.length);
  });

  test('首页提醒在无数据时返回记录引导', () {
    final reminder = AnalysisService.buildHomeReminder(
      glucoseRecords: const [],
      meals: const [],
      exercises: const [],
      statuses: const [],
      totalRecords: 0,
      now: DateTime(2026, 5, 1, 9),
    );

    expect(reminder, anyOf(contains('记录'), contains('一餐')));
  });

  test('首页提醒在刚吃完且无运动时提示轻走', () {
    final reminder = AnalysisService.buildHomeReminder(
      glucoseRecords: const [],
      meals: [_meal('meal_1', DateTime(2026, 5, 1, 12))],
      exercises: const [],
      statuses: const [],
      totalRecords: 2,
      now: DateTime(2026, 5, 1, 12, 50),
    );

    expect(reminder, anyOf(contains('走'), contains('饭后')));
  });

  test('首页提醒优先处理偏高血糖', () {
    final reminder = AnalysisService.buildHomeReminder(
      glucoseRecords: [_glucose(11.2, DateTime(2026, 5, 1, 12, 40))],
      meals: [_meal('meal_1', DateTime(2026, 5, 1, 12))],
      exercises: const [],
      statuses: const [],
      totalRecords: 3,
      now: DateTime(2026, 5, 1, 13),
    );

    expect(reminder, anyOf(contains('偏高'), contains('甜饮'), contains('主食')));
  });

  test('首页提醒会处理疲惫状态', () {
    final reminder = AnalysisService.buildHomeReminder(
      glucoseRecords: [_glucose(6.3, DateTime(2026, 5, 1, 8))],
      meals: [_meal('meal_1', DateTime(2026, 4, 30, 19))],
      exercises: [_exercise(DateTime(2026, 5, 1, 8, 20), 40)],
      statuses: [_status('略感疲惫', DateTime(2026, 5, 1, 9))],
      totalRecords: 5,
      now: DateTime(2026, 5, 1, 10),
    );

    expect(reminder, anyOf(contains('疲'), contains('困'), contains('状态')));
  });

  test('首页提醒同一输入同一天保持稳定', () {
    final first = AnalysisService.buildHomeReminder(
      glucoseRecords: [_glucose(6.3, DateTime(2026, 5, 1, 8))],
      meals: [_meal('meal_1', DateTime(2026, 4, 30, 19))],
      exercises: [_exercise(DateTime(2026, 5, 1, 8, 20), 40)],
      statuses: [_status('感觉不错', DateTime(2026, 5, 1, 9))],
      totalRecords: 6,
      now: DateTime(2026, 5, 1, 10),
    );
    final second = AnalysisService.buildHomeReminder(
      glucoseRecords: [_glucose(6.3, DateTime(2026, 5, 1, 8))],
      meals: [_meal('meal_1', DateTime(2026, 4, 30, 19))],
      exercises: [_exercise(DateTime(2026, 5, 1, 8, 20), 40)],
      statuses: [_status('感觉不错', DateTime(2026, 5, 1, 9))],
      totalRecords: 6,
      now: DateTime(2026, 5, 1, 18),
    );

    expect(second, first);
  });

  test('出生日期能换算成年龄', () {
    final today = DateTime.now();
    final birthday = '${today.year - 24}-01-01';
    expect(
      HealthRepository.ageFromBirthDate(birthday),
      greaterThanOrEqualTo(23),
    );
  });

  test('PGRST205 被识别为提醒表 schema 缺失', () {
    final error = PostgrestException(
      message:
          "Could not find the table 'public.reminder_settings' in the schema cache",
      code: 'PGRST205',
    );

    expect(isMissingSchemaError(error, table: 'reminder_settings'), isTrue);
    expect(
      friendlyActionError(error, action: '添加提醒'),
      contains('reminder_settings'),
    );
  });

  test('网络异常不会被当作提醒表缺失', () async {
    final repository = _NetworkReminderRepository();

    expect(
      isMissingSchemaError(
        Exception('SocketException: failed host lookup'),
        table: 'reminder_settings',
      ),
      isFalse,
    );
    await expectLater(repository.getRemindersIfAvailable(), throwsException);
  });

  test('提醒表缺失时读取提醒返回空列表', () async {
    final repository = _MissingReminderRepository();

    expect(await repository.getRemindersIfAvailable(), isEmpty);
  });

  test('刷新个人资料会更新性别', () async {
    final repository = _ProfileRepository();
    final provider = HealthProvider(repository: repository);

    await provider.refreshProfileData();

    expect(provider.gender, '女');
    expect(provider.displayName, '测试用户');
    expect(provider.weight, 58.5);
  });

  testWidgets('运动保存按钮防止连击', (tester) async {
    final repository = _SavingExerciseRepository();
    final provider = HealthProvider(repository: repository);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: ExerciseRecordPage()),
      ),
    );

    await tester.ensureVisible(find.text('保存运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存运动'));
    await tester.pump();
    await tester.tap(find.text('保存中'), warnIfMissed: false);
    await tester.pump();

    expect(repository.saveExerciseCalls, 1);

    repository.completeSave();
    await tester.pumpAndSettle();
  });
}

class _MissingReminderRepository extends HealthRepository {
  @override
  Future<List<Map<String, dynamic>>> getReminders() async {
    throw PostgrestException(
      message:
          "Could not find the table 'public.reminder_settings' in the schema cache",
      code: 'PGRST205',
    );
  }
}

class _NetworkReminderRepository extends HealthRepository {
  @override
  Future<List<Map<String, dynamic>>> getReminders() async {
    throw Exception('SocketException: failed host lookup');
  }
}

class _ProfileRepository extends HealthRepository {
  @override
  Future<Map<String, dynamic>> getProfile() async {
    return {
      'id': 'test-user',
      'display_name': '测试用户',
      'gender': '女',
      'height': 166.0,
      'birth_date': '2001-02-03',
    };
  }

  @override
  Future<Map<String, dynamic>?> getLatestBodyMetric() async {
    return {
      'id': 'metric_1',
      'user_id': 'test-user',
      'weight': 58.5,
      'record_time': DateTime(2026, 4, 30).toIso8601String(),
    };
  }
}

Map<String, dynamic> _mealItem(String mealId, String name, DateTime mealTime) {
  return {
    'id': '${mealId}_item',
    'meal_id': mealId,
    'food_name_confirmed': name,
    'meal_time': mealTime.toIso8601String(),
  };
}

Map<String, dynamic> _meal(String mealId, DateTime mealTime) {
  return {'id': mealId, 'meal_time': mealTime.toIso8601String()};
}

Map<String, dynamic> _glucose(double value, DateTime recordTime) {
  return {'value': value, 'record_time': recordTime.toIso8601String()};
}

Map<String, dynamic> _status(String level, DateTime recordTime) {
  return {'status_level': level, 'record_time': recordTime.toIso8601String()};
}

Map<String, dynamic> _exercise(DateTime exerciseTime, int duration) {
  return {
    'exercise_time': exerciseTime.toIso8601String(),
    'duration': duration,
  };
}

class _SavingExerciseRepository extends HealthRepository {
  int saveExerciseCalls = 0;
  final _saveCompleter = Completer<void>();

  @override
  Future<void> saveExercise({
    required String motionId,
    required int duration,
    required DateTime exerciseTime,
  }) async {
    saveExerciseCalls += 1;
    return _saveCompleter.future;
  }

  @override
  Future<HealthSnapshot> loadSnapshot() async {
    return HealthSnapshot(
      profile: {
        'id': 'test-user',
        'display_name': '稳稳',
        'gender': '男',
        'height': 170.0,
        'birth_date': '2000-01-01',
      },
      weight: 65.0,
      age: 26,
      hasBodyMetric: true,
      glucoseRecords: const [],
      meals: const [],
      mealItems: const [],
      exercises: const [],
      exerciseCatalog: HealthRepository.defaultExerciseCatalog,
      statuses: const [],
      reminders: const [],
    );
  }

  void completeSave() {
    if (!_saveCompleter.isCompleted) {
      _saveCompleter.complete();
    }
  }
}

String _readMealUpgradeMigration() {
  return File(
    'supabase/migrations/202604300003_upgrade_meal_calorie_catalog.sql',
  ).readAsStringSync();
}
