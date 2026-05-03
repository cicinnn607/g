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
  bool isAnalysisLoading = false;
  String? analysisError;

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
    } catch (error) {
      analysisError = '$error';
      debugPrint('分析报告加载失败: $error');
    } finally {
      isAnalysisLoading = false;
      if (notify) notifyListeners();
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
    isAnalysisLoading = false;
    analysisError = null;
    _latestGlucose = 0;
    _totalRecords = 0;
    notifyListeners();
  }
}
