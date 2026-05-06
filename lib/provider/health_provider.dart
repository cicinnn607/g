import 'dart:async';

import 'package:flutter/material.dart';

import '../services/analysis_service.dart';
import '../services/analysis_report.dart';
import '../services/health_repository.dart';
import '../services/reminder_service.dart';

class HealthProvider with ChangeNotifier {
  HealthProvider({HealthRepository? repository})
    : repository = repository ?? HealthRepository();

  final HealthRepository repository;

  bool isLoading = false;
  int _totalRecords = 0;
  double _latestGlucose = 0.0;

  String displayName = '稳稳';
  String gender = '男';
  double height = 170.0;
  String birthDate = '${DateTime.now().year - 23}-01-01';
  int age = 23;
  double weight = 65.0;
  bool hasBodyMetric = false;

  List<Map<String, dynamic>> _glucoseHistory = [];
  List<Map<String, dynamic>> _mealHistory = [];
  List<Map<String, dynamic>> _mealItems = [];
  List<Map<String, dynamic>> _exerciseHistory = [];
  List<Map<String, dynamic>> _exerciseCatalog =
      HealthRepository.defaultExerciseCatalog;
  List<Map<String, dynamic>> _statusHistory = [];
  List<Map<String, dynamic>> _reminders = [];
  AnalysisReport _analysisReport = AnalysisReport.empty;
  AnalysisCards _analysisCards = AnalysisCards.empty;
  bool isAnalysisLoading = false;
  bool isAnalysisCardsLoading = false;
  String? analysisError;
  String? analysisCardsError;
  String? _analysisCardsCacheKey;

  int get totalRecords => _totalRecords;
  double get latestGlucose => _latestGlucose;
  List<Map<String, dynamic>> get glucoseHistory => _glucoseHistory;
  List<Map<String, dynamic>> get mealHistory => _mealHistory;
  List<Map<String, dynamic>> get mealItems => _mealItems;
  List<Map<String, dynamic>> get exerciseHistory => _exerciseHistory;
  List<Map<String, dynamic>> get exerciseCatalog => _exerciseCatalog;
  List<Map<String, dynamic>> get statusHistory => _statusHistory;
  List<Map<String, dynamic>> get reminders => _reminders;
  AnalysisReport get analysisReport => _analysisReport;
  AnalysisCards get analysisCards => _analysisCards;
  bool get isLoadingAnalysis => isAnalysisLoading;
  bool get isLoadingAnalysisCards => isAnalysisCardsLoading;
  bool get isSignedIn => repository.isSignedIn;

  // Backwards-compatible names used by older pages/tests.
  List<Map<String, dynamic>> get dietHistory => _mealHistory;

  List<FoodSignal> get foodSignals => AnalysisService.buildFoodSignals(
    _mealItems,
    _glucoseHistory,
    _statusHistory,
  );

  List<FoodSignal> get homeFoodSignals => AnalysisService.buildHomeFoodSignals(
    _mealItems,
    _glucoseHistory,
    _statusHistory,
  );

  String get exerciseSuggestion => AnalysisService.buildExerciseSuggestion(
    _glucoseHistory,
    _mealHistory,
    _exerciseHistory,
  );

  String get homeReminder => AnalysisService.buildHomeReminder(
    glucoseRecords: _glucoseHistory,
    meals: _mealHistory,
    exercises: _exerciseHistory,
    statuses: _statusHistory,
    totalRecords: _totalRecords,
  );

  ManualInsight get manualInsight => AnalysisService.buildManualInsight(
    glucoseRecords: _glucoseHistory,
    meals: _mealHistory,
    exercises: _exerciseHistory,
    statuses: _statusHistory,
  );

  String get latestStatusLabel {
    if (_statusHistory.isEmpty) return '还没记录';
    return '${_statusHistory.first['status_level']}';
  }

  Future<void> loadDashboardData() async {
    isLoading = true;
    notifyListeners();
    try {
      final snapshot = await repository.loadSnapshot();
      _applyProfile(
        snapshot.profile,
        ageValue: snapshot.age,
        weightValue: snapshot.weight,
        hasMetric: snapshot.hasBodyMetric,
      );

      _glucoseHistory = snapshot.glucoseRecords;
      _mealHistory = snapshot.meals;
      _mealItems = snapshot.mealItems;
      _exerciseHistory = snapshot.exercises;
      _exerciseCatalog = snapshot.exerciseCatalog;
      _statusHistory = snapshot.statuses;
      _reminders = snapshot.reminders;
      _latestGlucose = snapshot.latestGlucose;
      _totalRecords = snapshot.totalRecords;
      _invalidateAnalysisCardsCache();

      await ReminderService.instance.syncReminders(_reminders);
      await loadAnalysisReport(notify: false);
    } catch (error) {
      debugPrint('数据加载失败: $error');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAnalysisReport({bool notify = true}) async {
    if (!repository.isConfigured || !repository.isSignedIn) {
      _analysisReport = AnalysisReport.empty;
      analysisError = null;
      isAnalysisLoading = false;
      if (notify) notifyListeners();
      return;
    }

    isAnalysisLoading = true;
    analysisError = null;
    if (notify) notifyListeners();
    try {
      final now = DateTime.now();
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));
      final end = DateTime(now.year, now.month, now.day);
      _analysisReport = await repository.getAnalysisReport(
        startDate: start,
        endDate: end,
        timezone: 'Asia/Shanghai',
      );
      unawaited(loadAnalysisCards(startDate: start, endDate: end));
    } catch (error) {
      analysisError = '$error';
      debugPrint('分析报告加载失败: $error');
    } finally {
      isAnalysisLoading = false;
      if (notify) notifyListeners();
    }
  }

  Future<void> loadAnalysisCards({
    DateTime? startDate,
    DateTime? endDate,
    bool force = false,
  }) async {
    if (!repository.isConfigured || !repository.isSignedIn) {
      _analysisCards = AnalysisCards.empty;
      analysisCardsError = null;
      isAnalysisCardsLoading = false;
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final start =
        startDate ??
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
    final end = endDate ?? DateTime(now.year, now.month, now.day);
    final localCacheKey = _buildLocalAnalysisCardsCacheKey(start, end);
    if (!force &&
        _analysisCardsCacheKey == localCacheKey &&
        _analysisCards != AnalysisCards.empty) {
      return;
    }

    isAnalysisCardsLoading = true;
    analysisCardsError = null;
    notifyListeners();
    try {
      final cards = await repository.getAnalysisCards(
        startDate: start,
        endDate: end,
        timezone: 'Asia/Shanghai',
      );
      _analysisCards = cards;
      _analysisCardsCacheKey = localCacheKey;
    } catch (error) {
      analysisCardsError = '$error';
      debugPrint('AI 分析卡片加载失败: $error');
      _analysisCards = AnalysisCards.empty;
      _analysisCardsCacheKey = localCacheKey;
    } finally {
      isAnalysisCardsLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteGlucoseRecord(String id) async {
    final previous = _glucoseHistory;
    _glucoseHistory = _glucoseHistory
        .where((record) => '${record['id']}' != id)
        .toList();
    notifyListeners();

    try {
      await repository.deleteGlucose(id);
      await loadDashboardData();
    } catch (_) {
      _glucoseHistory = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteMealRecord(String id) async {
    final previousMeals = _mealHistory;
    final previousItems = _mealItems;
    _mealHistory = _mealHistory
        .where((meal) => '${meal['id'] ?? meal['meal_id']}' != id)
        .toList();
    _mealItems = _mealItems
        .where((item) => '${item['meal_id']}' != id)
        .toList();
    notifyListeners();

    try {
      await repository.deleteMeal(id);
      await loadDashboardData();
    } catch (_) {
      _mealHistory = previousMeals;
      _mealItems = previousItems;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteExerciseRecord(String id) async {
    final previous = _exerciseHistory;
    _exerciseHistory = _exerciseHistory
        .where((record) => '${record['id']}' != id)
        .toList();
    notifyListeners();

    try {
      await repository.deleteExercise(id);
      await loadDashboardData();
    } catch (_) {
      _exerciseHistory = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteStatusRecord(String id) async {
    final previous = _statusHistory;
    _statusHistory = _statusHistory
        .where((record) => '${record['id']}' != id)
        .toList();
    notifyListeners();

    try {
      await repository.deleteStatus(id);
      await loadDashboardData();
    } catch (_) {
      _statusHistory = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshProfileData() async {
    final profile = await repository.getProfile();
    final bodyMetric = await repository.getLatestBodyMetric();
    final nextWeight = bodyMetric == null
        ? weight
        : double.tryParse('${bodyMetric['weight']}') ?? weight;
    _applyProfile(
      profile,
      ageValue: HealthRepository.ageFromBirthDate(
        '${profile['birth_date'] ?? ''}',
      ),
      weightValue: nextWeight,
      hasMetric: bodyMetric != null,
    );
    notifyListeners();
  }

  void _applyProfile(
    Map<String, dynamic> profile, {
    required int ageValue,
    required double weightValue,
    required bool hasMetric,
  }) {
    displayName = '${profile['display_name'] ?? '稳稳'}';
    gender = '${profile['gender'] ?? '男'}';
    height = double.tryParse('${profile['height']}') ?? 170.0;
    birthDate =
        '${profile['birth_date'] ?? '${DateTime.now().year - 23}-01-01'}';
    age = ageValue;
    weight = weightValue;
    hasBodyMetric = hasMetric;
  }

  void resetForSignedOutUser() {
    displayName = '稳稳';
    gender = '男';
    height = 170.0;
    birthDate = '${DateTime.now().year - 23}-01-01';
    age = 23;
    weight = 65.0;
    hasBodyMetric = false;
    _glucoseHistory = [];
    _mealHistory = [];
    _mealItems = [];
    _exerciseHistory = [];
    _exerciseCatalog = HealthRepository.defaultExerciseCatalog;
    _statusHistory = [];
    _reminders = [];
    _analysisReport = AnalysisReport.empty;
    _analysisCards = AnalysisCards.empty;
    isAnalysisLoading = false;
    isAnalysisCardsLoading = false;
    analysisError = null;
    analysisCardsError = null;
    _analysisCardsCacheKey = null;
    _latestGlucose = 0;
    _totalRecords = 0;
    notifyListeners();
  }

  void _invalidateAnalysisCardsCache() {
    final nextKey = _buildLocalAnalysisCardsCacheKey(null, null);
    if (_analysisCardsCacheKey != null && _analysisCardsCacheKey != nextKey) {
      _analysisCards = AnalysisCards.empty;
      _analysisCardsCacheKey = null;
      analysisCardsError = null;
    }
  }

  String _buildLocalAnalysisCardsCacheKey(DateTime? start, DateTime? end) {
    final latestTimes = <String>[
      ..._glucoseHistory.map((item) => '${item['record_time'] ?? ''}'),
      ..._mealHistory.map((item) => '${item['meal_time'] ?? ''}'),
      ..._exerciseHistory.map((item) => '${item['exercise_time'] ?? ''}'),
      ..._statusHistory.map((item) => '${item['record_time'] ?? ''}'),
    ]..sort();
    final range = start == null || end == null
        ? 'current'
        : '${start.toIso8601String()}|${end.toIso8601String()}';
    return [
      range,
      _glucoseHistory.length,
      _mealHistory.length,
      _mealItems.length,
      _exerciseHistory.length,
      _statusHistory.length,
      latestTimes.isEmpty ? 'empty' : latestTimes.last,
    ].join('|');
  }
}
