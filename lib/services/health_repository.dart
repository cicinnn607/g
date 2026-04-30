import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'analysis_service.dart';
import 'supabase_config.dart';

class MealItemDraft {
  final String foodNameRaw;
  final String foodNameConfirmed;
  final double caloriesRaw;
  final double portionSize;
  final double caloriesFinal;
  final String? imageUrl;

  const MealItemDraft({
    required this.foodNameRaw,
    required this.foodNameConfirmed,
    required this.caloriesRaw,
    required this.portionSize,
    required this.caloriesFinal,
    this.imageUrl,
  });
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
      'id': 'walk_slow',
      'name': '慢走',
      'met_value': 2.8,
      'category': '低强度',
      'description': '饭后轻松走一走',
    },
    {
      'id': 'walk_fast',
      'name': '快走',
      'met_value': 4.3,
      'category': '中等强度',
      'description': '能说话但略喘',
    },
    {
      'id': 'jog',
      'name': '慢跑',
      'met_value': 7.0,
      'category': '有氧',
      'description': '稳定节奏跑步',
    },
    {
      'id': 'bike',
      'name': '骑行',
      'met_value': 6.0,
      'category': '有氧',
      'description': '中等速度骑行',
    },
    {
      'id': 'yoga',
      'name': '瑜伽',
      'met_value': 3.0,
      'category': '舒缓',
      'description': '轻柔拉伸和呼吸',
    },
    {
      'id': 'strength',
      'name': '力量训练',
      'met_value': 5.0,
      'category': '抗阻',
      'description': '自重或器械训练',
    },
    {
      'id': 'swim',
      'name': '游泳',
      'met_value': 7.0,
      'category': '有氧',
      'description': '连续游泳',
    },
    {
      'id': 'hiit',
      'name': 'HIIT',
      'met_value': 8.0,
      'category': '高强度',
      'description': '间歇训练',
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
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) {
      await _seedDefaultReminders(client, user.id);
      return;
    }

    final fallbackName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _nameFromEmail(user.email);
    await client.from('user_profiles').insert({
      'id': user.id,
      'display_name': fallbackName,
      'gender': '男',
      'height': 170.0,
      'birth_date': '${DateTime.now().year - 23}-01-01',
    });

    await client.from('user_body_metrics').insert({
      'id': _uuid.v4(),
      'user_id': user.id,
      'weight': 65.0,
      'record_time': _dbTime(DateTime.now()),
    });

    await _seedDefaultReminders(client, user.id);
  }

  Future<HealthSnapshot> loadSnapshot() async {
    final userId = currentUserId;
    if (_client == null || userId == null) return _defaultSnapshot();

    await ensureCurrentUserProfile();
    final profile = await getProfile();
    final weight = await getLatestWeight();
    final glucoseRecords = await getGlucoseRecords();
    final mealItems = await getMealItems();
    final meals = await getMeals(preloadedItems: mealItems);
    final exerciseCatalog = await getExerciseCatalog();
    final exercises = await getExerciseLogs(preloadedCatalog: exerciseCatalog);
    final statuses = await getStatuses();
    final reminders = await getReminders();

    return HealthSnapshot(
      profile: profile,
      weight: weight,
      age: ageFromBirthDate('${profile['birth_date'] ?? ''}'),
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
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return _defaultProfile(id: userId);
    return Map<String, dynamic>.from(row);
  }

  Future<double> getLatestWeight() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return 65.0;

    final rows = _rows(
      await client
          .from('user_body_metrics')
          .select()
          .eq('user_id', userId)
          .order('record_time', ascending: false)
          .limit(1),
    );
    if (rows.isEmpty) return 65.0;
    return double.tryParse('${rows.first['weight']}') ?? 65.0;
  }

  Future<List<Map<String, dynamic>>> getGlucoseRecords() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    return _rows(
      await client
          .from('blood_glucose')
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
      final mealItems = itemsByMeal['${meal['meal_id']}'] ?? const [];
      final calories = mealItems.fold<double>(
        0,
        (sum, item) =>
            sum + (double.tryParse('${item['calories_final']}') ?? 0),
      );
      return {
        ...meal,
        'calories_final': calories,
        'item_count': mealItems.length,
        'food_names': mealItems
            .map((item) => '${item['food_name_confirmed']}')
            .where((name) => name.trim().isNotEmpty)
            .join('、'),
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
      for (final meal in meals) '${meal['meal_id']}': meal,
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

  Future<void> saveProfile({
    required String displayName,
    required String gender,
    required double height,
    required String birthDate,
  }) async {
    final client = _requireClient();
    final userId = _requireUserId();
    await client.from('user_profiles').upsert({
      'id': userId,
      'display_name': displayName.trim().isEmpty
          ? _nameFromEmail(client.auth.currentUser?.email)
          : displayName.trim(),
      'gender': gender,
      'height': height,
      'birth_date': birthDate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    await client.from('blood_glucose').insert({
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
        .from('blood_glucose')
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

    await client.storage.from(mealImageBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(extension),
            upsert: false,
          ),
        );

    final response = await client.functions.invoke(
      'recognize-meal',
      body: {'storage_path': storagePath},
    );
    final data = response.data;
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
      'meal_id': mealId,
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
                    'portion_size': item.portionSize,
                    'calories_final': item.caloriesFinal,
                    'image_url': item.imageUrl,
                  },
                )
                .toList(),
          );
    } catch (_) {
      await client.from('meals').delete().eq('meal_id', mealId);
      rethrow;
    }
  }

  Future<void> deleteMeal(String mealId) async {
    final client = _requireClient();
    await client
        .from('meals')
        .delete()
        .eq('meal_id', mealId)
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
      'mets': met,
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
      throw StateError('还没有配置 Supabase URL 和 anon key');
    }
    return client;
  }

  String _requireUserId() {
    final userId = currentUserId;
    if (userId == null) throw StateError('请先登录');
    return userId;
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

  HealthSnapshot _defaultSnapshot() {
    return HealthSnapshot(
      profile: _defaultProfile(),
      weight: 65.0,
      age: 23,
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
