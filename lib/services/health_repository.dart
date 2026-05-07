import 'dart:async';
import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_messages.dart';
import 'analysis_report.dart';
import 'analysis_service.dart';
import 'supabase_config.dart';

double? _optionalDouble(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return null;
  return double.tryParse('$value');
}

bool _parseBool(Object? value) {
  return value == true || value == 1 || '$value'.toLowerCase() == 'true';
}

Map<String, double> _parseServingOptions(Object? rawServingOptions) {
  final servingOptions = <String, double>{};
  if (rawServingOptions is Map) {
    rawServingOptions.forEach((key, value) {
      final grams = double.tryParse('$value');
      if (grams != null && grams > 0) {
        servingOptions['$key'] = grams;
      }
    });
  }
  return servingOptions;
}

class MealItemDraft {
  final String foodNameRaw;
  final String foodNameConfirmed;
  final double caloriesRaw;
  final double? carbsRaw;
  final double? proteinRaw;
  final double? fatRaw;
  final double? giValueSnapshot;
  final double grams;
  final String servingUnit;
  final double? caloriesUserOverride;
  final String? imageUrl;

  const MealItemDraft({
    required this.foodNameRaw,
    required this.foodNameConfirmed,
    required this.caloriesRaw,
    this.carbsRaw,
    this.proteinRaw,
    this.fatRaw,
    this.giValueSnapshot,
    required this.grams,
    required this.servingUnit,
    this.caloriesUserOverride,
    this.imageUrl,
  });
}

class FoodCalorieCatalogItem {
  final String id;
  final String name;
  final List<String> aliases;
  final double caloriesPer100g;
  final double? carbsPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? giValue;
  final Map<String, double> servingOptions;
  final String? category;
  final String? source;
  final bool isAiGenerated;
  final double? confidence;
  final double similarityScore;

  const FoodCalorieCatalogItem({
    required this.id,
    required this.name,
    required this.aliases,
    required this.caloriesPer100g,
    this.carbsPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.giValue,
    required this.servingOptions,
    this.category,
    this.source,
    this.isAiGenerated = false,
    this.confidence,
    this.similarityScore = 0,
  });

  factory FoodCalorieCatalogItem.fromMap(Map<String, dynamic> row) {
    final rawAliases = row['aliases'];
    final aliases = rawAliases is List
        ? rawAliases.map((alias) => '$alias').toList()
        : <String>[];

    return FoodCalorieCatalogItem(
      id: '${row['id'] ?? ''}',
      name: '${row['name'] ?? ''}',
      aliases: aliases,
      caloriesPer100g: double.tryParse('${row['calories_per_100g'] ?? 0}') ?? 0,
      carbsPer100g: _optionalDouble(row['carbs_per_100g']),
      proteinPer100g: _optionalDouble(row['protein_per_100g']),
      fatPer100g: _optionalDouble(row['fat_per_100g']),
      giValue: _optionalDouble(row['gi_value']),
      servingOptions: _parseServingOptions(row['serving_options']),
      category: row['category'] == null ? null : '${row['category']}',
      source: row['source'] == null ? null : '${row['source']}',
      isAiGenerated: _parseBool(row['is_ai_generated']),
      confidence: _optionalDouble(row['confidence']),
      similarityScore: double.tryParse('${row['similarity_score'] ?? 0}') ?? 0,
    );
  }

  FoodCalorieCatalogItem copyNutritionFrom(FoodCalorieCatalogItem source) {
    return FoodCalorieCatalogItem(
      id: id,
      name: name,
      aliases: aliases,
      caloriesPer100g: caloriesPer100g,
      carbsPer100g: source.carbsPer100g,
      proteinPer100g: source.proteinPer100g,
      fatPer100g: source.fatPer100g,
      giValue: source.giValue,
      servingOptions: source.servingOptions.isEmpty
          ? servingOptions
          : source.servingOptions,
      category: category,
      source: source.source ?? this.source,
      isAiGenerated: source.isAiGenerated || isAiGenerated,
      confidence: source.confidence ?? confidence,
      similarityScore: similarityScore,
    );
  }
}

class EstimatedFoodResult {
  final FoodCalorieCatalogItem item;

  const EstimatedFoodResult({required this.item});

  factory EstimatedFoodResult.fromMap(Map<String, dynamic> map) {
    final rawItem = map['item'];
    if (rawItem is! Map) {
      throw StateError('AI 食物估算返回了无法解析的数据');
    }
    return EstimatedFoodResult(
      item: FoodCalorieCatalogItem.fromMap(Map<String, dynamic>.from(rawItem)),
    );
  }
}

FoodCalorieCatalogItem _foodItemFromCustomRow(Map<String, dynamic> row) {
  return FoodCalorieCatalogItem.fromMap({
    'id': row['id'],
    'name': row['name'],
    'aliases': const [],
    'calories_per_100g': row['calories_per_100g'],
    'carbs_per_100g': row['carbs_per_100g'],
    'protein_per_100g': row['protein_per_100g'],
    'fat_per_100g': row['fat_per_100g'],
    'gi_value': row['gi_value'],
    'serving_options': row['serving_options'] ?? {'100克': 100},
    'category': row['category'] ?? '自定义',
    'source': row['source'] ?? 'custom',
    'is_ai_generated': row['is_ai_generated'],
    'confidence': row['confidence'],
    'similarity_score': row['similarity_score'] ?? 1,
  });
}

const List<Map<String, dynamic>> _localFoodCatalogRows = [
  {
    'id': 'local-rice',
    'name': '米饭',
    'aliases': ['白米饭', '蒸米饭', '大米饭'],
    'calories_per_100g': 116,
    'serving_options': {'1标准碗': 150, '半碗': 75, '1口': 15},
    'category': '主食',
    'source': 'local_seed',
  },
  {
    'id': 'local-egg',
    'name': '鸡蛋',
    'aliases': ['水煮蛋', '茶叶蛋', '煎鸡蛋', '煎蛋'],
    'calories_per_100g': 151,
    'serving_options': {'1个': 55, '半个': 28, '2个': 110},
    'category': '蛋白质',
    'source': 'local_seed',
  },
  {
    'id': 'local-fried-egg',
    'name': '煎鸡蛋',
    'aliases': ['煎蛋', '荷包蛋'],
    'calories_per_100g': 144,
    'serving_options': {'1个': 55, '半个': 28, '2个': 110},
    'category': '蛋白质',
    'source': 'local_seed',
  },
  {
    'id': 'local-milk',
    'name': '牛奶',
    'aliases': ['纯牛奶', '全脂牛奶'],
    'calories_per_100g': 65,
    'serving_options': {'1盒': 250, '半盒': 125, '1口': 20},
    'category': '饮品',
    'source': 'local_seed',
  },
  {
    'id': 'local-latte',
    'name': '拿铁',
    'aliases': ['咖啡拿铁', '牛奶咖啡'],
    'calories_per_100g': 60,
    'serving_options': {'1杯': 300, '中杯': 360, '1口': 20},
    'category': '饮品',
    'source': 'local_seed',
  },
  {
    'id': 'local-bread',
    'name': '全麦面包',
    'aliases': ['面包', '吐司', '全麦吐司'],
    'calories_per_100g': 246,
    'serving_options': {'1片': 35, '2片': 70, '半片': 18},
    'category': '主食',
    'source': 'local_seed',
  },
  {
    'id': 'local-beef',
    'name': '牛肉',
    'aliases': ['瘦牛肉', '煎牛排', '牛排'],
    'calories_per_100g': 125,
    'serving_options': {'1掌心': 100, '半掌心': 50, '1块': 25},
    'category': '蛋白质',
    'source': 'local_seed',
  },
  {
    'id': 'local-chicken-breast',
    'name': '鸡胸肉',
    'aliases': ['鸡胸', '鸡肉'],
    'calories_per_100g': 133,
    'serving_options': {'1掌心': 100, '半掌心': 50, '1块': 120},
    'category': '蛋白质',
    'source': 'local_seed',
  },
  {
    'id': 'local-apple',
    'name': '苹果',
    'aliases': ['红苹果', '青苹果'],
    'calories_per_100g': 53,
    'serving_options': {'1个': 180, '半个': 90, '1片': 30},
    'category': '水果',
    'source': 'local_seed',
  },
  {
    'id': 'local-banana',
    'name': '香蕉',
    'aliases': ['蕉'],
    'calories_per_100g': 93,
    'serving_options': {'1根': 120, '半根': 60, '1口': 20},
    'category': '水果',
    'source': 'local_seed',
  },
  {
    'id': 'local-tomato',
    'name': '番茄',
    'aliases': ['西红柿'],
    'calories_per_100g': 18,
    'serving_options': {'1个': 180, '半个': 90, '1片': 20},
    'category': '蔬菜',
    'source': 'local_seed',
  },
  {
    'id': 'local-cucumber',
    'name': '黄瓜',
    'aliases': ['青瓜', '凉拌黄瓜'],
    'calories_per_100g': 15,
    'serving_options': {'1根': 200, '半根': 100, '1片': 10},
    'category': '蔬菜',
    'source': 'local_seed',
  },
  {
    'id': 'local-tofu',
    'name': '豆腐',
    'aliases': ['嫩豆腐', '老豆腐'],
    'calories_per_100g': 84,
    'serving_options': {'半盒': 150, '1块': 100, '1口': 20},
    'category': '豆制品',
    'source': 'local_seed',
  },
  {
    'id': 'local-noodles',
    'name': '面条',
    'aliases': ['汤面', '拌面', '挂面', '拉面'],
    'calories_per_100g': 110,
    'serving_options': {'1碗': 250, '半碗': 125, '1口': 25},
    'category': '主食',
    'source': 'local_seed',
  },
  {
    'id': 'local-fried-rice',
    'name': '炒饭',
    'aliases': ['蛋炒饭'],
    'calories_per_100g': 188,
    'serving_options': {'1盘': 300, '半盘': 150, '1勺': 35},
    'category': '常见菜',
    'source': 'local_seed',
  },
  {
    'id': 'local-malatang',
    'name': '麻辣烫',
    'aliases': ['麻辣烫蔬菜'],
    'calories_per_100g': 120,
    'serving_options': {'1碗': 500, '半碗': 250, '1勺': 40},
    'category': '常见菜',
    'source': 'local_seed',
  },
  {
    'id': 'local-burger',
    'name': '汉堡',
    'aliases': ['牛肉汉堡', '鸡腿堡'],
    'calories_per_100g': 250,
    'serving_options': {'1个': 180, '半个': 90, '1口': 25},
    'category': '快餐',
    'source': 'local_seed',
  },
  {
    'id': 'local-salad',
    'name': '鸡胸肉沙拉',
    'aliases': ['沙拉', '轻食沙拉'],
    'calories_per_100g': 120,
    'serving_options': {'1盒': 300, '半盒': 150, '1叉': 25},
    'category': '轻食',
    'source': 'local_seed',
  },
];

class MealRecognitionItem {
  final String foodNameRaw;
  final String? foodNameConfirmed;
  final double caloriesRaw;
  final double? carbsPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? giValue;
  final Map<String, double> servingOptions;
  final String? source;
  final bool isAiGenerated;
  final String? catalogId;
  final double confidence;

  const MealRecognitionItem({
    required this.foodNameRaw,
    this.foodNameConfirmed,
    required this.caloriesRaw,
    this.carbsPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.giValue,
    this.servingOptions = const {},
    this.source,
    this.isAiGenerated = false,
    this.catalogId,
    required this.confidence,
  });

  factory MealRecognitionItem.fromMap(Map<dynamic, dynamic> item) {
    return MealRecognitionItem(
      foodNameRaw: '${item['food_name_raw'] ?? '未识别食物'}',
      foodNameConfirmed: item['food_name_confirmed'] == null
          ? null
          : '${item['food_name_confirmed']}',
      caloriesRaw: double.tryParse('${item['calories_raw'] ?? 0}') ?? 0,
      carbsPer100g: _optionalDouble(item['carbs_per_100g']),
      proteinPer100g: _optionalDouble(item['protein_per_100g']),
      fatPer100g: _optionalDouble(item['fat_per_100g']),
      giValue: _optionalDouble(item['gi_value']),
      servingOptions: _parseServingOptions(item['serving_options']),
      source: item['source'] == null ? null : '${item['source']}',
      isAiGenerated: _parseBool(item['is_ai_generated']),
      catalogId: item['catalog_id'] == null ? null : '${item['catalog_id']}',
      confidence: double.tryParse('${item['confidence'] ?? 0}') ?? 0,
    );
  }

  MealRecognitionItem copyFromEstimate(FoodCalorieCatalogItem item) {
    return MealRecognitionItem(
      foodNameRaw: foodNameRaw,
      foodNameConfirmed: item.name,
      caloriesRaw: item.caloriesPer100g,
      carbsPer100g: item.carbsPer100g,
      proteinPer100g: item.proteinPer100g,
      fatPer100g: item.fatPer100g,
      giValue: item.giValue,
      servingOptions: item.servingOptions,
      source: item.source,
      isAiGenerated: true,
      catalogId: item.id.isEmpty ? null : item.id,
      confidence: item.confidence ?? confidence,
    );
  }
}

class MealRecognitionResult {
  final String storagePath;
  final List<MealRecognitionItem> items;

  const MealRecognitionResult({required this.storagePath, required this.items});
}

class HealthSnapshot {
  final Map<String, dynamic> profile;
  final double weight;
  final int age;
  final bool hasBodyMetric;
  final List<Map<String, dynamic>> glucoseRecords;
  final List<Map<String, dynamic>> meals;
  final List<Map<String, dynamic>> mealItems;
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> exerciseCatalog;
  final List<Map<String, dynamic>> statuses;
  final List<Map<String, dynamic>> reminders;

  const HealthSnapshot({
    required this.profile,
    required this.weight,
    required this.age,
    required this.hasBodyMetric,
    required this.glucoseRecords,
    required this.meals,
    required this.mealItems,
    required this.exercises,
    required this.exerciseCatalog,
    required this.statuses,
    required this.reminders,
  });

  int get totalRecords =>
      glucoseRecords.length + meals.length + exercises.length + statuses.length;

  double get latestGlucose => glucoseRecords.isEmpty
      ? 0.0
      : double.tryParse('${glucoseRecords.first['value']}') ?? 0.0;
}

class HealthRepository {
  HealthRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  final Uuid _uuid = const Uuid();

  static const String mealImageBucket = 'meal-images';

  static const List<Map<String, dynamic>> defaultExerciseCatalog = [
    {
      'id': '10000000-0000-4000-8000-000000000001',
      'name': '缓慢步行 (<4km/h)',
      'met_value': 2.0,
      'category': '低强度',
      'description': '散步、逛街等非常轻松的走动',
    },
    {
      'id': '10000000-0000-4000-8000-000000000002',
      'name': '做家务 (轻度)',
      'met_value': 2.5,
      'category': '低强度',
      'description': '擦桌子、整理杂物、洗碗',
    },
    {
      'id': '10000000-0000-4000-8000-000000000003',
      'name': '做家务 (重度)',
      'met_value': 3.5,
      'category': '中等强度',
      'description': '拖地、搬动家具、擦窗户',
    },
    {
      'id': '10000000-0000-4000-8000-000000000004',
      'name': '园艺/种花',
      'met_value': 3.8,
      'category': '中等强度',
      'description': '修剪植物、除草',
    },
    {
      'id': '10000000-0000-4000-8000-000000000005',
      'name': '站立办公/工作',
      'met_value': 1.8,
      'category': '低强度',
      'description': '不需要大幅度移动的站立工作',
    },
    {
      'id': '10000000-0000-4000-8000-000000000006',
      'name': '快走 (6km/h)',
      'met_value': 4.5,
      'category': '中等强度',
      'description': '有一定节奏的快速步行',
    },
    {
      'id': '10000000-0000-4000-8000-000000000007',
      'name': '慢跑 (8km/h)',
      'met_value': 7.0,
      'category': '中等强度',
      'description': '初学者常见的跑步速度',
    },
    {
      'id': '10000000-0000-4000-8000-000000000008',
      'name': '中速跑 (10km/h)',
      'met_value': 9.8,
      'category': '高强度',
      'description': '标准的健身跑步速度',
    },
    {
      'id': '10000000-0000-4000-8000-000000000009',
      'name': '快速跑 (12km/h)',
      'met_value': 11.5,
      'category': '高强度',
      'description': '较高强度的长跑',
    },
    {
      'id': '10000000-0000-4000-8000-000000000010',
      'name': '极速冲刺 (16km/h)',
      'met_value': 14.5,
      'category': '高强度',
      'description': '短距离冲刺或间歇跑',
    },
    {
      'id': '10000000-0000-4000-8000-000000000011',
      'name': '上下楼梯',
      'met_value': 8.0,
      'category': '高强度',
      'description': '爬楼梯锻炼',
    },
    {
      'id': '10000000-0000-4000-8000-000000000012',
      'name': '休闲骑行 (<16km/h)',
      'met_value': 4.0,
      'category': '中等强度',
      'description': '慢速骑车去超市或兜风',
    },
    {
      'id': '10000000-0000-4000-8000-000000000013',
      'name': '健身房动感单车',
      'met_value': 8.5,
      'category': '高强度',
      'description': '高频率、有节奏的室内单车',
    },
    {
      'id': '10000000-0000-4000-8000-000000000014',
      'name': '竞技骑行 (>20km/h)',
      'met_value': 10.5,
      'category': '高强度',
      'description': '公路车快速骑行',
    },
    {
      'id': '10000000-0000-4000-8000-000000000015',
      'name': '休闲游泳 (蛙泳/慢速)',
      'met_value': 5.8,
      'category': '中等强度',
      'description': '不间断的轻松游泳',
    },
    {
      'id': '10000000-0000-4000-8000-000000000016',
      'name': '竞速游泳 (自由泳/快速)',
      'met_value': 9.5,
      'category': '高强度',
      'description': '高频率的往返游泳',
    },
    {
      'id': '10000000-0000-4000-8000-000000000017',
      'name': '羽毛球 (休闲)',
      'met_value': 4.5,
      'category': '中等强度',
      'description': '公园里的双打或练习',
    },
    {
      'id': '10000000-0000-4000-8000-000000000018',
      'name': '羽毛球 (竞技)',
      'met_value': 7.0,
      'category': '中等强度',
      'description': '有强度的比赛',
    },
    {
      'id': '10000000-0000-4000-8000-000000000019',
      'name': '乒乓球',
      'met_value': 4.0,
      'category': '中等强度',
      'description': '持续的对练',
    },
    {
      'id': '10000000-0000-4000-8000-000000000020',
      'name': '网球 (单打)',
      'met_value': 8.0,
      'category': '高强度',
      'description': '全场跑动的竞技',
    },
    {
      'id': '10000000-0000-4000-8000-000000000021',
      'name': '篮球 (投篮练习)',
      'met_value': 4.5,
      'category': '中等强度',
      'description': '半场定点投篮',
    },
    {
      'id': '10000000-0000-4000-8000-000000000022',
      'name': '篮球 (正式比赛)',
      'met_value': 9.0,
      'category': '高强度',
      'description': '全场高强度的对抗',
    },
    {
      'id': '10000000-0000-4000-8000-000000000023',
      'name': '足球 (正式比赛)',
      'met_value': 10.0,
      'category': '高强度',
      'description': '大面积跑动的竞技',
    },
    {
      'id': '10000000-0000-4000-8000-000000000024',
      'name': '基础瑜伽/普拉提',
      'met_value': 3.0,
      'category': '低强度',
      'description': '拉伸与呼吸训练',
    },
    {
      'id': '10000000-0000-4000-8000-000000000025',
      'name': '力量训练 (轻重量)',
      'met_value': 3.5,
      'category': '中等强度',
      'description': '哑铃操或小重量塑形',
    },
    {
      'id': '10000000-0000-4000-8000-000000000026',
      'name': '力量训练 (大重量)',
      'met_value': 6.0,
      'category': '中等强度',
      'description': '深蹲、硬拉等核心力量训练',
    },
    {
      'id': '10000000-0000-4000-8000-000000000027',
      'name': 'HIIT/波比跳',
      'met_value': 11.0,
      'category': '高强度',
      'description': '高强度间歇训练',
    },
    {
      'id': '10000000-0000-4000-8000-000000000028',
      'name': '跳绳 (慢速)',
      'met_value': 8.0,
      'category': '高强度',
      'description': '约 100 次/分钟',
    },
    {
      'id': '10000000-0000-4000-8000-000000000029',
      'name': '跳绳 (快速)',
      'met_value': 12.0,
      'category': '高强度',
      'description': '约 120-160 次/分钟',
    },
    {
      'id': '10000000-0000-4000-8000-000000000030',
      'name': '划船机 (中等强度)',
      'met_value': 7.0,
      'category': '中等强度',
      'description': '全身协调有氧训练',
    },
  ];

  SupabaseClient? get _client => _injectedClient ?? SupabaseConfig.tryClient();

  String? get currentUserId => _client?.auth.currentUser?.id;

  bool get isConfigured =>
      SupabaseConfig.isConfigured || _injectedClient != null;

  bool get isSignedIn => currentUserId != null;

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final client = _requireClient();
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
    if (response.user == null || response.session == null) return false;
    await ensureCurrentUserProfile(displayName: displayName);
    return true;
  }

  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await ensureCurrentUserProfile();
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
  }

  Future<void> ensureCurrentUserProfile({String? displayName}) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    final existing = await client
        .from('user_profile')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) {
      await _seedDefaultBodyMetricIfMissing(client, user.id);
      await _seedDefaultRemindersIfAvailable(client, user.id);
      return;
    }

    final fallbackName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _nameFromEmail(user.email);
    await client.from('user_profile').insert({
      'id': user.id,
      'display_name': fallbackName,
      'gender': '男',
      'height': 170.0,
      'birth_date': '${DateTime.now().year - 23}-01-01',
    });

    await _seedDefaultBodyMetricIfMissing(client, user.id);
    await _seedDefaultRemindersIfAvailable(client, user.id);
  }

  Future<HealthSnapshot> loadSnapshot() async {
    final userId = currentUserId;
    if (_client == null || userId == null) return _defaultSnapshot();

    await ensureCurrentUserProfile();
    final profile = await getProfile();
    final bodyMetric = await getLatestBodyMetric();
    final weight = bodyMetric == null
        ? 65.0
        : double.tryParse('${bodyMetric['weight']}') ?? 65.0;
    final glucoseRecords = await getGlucoseRecords();
    final mealItems = await getMealItems();
    final meals = await getMeals(preloadedItems: mealItems);
    final exerciseCatalog = await getExerciseCatalog();
    final exercises = await getExerciseLogs(preloadedCatalog: exerciseCatalog);
    final statuses = await getStatuses();
    final reminders = await getRemindersIfAvailable();

    return HealthSnapshot(
      profile: profile,
      weight: weight,
      age: ageFromBirthDate('${profile['birth_date'] ?? ''}'),
      hasBodyMetric: bodyMetric != null,
      glucoseRecords: glucoseRecords,
      meals: meals,
      mealItems: mealItems,
      exercises: exercises,
      exerciseCatalog: exerciseCatalog,
      statuses: statuses,
      reminders: reminders,
    );
  }

  Future<Map<String, dynamic>> getProfile() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return _defaultProfile();

    final row = await client
        .from('user_profile')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return _defaultProfile(id: userId);
    return Map<String, dynamic>.from(row);
  }

  Future<double> getLatestWeight() async {
    final row = await getLatestBodyMetric();
    if (row == null) return 65.0;
    return double.tryParse('${row['weight']}') ?? 65.0;
  }

  Future<Map<String, dynamic>?> getLatestBodyMetric() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return null;

    final rows = _rows(
      await client
          .from('user_body_metrics')
          .select()
          .eq('user_id', userId)
          .order('record_time', ascending: false)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getGlucoseRecords() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    return _rows(
      await client
          .from('blood_glucose_logs')
          .select()
          .eq('user_id', userId)
          .order('record_time', ascending: false),
    );
  }

  Future<List<Map<String, dynamic>>> getMeals({
    List<Map<String, dynamic>>? preloadedItems,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    final meals = _rows(
      await client
          .from('meals')
          .select()
          .eq('user_id', userId)
          .order('meal_time', ascending: false),
    );
    final items = preloadedItems ?? await getMealItems();
    final itemsByMeal = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final mealId = '${item['meal_id']}';
      itemsByMeal.putIfAbsent(mealId, () => []).add(item);
    }

    return meals.map((meal) {
      final mealId = '${meal['id'] ?? meal['meal_id']}';
      final mealItems = itemsByMeal[mealId] ?? const [];
      final calories = mealItems.fold<double>(
        0,
        (sum, item) =>
            sum + (double.tryParse('${item['calories_final']}') ?? 0),
      );
      return {
        ...meal,
        'id': mealId,
        'meal_id': mealId,
        'calories_final': calories,
        'item_count': mealItems.length,
        'food_names': mealItems
            .map((item) => '${item['food_name_confirmed']}')
            .where((name) => name.trim().isNotEmpty)
            .join('、'),
        'serving_summary': formatMealServingSummary(mealItems),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getMealItems() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    final meals = _rows(
      await client.from('meals').select().eq('user_id', userId),
    );
    if (meals.isEmpty) return const [];

    final mealMeta = {
      for (final meal in meals) '${meal['id'] ?? meal['meal_id']}': meal,
    };
    final mealIds = mealMeta.keys.toList();
    final items = _rows(
      await client.from('meal_items').select().inFilter('meal_id', mealIds),
    );
    items.sort((a, b) {
      final aTime = '${mealMeta['${a['meal_id']}']?['meal_time'] ?? ''}';
      final bTime = '${mealMeta['${b['meal_id']}']?['meal_time'] ?? ''}';
      return bTime.compareTo(aTime);
    });

    return items.map((item) {
      final meal = mealMeta['${item['meal_id']}'];
      return {
        ...item,
        'meal_type': meal?['meal_type'],
        'meal_time': meal?['meal_time'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getExerciseCatalog() async {
    final client = _client;
    if (client == null || currentUserId == null) return defaultExerciseCatalog;

    final rows = _rows(
      await client
          .from('exercise_catalog')
          .select()
          .order('category', ascending: true)
          .order('name', ascending: true),
    );
    return rows.isEmpty ? defaultExerciseCatalog : rows;
  }

  Future<List<Map<String, dynamic>>> getExerciseLogs({
    List<Map<String, dynamic>>? preloadedCatalog,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    final logs = _rows(
      await client
          .from('exercise_logs')
          .select()
          .eq('user_id', userId)
          .order('exercise_time', ascending: false),
    );
    final catalog = preloadedCatalog ?? await getExerciseCatalog();
    final catalogById = {for (final item in catalog) '${item['id']}': item};

    return logs.map((log) {
      final motion = catalogById['${log['motion_id']}'];
      return {
        ...log,
        'mets': log['mets_snapshot'],
        'motion_name': motion?['name'] ?? '运动',
        'category': motion?['category'],
        'description': motion?['description'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getStatuses() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    return _rows(
      await client
          .from('wellness_status')
          .select()
          .eq('user_id', userId)
          .order('record_time', ascending: false),
    );
  }

  Future<List<Map<String, dynamic>>> getReminders() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    return _rows(
      await client
          .from('reminder_settings')
          .select()
          .eq('user_id', userId)
          .order('time_of_day', ascending: true),
    );
  }

  Future<List<Map<String, dynamic>>> getRemindersIfAvailable() async {
    try {
      return await getReminders();
    } catch (error) {
      if (isMissingSchemaError(error, table: 'reminder_settings')) {
        return const [];
      }
      rethrow;
    }
  }

  Future<AnalysisReport> getAnalysisReport({
    required DateTime startDate,
    required DateTime endDate,
    String timezone = 'Asia/Shanghai',
  }) async {
    final client = _requireClient();
    _requireUserId();
    final accessToken = client.auth.currentSession?.accessToken;
    final response = await client.functions
        .invoke(
          'analysis-report',
          headers: accessToken == null
              ? null
              : {'Authorization': 'Bearer $accessToken'},
          body: {
            'start_date': _dateOnly(startDate),
            'end_date': _dateOnly(endDate),
            'timezone': timezone,
          },
        )
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException('analysis-report 请求超时'),
        );
    final data = response.data;
    if (_isFunctionNotFound(response)) {
      throw StateError('AI 食物热量功能还没有部署，请先手动填写热量');
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['error'] != null) {
        throw StateError('analysis-report: ${map['error']}');
      }
      return AnalysisReport.fromMap(map);
    }
    throw StateError('analysis-report 返回了无法解析的数据');
  }

  Future<AnalysisCards> getAnalysisCards({
    required DateTime startDate,
    required DateTime endDate,
    String timezone = 'Asia/Shanghai',
  }) async {
    final client = _requireClient();
    _requireUserId();
    final accessToken = client.auth.currentSession?.accessToken;
    final response = await client.functions
        .invoke(
          'analysis-report',
          headers: accessToken == null
              ? null
              : {'Authorization': 'Bearer $accessToken'},
          body: {
            'mode': 'cards',
            'start_date': _dateOnly(startDate),
            'end_date': _dateOnly(endDate),
            'timezone': timezone,
          },
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('analysis report 请求超时'),
        );
    final data = response.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['error'] != null) {
        throw StateError('analysis report: ${map['error']}');
      }
      return AnalysisCards.fromMap(map);
    }
    throw StateError('analysis report 返回了无法解析的数据');
  }

  Future<List<FoodCalorieCatalogItem>> searchFoodCalorieCatalog(
    String query, {
    int limit = 8,
  }) async {
    final client = _client;
    final userId = currentUserId;
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final results = <FoodCalorieCatalogItem>[
      ..._searchLocalFoodCatalog(normalized, limit: limit),
    ];

    if (client == null || userId == null) {
      return _dedupeFoodItems(results, limit);
    }

    try {
      final data = await client.rpc(
        'search_food_calorie_catalog',
        params: {'query_text': normalized, 'result_limit': limit},
      );
      results.addAll(
        _rows(data)
            .map(FoodCalorieCatalogItem.fromMap)
            .where((item) => item.name.trim().isNotEmpty),
      );
    } catch (error) {
      // Keep search usable even while optional catalog migrations are catching up.
    }

    try {
      final customRows = _rows(
        await client
            .from('custom_foods')
            .select()
            .eq('user_id', userId)
            .ilike('name', '%$normalized%')
            .order('created_at', ascending: false)
            .limit(limit),
      );
      results.addAll(
        customRows
            .map(_foodItemFromCustomRow)
            .where((item) => item.name.trim().isNotEmpty),
      );
    } catch (error) {
      // Custom foods are additive; search should still return base catalog rows.
    }

    return _dedupeFoodItems(results, limit);
  }

  Future<List<FoodCalorieCatalogItem>> getRecentFoods({int limit = 12}) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) {
      return _localFoodCatalogRows
          .take(max(1, min(limit, 20)))
          .map((row) => FoodCalorieCatalogItem.fromMap(row))
          .toList();
    }

    final cappedLimit = max(1, min(limit, 20));
    try {
      final meals = _rows(
        await client
            .from('meals')
            .select('id, meal_time')
            .eq('user_id', userId)
            .order('meal_time', ascending: false)
            .limit(80),
      );
      if (meals.isEmpty) return const [];

      final mealTimes = <String, String>{};
      for (final meal in meals) {
        mealTimes['${meal['id'] ?? meal['meal_id']}'] =
            '${meal['meal_time'] ?? ''}';
      }

      final items = _rows(
        await client
            .from('meal_items')
            .select('food_name_confirmed, calories_raw, created_at, meal_id')
            .inFilter('meal_id', mealTimes.keys.toList()),
      );
      final stats = <String, Map<String, dynamic>>{};

      for (final item in items) {
        final name = '${item['food_name_confirmed'] ?? ''}'.trim();
        final calories = double.tryParse('${item['calories_raw'] ?? ''}') ?? 0;
        if (name.isEmpty || calories <= 0) continue;

        final key = name.toLowerCase();
        final time =
            mealTimes['${item['meal_id']}'] ?? '${item['created_at'] ?? ''}';
        final existing = stats[key];
        if (existing == null) {
          stats[key] = {
            'id': '',
            'name': name,
            'calories_per_100g': calories,
            'count': 1,
            'latest': time,
            'category': '最近常吃',
            'source': 'recent',
          };
        } else {
          existing['count'] = (existing['count'] as int) + 1;
          if (time.compareTo('${existing['latest']}') > 0) {
            existing['latest'] = time;
            existing['calories_per_100g'] = calories;
          }
        }
      }

      final rows = stats.values.toList()
        ..sort((a, b) {
          final byCount = (b['count'] as int).compareTo(a['count'] as int);
          if (byCount != 0) return byCount;
          return '${b['latest']}'.compareTo('${a['latest']}');
        });

      return rows.take(cappedLimit).map(_foodItemFromCustomRow).toList();
    } catch (error) {
      if (isMissingSchemaError(error, table: 'meal_items') ||
          isMissingSchemaError(error, table: 'meals') ||
          _isNetworkishError(error)) {
        return const [];
      }
      rethrow;
    }
  }

  Future<FoodCalorieCatalogItem> createCustomFood({
    required String name,
    required double caloriesPer100g,
    double? carbsPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? giValue,
    Map<String, double> servingOptions = const {},
    String source = 'custom',
    bool isAiGenerated = false,
    double? confidence,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    final normalized = name.trim();
    if (normalized.isEmpty) throw StateError('请输入食物名称');
    if (caloriesPer100g <= 0) throw StateError('请输入有效的每100g热量');

    final row = Map<String, dynamic>.from(
      await client
          .from('custom_foods')
          .upsert({
            'user_id': userId,
            'name': normalized,
            'calories_per_100g': caloriesPer100g,
            'carbs_per_100g': carbsPer100g,
            'protein_per_100g': proteinPer100g,
            'fat_per_100g': fatPer100g,
            'gi_value': giValue,
            'serving_options': servingOptions,
            'source': source,
            'is_ai_generated': isAiGenerated,
            'confidence': confidence,
          }, onConflict: 'user_id,name')
          .select()
          .single(),
    );

    return _foodItemFromCustomRow(row);
  }

  Future<FoodCalorieCatalogItem> estimateFood(String foodName) async {
    final client = _requireClient();
    _requireUserId();
    final normalized = foodName.trim();
    if (normalized.isEmpty) throw StateError('请输入食物名称');

    final accessToken = client.auth.currentSession?.accessToken;
    final response = await client.functions
        .invoke(
          'estimate-food',
          headers: accessToken == null
              ? null
              : {'Authorization': 'Bearer $accessToken'},
          body: {'food_name': normalized},
        )
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException('AI 食物热量估算请求超时'),
        );
    final data = response.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['error'] != null) {
        throw StateError('AI 食物估算失败：${map['error']}');
      }
      return EstimatedFoodResult.fromMap(map).item;
    }
    throw StateError('AI 食物估算返回了无法解析的数据');
  }

  Future<void> saveProfile({
    required String displayName,
    required String gender,
    required double height,
    required String birthDate,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    await client.from('user_profile').upsert({
      'id': userId,
      'display_name': displayName.trim().isEmpty
          ? _nameFromEmail(client.auth.currentUser?.email)
          : displayName.trim(),
      'gender': gender,
      'height': height,
      'birth_date': birthDate,
    });
  }

  Future<void> addBodyMetric({
    required double weight,
    required DateTime recordTime,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    await client.from('user_body_metrics').insert({
      'id': _uuid.v4(),
      'user_id': userId,
      'weight': weight,
      'record_time': _dbTime(recordTime),
    });
  }

  Future<void> saveGlucose({
    required double value,
    required DateTime recordTime,
    required String timePeriod,
    required String unit,
    required String source,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    await client.from('blood_glucose_logs').insert({
      'id': _uuid.v4(),
      'user_id': userId,
      'record_time': _dbTime(recordTime),
      'time_period': timePeriod,
      'value': value,
      'unit': unit,
      'source': source,
    });
  }

  Future<void> deleteGlucose(String id) async {
    final client = _requireClient();
    await client
        .from('blood_glucose_logs')
        .delete()
        .eq('id', id)
        .eq('user_id', _requireUserId());
  }

  Future<MealRecognitionResult> recognizeMealImage(XFile file) async {
    final client = _requireClient();
    final userId = _requireUserId();
    final extension = _imageExtension(file.name);
    final storagePath =
        '$userId/draft_${_uuid.v4()}/${DateTime.now().millisecondsSinceEpoch}$extension';
    final bytes = await file.readAsBytes();

    try {
      await client.storage
          .from(mealImageBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(extension),
              upsert: false,
            ),
          );
    } catch (error) {
      throw StateError(friendlyMealRecognitionError(error));
    }

    dynamic response;
    try {
      response = await client.functions.invoke(
        'recognize-meal',
        body: {'storage_path': storagePath},
      );
    } catch (error) {
      throw StateError(friendlyMealRecognitionError(error));
    }
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw StateError(
        friendlyMealRecognitionError(Exception('${data['error']}')),
      );
    }
    final rawItems = data is Map ? data['items'] : null;
    final items = rawItems is List
        ? rawItems.whereType<Map>().map(MealRecognitionItem.fromMap).toList()
        : <MealRecognitionItem>[];

    return MealRecognitionResult(storagePath: storagePath, items: items);
  }

  Future<void> saveMeal({
    required String mealType,
    required DateTime mealTime,
    required List<MealItemDraft> items,
  }) async {
    if (items.isEmpty) return;
    final client = _requireClient();
    final userId = _requireUserId();
    final mealId = _uuid.v4();
    await client.from('meals').insert({
      'id': mealId,
      'user_id': userId,
      'meal_type': mealType,
      'meal_time': _dbTime(mealTime),
    });

    try {
      await client
          .from('meal_items')
          .insert(
            items
                .map(
                  (item) => {
                    'id': _uuid.v4(),
                    'meal_id': mealId,
                    'food_name_raw': item.foodNameRaw.trim().isEmpty
                        ? item.foodNameConfirmed.trim()
                        : item.foodNameRaw.trim(),
                    'food_name_confirmed': item.foodNameConfirmed.trim().isEmpty
                        ? '未命名食物'
                        : item.foodNameConfirmed.trim(),
                    'calories_raw': item.caloriesRaw,
                    'carbs_raw': item.carbsRaw,
                    'protein_raw': item.proteinRaw,
                    'fat_raw': item.fatRaw,
                    'gi_value_snapshot': item.giValueSnapshot,
                    'portion_size': 1.0,
                    'grams': item.grams,
                    'serving_unit': item.servingUnit.trim().isEmpty
                        ? 'g'
                        : item.servingUnit.trim(),
                    'calories_user_override': item.caloriesUserOverride,
                    'image_url': item.imageUrl,
                  },
                )
                .toList(),
          );
    } catch (_) {
      await client.from('meals').delete().eq('id', mealId);
      rethrow;
    }
  }

  Future<void> deleteMeal(String mealId) async {
    final client = _requireClient();
    await client
        .from('meals')
        .delete()
        .eq('id', mealId)
        .eq('user_id', _requireUserId());
  }

  Future<void> saveExercise({
    required String motionId,
    required int duration,
    required DateTime exerciseTime,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    final catalogRows = _rows(
      await client
          .from('exercise_catalog')
          .select()
          .eq('id', motionId)
          .limit(1),
    );
    final met = catalogRows.isEmpty
        ? 3.0
        : double.tryParse('${catalogRows.first['met_value']}') ?? 3.0;
    final weight = await getLatestWeight();
    final calories = AnalysisService.calculateExerciseCalories(
      met,
      weight,
      duration,
    );

    await client.from('exercise_logs').insert({
      'id': _uuid.v4(),
      'user_id': userId,
      'exercise_time': _dbTime(exerciseTime),
      'motion_id': motionId,
      'duration': duration,
      'mets_snapshot': met,
      'calories_burned': calories,
    });
  }

  Future<void> deleteExercise(String id) async {
    final client = _requireClient();
    await client
        .from('exercise_logs')
        .delete()
        .eq('id', id)
        .eq('user_id', _requireUserId());
  }

  Future<void> saveStatus({
    required String statusLevel,
    required DateTime recordTime,
    String? notes,
    String? relatedMealId,
    String? relatedExerciseId,
  }) async {
    final client = _requireClient();
    await client.from('wellness_status').insert({
      'id': _uuid.v4(),
      'user_id': _requireUserId(),
      'status_level': statusLevel,
      'record_time': _dbTime(recordTime),
      'notes': notes,
      'related_meal_id': relatedMealId,
      'related_exercise_id': relatedExerciseId,
    });
  }

  Future<void> deleteStatus(String id) async {
    final client = _requireClient();
    await client
        .from('wellness_status')
        .delete()
        .eq('id', id)
        .eq('user_id', _requireUserId());
  }

  Future<Map<String, dynamic>> addReminder({
    required String timeOfDay,
    required String label,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    final row = {
      'id': _uuid.v4(),
      'user_id': userId,
      'time_of_day': timeOfDay,
      'enabled': true,
      'label': label,
    };
    final inserted = await client
        .from('reminder_settings')
        .insert(row)
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<void> setReminderEnabled(String id, bool enabled) async {
    final client = _requireClient();
    await client
        .from('reminder_settings')
        .update({'enabled': enabled})
        .eq('id', id)
        .eq('user_id', _requireUserId());
  }

  Future<void> deleteReminder(String id) async {
    final client = _requireClient();
    await client
        .from('reminder_settings')
        .delete()
        .eq('id', id)
        .eq('user_id', _requireUserId());
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('还没有配置 Supabase anon key');
    }
    return client;
  }

  String _requireUserId() {
    final userId = currentUserId;
    if (userId == null) throw StateError('请先登录');
    return userId;
  }

  Future<void> _seedDefaultBodyMetricIfMissing(
    SupabaseClient client,
    String userId,
  ) async {
    final existing = _rows(
      await client
          .from('user_body_metrics')
          .select('id')
          .eq('user_id', userId)
          .limit(1),
    );
    if (existing.isNotEmpty) return;

    await client.from('user_body_metrics').insert({
      'id': _uuid.v4(),
      'user_id': userId,
      'weight': 65.0,
      'record_time': _dbTime(DateTime.now()),
    });
  }

  Future<void> _seedDefaultReminders(
    SupabaseClient client,
    String userId,
  ) async {
    final existing = _rows(
      await client
          .from('reminder_settings')
          .select('id')
          .eq('user_id', userId)
          .limit(1),
    );
    if (existing.isNotEmpty) return;
    await client.from('reminder_settings').insert([
      {
        'id': _uuid.v4(),
        'user_id': userId,
        'time_of_day': '08:30',
        'enabled': true,
        'label': '早餐后记录',
      },
      {
        'id': _uuid.v4(),
        'user_id': userId,
        'time_of_day': '13:30',
        'enabled': true,
        'label': '午餐后记录',
      },
      {
        'id': _uuid.v4(),
        'user_id': userId,
        'time_of_day': '20:30',
        'enabled': true,
        'label': '晚间回看',
      },
    ]);
  }

  Future<void> _seedDefaultRemindersIfAvailable(
    SupabaseClient client,
    String userId,
  ) async {
    try {
      await _seedDefaultReminders(client, userId);
    } catch (error) {
      if (isMissingSchemaError(error, table: 'reminder_settings')) {
        return;
      }
      rethrow;
    }
  }

  HealthSnapshot _defaultSnapshot() {
    return HealthSnapshot(
      profile: _defaultProfile(),
      weight: 65.0,
      age: 23,
      hasBodyMetric: false,
      glucoseRecords: const [],
      meals: const [],
      mealItems: const [],
      exercises: const [],
      exerciseCatalog: defaultExerciseCatalog,
      statuses: const [],
      reminders: const [],
    );
  }

  Map<String, dynamic> _defaultProfile({String id = 'anonymous'}) {
    return {
      'id': id,
      'display_name': '稳稳',
      'gender': '男',
      'height': 170.0,
      'birth_date': '${DateTime.now().year - 23}-01-01',
    };
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<FoodCalorieCatalogItem> _searchLocalFoodCatalog(
    String query, {
    required int limit,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final scored = <({FoodCalorieCatalogItem item, int score})>[];
    for (final row in _localFoodCatalogRows) {
      final item = FoodCalorieCatalogItem.fromMap(row);
      final names = [item.name, ...item.aliases]
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList();
      var score = 0;
      for (final name in names) {
        if (name == normalized) {
          score = max(score, 100);
        } else if (name.contains(normalized)) {
          score = max(score, 80);
        } else if (normalized.contains(name)) {
          score = max(score, 65);
        }
      }
      if (score > 0) scored.add((item: item, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.item.name.length.compareTo(b.item.name.length);
    });
    return scored
        .take(max(1, min(limit, 20)))
        .map((entry) => entry.item)
        .toList();
  }

  List<FoodCalorieCatalogItem> _dedupeFoodItems(
    List<FoodCalorieCatalogItem> items,
    int limit,
  ) {
    final seen = <String>{};
    final merged = <FoodCalorieCatalogItem>[];
    for (final item in items) {
      final key = item.name.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      merged.add(item);
    }
    return merged.take(max(1, min(limit, 20))).toList();
  }

  bool _isNetworkishError(Object error) {
    final message = '$error'.toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('network') ||
        message.contains('connection');
  }

  bool _isFunctionNotFound(FunctionResponse response) {
    final data = response.data;
    final text = '$data'.toLowerCase();
    return response.status == 404 ||
        text.contains('not_found') ||
        text.contains('requested function was not found');
  }

  static String formatMealServingSummary(List<Map<String, dynamic>> items) {
    return items
        .map(formatMealItemServingSummary)
        .where((summary) {
          return summary.trim().isNotEmpty;
        })
        .join('、');
  }

  static String formatMealItemServingSummary(Map<String, dynamic> item) {
    final name = '${item['food_name_confirmed'] ?? item['food_name_raw'] ?? ''}'
        .trim();
    final servingUnit = '${item['serving_unit'] ?? ''}'.trim();
    final grams = double.tryParse('${item['grams'] ?? ''}') ?? 0;
    final calories = double.tryParse('${item['calories_final'] ?? ''}') ?? 0;
    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (servingUnit.isNotEmpty && servingUnit != 'g') {
      parts.add(servingUnit);
    } else if (grams > 0) {
      parts.add('${_formatCompactNumber(grams)}g');
    }
    parts.add('${calories.toStringAsFixed(0)} kcal');
    return parts.join(' · ');
  }

  static String _formatCompactNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _dateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _nameFromEmail(String? email) {
    final name = email == null ? '' : email.split('@').first.trim();
    return name.isEmpty ? '稳稳' : name;
  }

  String _dbTime(DateTime value) => value.toUtc().toIso8601String();

  String _imageExtension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.heic')) return '.heic';
    return '.jpg';
  }

  String _contentType(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static String formatDateTime(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  static String compactDateTime(Object? value) {
    final parsed = DateTime.tryParse('$value');
    final local = parsed?.toLocal();
    if (local == null) return '$value';
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static int ageFromBirthDate(String birthDate) {
    final parsed = DateTime.tryParse(birthDate);
    if (parsed == null) return 23;
    final now = DateTime.now();
    var age = now.year - parsed.year;
    final hasBirthdayPassed =
        now.month > parsed.month ||
        (now.month == parsed.month && now.day >= parsed.day);
    if (!hasBirthdayPassed) age -= 1;
    return min(max(age, 0), 120);
  }
}
