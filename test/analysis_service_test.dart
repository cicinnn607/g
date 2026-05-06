import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:glucose_assistant/core/app_messages.dart';
import 'package:glucose_assistant/pages/exercise_page.dart';
import 'package:glucose_assistant/provider/health_provider.dart';
import 'package:glucose_assistant/services/analysis_report.dart';
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

  test('按每100g营养素和克重计算营养总量', () {
    expect(AnalysisService.calculateNutrientByGrams(25.9, 150), 38.9);
    expect(AnalysisService.calculateNutrientByGrams(null, 150), 0);
    expect(AnalysisService.calculateNutrientByGrams(25.9, null), 0);
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
      'carbs_per_100g': 1.2,
      'protein_per_100g': 20,
      'fat_per_100g': 9,
      'gi_value': 20,
      'serving_options': {'1掌心': 100, '半掌心': 50},
      'is_ai_generated': true,
      'confidence': 0.85,
      'similarity_score': 0.7,
    });

    expect(item.name, '煎牛排');
    expect(item.aliases, contains('牛排'));
    expect(item.servingOptions['1掌心'], 100);
    expect(item.caloriesPer100g, 180);
    expect(item.carbsPer100g, 1.2);
    expect(item.proteinPer100g, 20);
    expect(item.fatPer100g, 9);
    expect(item.giValue, 20);
    expect(item.isAiGenerated, isTrue);
    expect(item.confidence, 0.85);
  });

  test('识别结果兼容旧响应并解析新增营养字段', () {
    final legacy = MealRecognitionItem.fromMap({
      'food_name_raw': '米饭',
      'calories_raw': 116,
      'confidence': 0.9,
    });
    final upgraded = MealRecognitionItem.fromMap({
      'food_name_raw': '宫保鸡丁',
      'food_name_confirmed': '宫保鸡丁',
      'calories_raw': 180,
      'carbs_per_100g': 10,
      'protein_per_100g': 12,
      'fat_per_100g': 8,
      'gi_value': 45,
      'serving_options': {'1小盘': 180},
      'source': 'zhipu',
      'is_ai_generated': true,
      'catalog_id': 'food_2',
      'confidence': 0.85,
    });

    expect(legacy.foodNameRaw, '米饭');
    expect(legacy.servingOptions, isEmpty);
    expect(upgraded.foodNameConfirmed, '宫保鸡丁');
    expect(upgraded.carbsPer100g, 10);
    expect(upgraded.proteinPer100g, 12);
    expect(upgraded.fatPer100g, 8);
    expect(upgraded.giValue, 45);
    expect(upgraded.servingOptions['1小盘'], 180);
    expect(upgraded.isAiGenerated, isTrue);
    expect(upgraded.catalogId, 'food_2');
  });

  test('分析报告模型兼容 null、数字字符串和缺失总结', () {
    final report = AnalysisReport.fromMap({
      'daily_stats': [
        {
          'record_date': '2026-05-02',
          'reading_count': '1',
          'avg_glucose': '10.0',
          'cv': null,
          'in_range_ratio': '1.0',
        },
      ],
      'weekly_summary_metrics': {
        'reading_count': '3',
        'valid_day_count': 2,
        'avg_glucose': '7.2',
        'cv': null,
      },
      'food_signals': [
        {
          'food_name': '米饭',
          'signal_level': 'yellow',
          'avg_excursion': '1.8',
          'meal_count': '2',
          'reason': '继续观察',
        },
      ],
      'data_quality': {
        'reading_count': '3',
        'valid_day_count': '2',
        'has_enough_glucose': false,
        'has_enough_food_signals': 'true',
        'messages': ['本周血糖记录偏少'],
      },
      'summary_text': '近期血糖整体比较平稳，请继续保持记录。',
      'summary_source': 'template',
      'summary_error': 'missing_llm_config',
    });

    expect(report.dailyStats.single.recordDate, '2026-05-02');
    expect(report.dailyStats.single.readingCount, 1);
    expect(report.dailyStats.single.avgGlucose, 10.0);
    expect(report.dailyStats.single.cv, isNull);
    expect(report.weeklySummaryMetrics.readingCount, 3);
    expect(report.weeklySummaryMetrics.cv, isNull);
    expect(report.foodSignals.single.avgExcursion, 1.8);
    expect(report.dataQuality.hasEnoughFoodSignals, isTrue);
    expect(report.summaryText, '近期血糖整体比较平稳，请继续保持记录。');
    expect(report.summarySource, 'template');
    expect(report.summaryError, 'missing_llm_config');
  });

  test('AI 分析卡片模型解析并过滤危险医疗词', () {
    final cards = AnalysisCards.fromMap({
      'analysis_cards_source': 'llm',
      'evidence_cache_key': 'demo-key',
      'analysis_cards': {
        'overall': {
          'title': '本周重点',
          'summary': '观察到早餐后状态更值得继续记录。',
          'confidence': 'medium',
          'confidence_reason': '记录覆盖多天',
        },
        'diet_cards': [
          {
            'title': '米饭和奶茶',
            'signal': 'red',
            'evidence': '餐后读数偏高，状态略感疲惫',
            'suggestion': '下次减少甜饮并饭后轻走。',
            'next_record': '餐后2小时补血糖',
          },
          {
            'title': '危险文案',
            'signal': 'bad',
            'evidence': '需要确诊',
            'suggestion': '建议就医',
            'next_record': '',
          },
        ],
        'exercise_card': {
          'title': '饭后轻动',
          'evidence': '本周运动记录偏少',
          'suggestion': '先从饭后轻走10分钟开始。',
        },
        'next_steps': [
          {'type': 'glucose', 'task': '餐后2小时补血糖'},
          {'type': 'unknown', 'task': '继续记录下一餐'},
        ],
        'safety_note': '仅供生活习惯参考，不替代医疗建议。',
      },
    });

    expect(cards.isLlm, isTrue);
    expect(cards.cacheKey, 'demo-key');
    expect(cards.overall.confidence, 'medium');
    expect(cards.dietCards.first.signal, 'red');
    expect(cards.dietCards.last.signal, 'observe');
    expect(cards.dietCards.last.evidence, '样本还少，建议继续配对记录。');
    expect(cards.nextSteps.last.type, 'diet');
  });

  test('meal_items 升级 migration 保留旧最终热量并重建公式', () {
    final migration = _readMealUpgradeMigration();
    final nutritionMigration = _readNutritionMigration();

    expect(migration, contains('set calories_user_override = calories_final'));
    expect(
      migration,
      contains('coalesce(calories_raw, 0) * coalesce(grams, 0) / 100'),
    );
    expect(nutritionMigration, contains('carbs_per_100g'));
    expect(
      nutritionMigration,
      contains('coalesce(carbs_raw, 0) * coalesce(grams, 0) / 100'),
    );
    expect(nutritionMigration, contains("notify pgrst, 'reload schema'"));
  });

  test('分析 migration 包含安全视图、时区 RPC 和最近餐次归因', () {
    final migration = _readAnalysisMigration();

    expect(migration, contains('with (security_invoker = true)'));
    expect(migration, contains('RETURNS TABLE'));
    expect(migration, contains('record_time at time zone'));
    expect(migration, contains("unit = 'mg/dL'"));
    expect(migration, contains('value / 18.0'));
    expect(
      migration,
      contains('stddev_samp(glucose_mmol) / avg(glucose_mmol)'),
    );
    expect(migration, contains('order by m.meal_time desc'));
    expect(migration, contains('get_food_impact_stats'));
    expect(migration, contains('notify pgrst'));
  });

  test('analysis-report Edge Function 包含认证、RPC 和 AI 卡片兜底', () {
    final functionCode = _readAnalysisFunction();

    expect(functionCode, contains("userClient.auth.getUser()"));
    expect(functionCode, contains("client.rpc(name, params)"));
    expect(functionCode, contains("SUPABASE_SERVICE_ROLE_KEY"));
    expect(functionCode, contains(".eq('user_id', userId)"));
    expect(functionCode, contains('AbortController'));
    expect(
      functionCode,
      contains('setTimeout(() => controller.abort(), 12000)'),
    );
    expect(functionCode, isNot(contains('50-80字')));
    expect(functionCode, contains('ANALYSIS_LLM_API_KEY'));
    expect(functionCode, contains('ZHIPU_API_KEY'));
    expect(
      functionCode,
      contains('open.bigmodel.cn/api/paas/v4/chat/completions'),
    );
    expect(functionCode, contains('glm-4.7-flash'));
    expect(functionCode, contains('summary_source'));
    expect(functionCode, contains('summary_error'));
    expect(functionCode, contains("body.mode === 'cards'"));
    expect(functionCode, contains('analysis_cards'));
    expect(functionCode, contains('buildAnalysisCards'));
    expect(functionCode, contains('hasUsableCardsData'));
    expect(functionCode, contains('extractJsonObject'));
    expect(functionCode, contains('```json'));
    expect(functionCode, contains('普通人群血糖健康管理助手'));
    expect(functionCode, contains('buildSummaryPrompt'));
    expect(functionCode, contains('sanitizeLlmSummary'));
    expect(functionCode, contains('近期血糖主要在'));
    expect(functionCode, contains('近期记录的数据较少'));
    expect(functionCode, contains('Asia/Shanghai'));
  });

  test('分析页使用 AI 卡片化局部加载并移除重复卡片', () {
    final pageCode = _readAnalysisPage();

    expect(pageCode, isNot(contains('远端分析暂时不可用')));
    expect(pageCode, isNot(contains('本地规则总结')));
    expect(pageCode, contains('provider.isLoadingAnalysisCards'));
    expect(pageCode, contains('_WeeklyFocusCard'));
    expect(pageCode, contains('_DietObservationCard'));
    expect(pageCode, contains('_NextStepsCard'));
    expect(pageCode, contains('Icons.insights'));
    expect(pageCode, isNot(contains('_TrendChartCard(data: data)')));
    expect(
      pageCode,
      isNot(contains('_FoodSignalsCard(signals: data.foodSignals)')),
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

  test('删除血糖记录会先从界面数据移除', () async {
    final repository = _DeletingRepository();
    final provider = HealthProvider(repository: repository);
    await provider.loadDashboardData();

    final deleteFuture = provider.deleteGlucoseRecord('bg_1');

    expect(provider.glucoseHistory.map((item) => item['id']), ['bg_2']);
    expect(repository.deleteGlucoseCalls, 1);

    repository.completeDelete();
    await deleteFuture;
  });

  test('删除血糖失败时会恢复原列表', () async {
    final repository = _DeletingRepository(failDelete: true);
    final provider = HealthProvider(repository: repository);
    await provider.loadDashboardData();

    await expectLater(
      provider.deleteGlucoseRecord('bg_1'),
      throwsA(isA<StateError>()),
    );

    expect(provider.glucoseHistory.map((item) => item['id']), ['bg_1', 'bg_2']);
  });

  test('删除饮食记录会同步移除餐食和食物明细', () async {
    final repository = _DeletingRepository();
    final provider = HealthProvider(repository: repository);
    await provider.loadDashboardData();

    final deleteFuture = provider.deleteMealRecord('meal_1');

    expect(provider.mealHistory.map((item) => item['id']), ['meal_2']);
    expect(provider.mealItems.map((item) => item['meal_id']), ['meal_2']);
    expect(repository.deleteMealCalls, 1);

    repository.completeDelete();
    await deleteFuture;
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

class _DeletingRepository extends HealthRepository {
  _DeletingRepository({this.failDelete = false});

  final bool failDelete;
  final _deleteCompleter = Completer<void>();
  int deleteGlucoseCalls = 0;
  int deleteMealCalls = 0;

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
      glucoseRecords: const [
        {'id': 'bg_1', 'value': 5.5},
        {'id': 'bg_2', 'value': 6.1},
      ],
      meals: const [
        {'id': 'meal_1', 'meal_time': '2026-05-04T08:00:00.000'},
        {'id': 'meal_2', 'meal_time': '2026-05-04T12:00:00.000'},
      ],
      mealItems: const [
        {'id': 'item_1', 'meal_id': 'meal_1'},
        {'id': 'item_2', 'meal_id': 'meal_2'},
      ],
      exercises: const [],
      exerciseCatalog: HealthRepository.defaultExerciseCatalog,
      statuses: const [],
      reminders: const [],
    );
  }

  @override
  Future<void> deleteGlucose(String id) async {
    deleteGlucoseCalls += 1;
    if (failDelete) throw StateError('delete failed');
    return _deleteCompleter.future;
  }

  @override
  Future<void> deleteMeal(String mealId) async {
    deleteMealCalls += 1;
    if (failDelete) throw StateError('delete failed');
    return _deleteCompleter.future;
  }

  void completeDelete() {
    if (!_deleteCompleter.isCompleted) {
      _deleteCompleter.complete();
    }
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

String _readNutritionMigration() {
  return File(
    'supabase/migrations/202605030001_extend_diet_nutrition_recognition.sql',
  ).readAsStringSync();
}

String _readAnalysisMigration() {
  return File(
    'supabase/migrations/202605030002_analysis_report.sql',
  ).readAsStringSync();
}

String _readAnalysisFunction() {
  return File('supabase/functions/analysis-report/index.ts').readAsStringSync();
}

String _readAnalysisPage() {
  return File('lib/pages/analysis_page.dart').readAsStringSync();
}
