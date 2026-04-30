import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const databaseName = 'GlucoseAssistant.db';
  static const databaseVersion = 4;

  static const localUserId = 'local_user';

  // Legacy tables kept for migration and backwards compatibility.
  static const tableGlucose = 'glucose_records';
  static const tableDiet = 'diet_records';
  static const tableExercise = 'exercise_records';
  static const tableProfile = 'user_profile';

  // Supabase-aligned local tables.
  static const tableUserProfiles = 'user_profiles';
  static const tableUserBodyMetrics = 'user_body_metrics';
  static const tableBloodGlucose = 'blood_glucose';
  static const tableMeals = 'meals';
  static const tableMealItems = 'meal_items';
  static const tableExerciseCatalog = 'exercise_catalog';
  static const tableExerciseLogs = 'exercise_logs';
  static const tableWellnessStatus = 'wellness_status';
  static const tableReminderSettings = 'reminder_settings';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, databaseName);
    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createLegacyTables(db);
    await _createCurrentTables(db);
    await _seedCurrentData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _createLegacyTables(db);
    await _createCurrentTables(db);
    await _migrateLegacyData(db);
    await _seedCurrentData(db);
  }

  Future<void> _createLegacyTables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tableGlucose (id INTEGER PRIMARY KEY AUTOINCREMENT, glucose_value REAL NOT NULL, record_time TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tableDiet (id INTEGER PRIMARY KEY AUTOINCREMENT, food_name TEXT NOT NULL, portion TEXT NOT NULL, calories INTEGER NOT NULL, record_time TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tableExercise (id INTEGER PRIMARY KEY AUTOINCREMENT, activity_type TEXT NOT NULL, duration INTEGER NOT NULL, calories INTEGER NOT NULL, record_time TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $tableProfile (id INTEGER PRIMARY KEY AUTOINCREMENT, age INTEGER, gender TEXT, height REAL, weight REAL)',
    );
  }

  Future<void> _createCurrentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableUserProfiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        gender TEXT,
        height REAL,
        birth_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableUserBodyMetrics (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        weight REAL NOT NULL,
        record_time TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableBloodGlucose (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        record_time TEXT NOT NULL,
        time_period TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'mmol/L',
        source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMeals (
        meal_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        meal_time TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMealItems (
        id TEXT PRIMARY KEY,
        meal_id TEXT NOT NULL,
        food_name_raw TEXT,
        food_name_confirmed TEXT NOT NULL,
        calories_raw REAL NOT NULL,
        portion_size REAL NOT NULL,
        calories_final REAL NOT NULL,
        image_url TEXT,
        FOREIGN KEY(meal_id) REFERENCES $tableMeals(meal_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableExerciseCatalog (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        met_value REAL NOT NULL,
        category TEXT,
        description TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableExerciseLogs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        exercise_time TEXT NOT NULL,
        motion_id TEXT NOT NULL,
        duration INTEGER NOT NULL,
        mets REAL NOT NULL,
        calories_burned REAL NOT NULL,
        FOREIGN KEY(motion_id) REFERENCES $tableExerciseCatalog(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableWellnessStatus (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        status_level TEXT NOT NULL,
        record_time TEXT NOT NULL,
        notes TEXT,
        related_meal_id TEXT,
        related_exercise_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableReminderSettings (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        time_of_day TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        label TEXT
      )
    ''');
  }

  Future<void> _seedCurrentData(Database db) async {
    await _seedProfile(db);
    await _seedExerciseCatalog(db);
    await _seedReminders(db);

    final glucoseCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $tableBloodGlucose'),
        ) ??
        0;
    if (glucoseCount > 0) return;

    final now = DateTime.now();
    final today = _date(now);
    final yesterday = _date(now.subtract(const Duration(days: 1)));

    await db.insert(tableBloodGlucose, {
      'id': 'seed_bg_1',
      'user_id': localUserId,
      'record_time': '$yesterday 14:00:00',
      'time_period': '午餐后',
      'value': 8.5,
      'unit': 'mmol/L',
      'source': 'manual',
    });
    await db.insert(tableBloodGlucose, {
      'id': 'seed_bg_2',
      'user_id': localUserId,
      'record_time': '$yesterday 21:00:00',
      'time_period': '晚餐后',
      'value': 5.8,
      'unit': 'mmol/L',
      'source': 'manual',
    });
    await db.insert(tableBloodGlucose, {
      'id': 'seed_bg_3',
      'user_id': localUserId,
      'record_time': '$today 07:30:00',
      'time_period': '空腹',
      'value': 4.9,
      'unit': 'mmol/L',
      'source': 'manual',
    });
    await db.insert(tableBloodGlucose, {
      'id': 'seed_bg_4',
      'user_id': localUserId,
      'record_time': '$today 10:00:00',
      'time_period': '早餐后',
      'value': 6.2,
      'unit': 'mmol/L',
      'source': 'manual',
    });

    await _insertSeedMeal(
      db,
      id: 'seed_meal_1',
      type: '午餐',
      time: '$yesterday 12:30:00',
      name: '炒鸡盖饭',
      calories: 850,
      portion: 1.5,
    );
    await _insertSeedMeal(
      db,
      id: 'seed_meal_2',
      type: '早餐',
      time: '$today 08:00:00',
      name: '全麦面包和牛奶',
      calories: 320,
      portion: 1.0,
    );
    await _insertSeedMeal(
      db,
      id: 'seed_meal_3',
      type: '午餐',
      time: '$today 12:00:00',
      name: '清蒸鱼和糙米饭',
      calories: 450,
      portion: 1.0,
    );

    await db.insert(tableExerciseLogs, {
      'id': 'seed_exercise_1',
      'user_id': localUserId,
      'exercise_time': '$yesterday 19:00:00',
      'motion_id': 'jog',
      'duration': 45,
      'mets': 7.0,
      'calories_burned': 368,
    });
    await db.insert(tableWellnessStatus, {
      'id': 'seed_status_1',
      'user_id': localUserId,
      'status_level': '状态平稳',
      'record_time': '$today 10:30:00',
      'notes': '早餐后没有明显犯困。',
      'related_meal_id': 'seed_meal_2',
      'related_exercise_id': null,
    });
  }

  Future<void> _seedProfile(Database db) async {
    final existing =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $tableUserProfiles'),
        ) ??
        0;
    if (existing == 0) {
      await db.insert(tableUserProfiles, {
        'id': localUserId,
        'display_name': '稳稳',
        'gender': '男',
        'height': 170.0,
        'birth_date': '${DateTime.now().year - 23}-01-01',
      });
    }

    final metrics =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $tableUserBodyMetrics'),
        ) ??
        0;
    if (metrics == 0) {
      await db.insert(tableUserBodyMetrics, {
        'id': 'seed_metric_1',
        'user_id': localUserId,
        'weight': 65.0,
        'record_time': '${_date(DateTime.now())} 08:00:00',
      });
    }
  }

  Future<void> _seedExerciseCatalog(Database db) async {
    final catalog = [
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
        'description': '稳定节奏的跑步',
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

    for (final item in catalog) {
      await db.insert(
        tableExerciseCatalog,
        item,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _seedReminders(Database db) async {
    final existing =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $tableReminderSettings'),
        ) ??
        0;
    if (existing > 0) return;

    final reminders = [
      {'id': 'reminder_morning', 'time_of_day': '08:30', 'label': '早餐后记录'},
      {'id': 'reminder_noon', 'time_of_day': '13:30', 'label': '午餐后记录'},
      {'id': 'reminder_evening', 'time_of_day': '20:30', 'label': '晚间回看'},
    ];
    for (final reminder in reminders) {
      await db.insert(tableReminderSettings, {
        ...reminder,
        'user_id': localUserId,
        'enabled': 1,
      });
    }
  }

  Future<void> _insertSeedMeal(
    Database db, {
    required String id,
    required String type,
    required String time,
    required String name,
    required num calories,
    required num portion,
  }) async {
    await db.insert(tableMeals, {
      'meal_id': id,
      'user_id': localUserId,
      'meal_type': type,
      'meal_time': time,
    });
    await db.insert(tableMealItems, {
      'id': '${id}_item',
      'meal_id': id,
      'food_name_raw': name,
      'food_name_confirmed': name,
      'calories_raw': calories / portion,
      'portion_size': portion,
      'calories_final': calories,
      'image_url': null,
    });
  }

  Future<void> _migrateLegacyData(Database db) async {
    if (await _tableHasRows(db, tableBloodGlucose)) return;

    final profileRows = await db.query(tableProfile, limit: 1);
    if (profileRows.isNotEmpty) {
      final profile = profileRows.first;
      final age = int.tryParse('${profile['age']}') ?? 23;
      await db.insert(tableUserProfiles, {
        'id': localUserId,
        'display_name': '稳稳',
        'gender': '${profile['gender'] ?? '男'}',
        'height': double.tryParse('${profile['height']}') ?? 170.0,
        'birth_date': '${DateTime.now().year - age}-01-01',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(tableUserBodyMetrics, {
        'id': 'legacy_metric_1',
        'user_id': localUserId,
        'weight': double.tryParse('${profile['weight']}') ?? 65.0,
        'record_time': '${_date(DateTime.now())} 08:00:00',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final oldGlucose = await db.query(tableGlucose);
    for (final record in oldGlucose) {
      await db.insert(tableBloodGlucose, {
        'id': 'legacy_bg_${record['id']}',
        'user_id': localUserId,
        'record_time': _normalizeTime('${record['record_time']}'),
        'time_period': '随机',
        'value': double.tryParse('${record['glucose_value']}') ?? 0.0,
        'unit': 'mmol/L',
        'source': 'manual',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final oldDiet = await db.query(tableDiet);
    for (final record in oldDiet) {
      final mealId = 'legacy_meal_${record['id']}';
      final calories = double.tryParse('${record['calories']}') ?? 0.0;
      await db.insert(tableMeals, {
        'meal_id': mealId,
        'user_id': localUserId,
        'meal_type': _guessMealType('${record['record_time']}'),
        'meal_time': _normalizeTime('${record['record_time']}'),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(tableMealItems, {
        'id': '${mealId}_item',
        'meal_id': mealId,
        'food_name_raw': '${record['food_name']}',
        'food_name_confirmed': '${record['food_name']}',
        'calories_raw': calories,
        'portion_size': 1.0,
        'calories_final': calories,
        'image_url': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final oldExercise = await db.query(tableExercise);
    for (final record in oldExercise) {
      final name = '${record['activity_type']}';
      final customId = 'legacy_${name.hashCode.abs()}';
      final duration = int.tryParse('${record['duration']}') ?? 0;
      final calories = double.tryParse('${record['calories']}') ?? 0.0;
      await db.insert(tableExerciseCatalog, {
        'id': customId,
        'name': name,
        'met_value': 5.0,
        'category': '自定义',
        'description': '由旧记录迁移',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(tableExerciseLogs, {
        'id': 'legacy_exercise_${record['id']}',
        'user_id': localUserId,
        'exercise_time': _normalizeTime('${record['record_time']}'),
        'motion_id': customId,
        'duration': duration,
        'mets': 5.0,
        'calories_burned': calories,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<bool> _tableHasRows(Database db, String table) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ??
        0;
    return count > 0;
  }

  static String _date(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  static String _normalizeTime(String value) {
    if (value.length >= 19) return value.substring(0, 19);
    if (value.length >= 16) return '${value.substring(0, 16)}:00';
    return value;
  }

  static String _guessMealType(String value) {
    final hour = value.length >= 13
        ? int.tryParse(value.substring(11, 13))
        : null;
    if (hour == null) return '加餐';
    if (hour < 10) return '早餐';
    if (hour < 15) return '午餐';
    if (hour < 20) return '晚餐';
    return '加餐';
  }

  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(table, row);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> row, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final db = await database;
    return db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final db = await database;
    return db.rawQuery(sql, arguments);
  }

  Future<int> delete(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<int> insertRecord(String table, Map<String, dynamic> row) async {
    return insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRecords(String table) async {
    if (table == tableProfile) {
      return query(table);
    }
    return query(table, orderBy: 'record_time DESC');
  }

  Future<int> deleteRecord(String table, int id) async {
    return delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateProfile(Map<String, dynamic> row) async {
    final db = await database;
    final count = await db.update(
      tableProfile,
      row,
      where: 'id = ?',
      whereArgs: [1],
    );
    if (count == 0) {
      row['id'] = 1;
      return db.insert(tableProfile, row);
    }
    return count;
  }
}
