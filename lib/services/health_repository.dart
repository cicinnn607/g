import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_messages.dart';
import 'analysis_service.dart';
import 'supabase_config.dart';

class MealItemDraft {
  final String foodNameRaw;
  final String foodNameConfirmed;
  final double caloriesRaw;
  final double grams;
  final String servingUnit;
  final double? caloriesUserOverride;
  final String? imageUrl;

  const MealItemDraft({
    required this.foodNameRaw,
    required this.foodNameConfirmed,
    required this.caloriesRaw,
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
  final Map<String, double> servingOptions;
  final String? category;
  final String? source;
  final double similarityScore;

  const FoodCalorieCatalogItem({
    required this.id,
    required this.name,
    required this.aliases,
    required this.caloriesPer100g,
    required this.servingOptions,
    this.category,
    this.source,
    this.similarityScore = 0,
  });

  factory FoodCalorieCatalogItem.fromMap(Map<String, dynamic> row) {
    final rawServingOptions = row['serving_options'];
    final servingOptions = <String, double>{};
    if (rawServingOptions is Map) {
      rawServingOptions.forEach((key, value) {
        final grams = double.tryParse('$value');
        if (grams != null && grams > 0) {
          servingOptions['$key'] = grams;
        }
      });
    }

    final rawAliases = row['aliases'];
    final aliases = rawAliases is List
        ? rawAliases.map((alias) => '$alias').toList()
        : <String>[];

    return FoodCalorieCatalogItem(
      id: '${row['id'] ?? ''}',
      name: '${row['name'] ?? ''}',
      aliases: aliases,
      caloriesPer100g:
          double.tryParse('${row['calories_per_100g'] ?? 0}') ?? 0,
      servingOptions: servingOptions,
      category: row['category'] == null ? null : '${row['category']}',
      source: row['source'] == null ? null : '${row['source']}',
      similarityScore:
          double.tryParse('${row['similarity_score'] ?? 0}') ?? 0,
    );
  }
}

class MealRecognitionItem {
  final String foodNameRaw;
  final double caloriesRaw;
  final double confidence;

  const MealRecognitionItem({
    required this.foodNameRaw,
    required this.caloriesRaw,
    required this.confidence,
  });
}

class MealRecognitionResult {
  final String storagePath;
  final List<MealRecognitionItem> items;

  const MealRecognitionResult({
    required this.storagePath,
    required this.items,
  });
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

  SupabaseClient? get _client =>
      _injectedClient ?? SupabaseConfig.tryClient();

  String? get currentUserId => _client?.auth.currentUser?.id;

  bool get isConfigured => SupabaseConfig.isConfigured || _injectedClient != null;

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

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
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
    final catalogById = {
      for (final item in catalog) '${item['id']}': item,
    };

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

  Future<List<FoodCalorieCatalogItem>> searchFoodCalorieCatalog(
    String query, {
    int limit = 8,
  }) async {
    final client = _client;
    if (client == null || currentUserId == null || query.trim().isEmpty) {
      return const [];
    }

    try {
      final data = await client.rpc(
        'search_food_calorie_catalog',
        params: {
          'query_text': query.trim(),
          'result_limit': limit,
        },
      );
      return _rows(data)
          .map(FoodCalorieCatalogItem.fromMap)
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
    } catch (error) {
      if (isMissingSchemaError(error, table: 'food_calorie_catalog')) {
        return const [];
      }
      final message = '$error'.toLowerCase();
      if (message.contains('failed host lookup') ||
          message.contains('socketexception') ||
          message.contains('network') ||
          message.contains('connection')) {
        return const [];
      }
      return const [];
    }
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
      await client.storage.from(mealImageBucket).uploadBinary(
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
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => MealRecognitionItem(
                foodNameRaw: '${item['food_name_raw'] ?? '未识别食物'}',
                caloriesRaw:
                    double.tryParse('${item['calories_raw'] ?? 0}') ?? 0,
                confidence:
                    double.tryParse('${item['confidence'] ?? 0}') ?? 0,
              ),
            )
            .toList()
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
      await client.from('meal_items').insert(
            items
                .map(
                  (item) => {
                    'id': _uuid.v4(),
                    'meal_id': mealId,
                    'food_name_raw': item.foodNameRaw.trim().isEmpty
                        ? item.foodNameConfirmed.trim()
                        : item.foodNameRaw.trim(),
                    'food_name_confirmed':
                        item.foodNameConfirmed.trim().isEmpty
                            ? '未命名食物'
                            : item.foodNameConfirmed.trim(),
                    'calories_raw': item.caloriesRaw,
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

  static String formatMealServingSummary(List<Map<String, dynamic>> items) {
    return items.map(formatMealItemServingSummary).where((summary) {
      return summary.trim().isNotEmpty;
    }).join('、');
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
