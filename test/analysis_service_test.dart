import 'package:flutter_test/flutter_test.dart';
import 'package:glucose_assistant/services/analysis_service.dart';
import 'package:glucose_assistant/services/health_repository.dart';

void main() {
  test('按份量系数计算饮食热量', () {
    expect(AnalysisService.calculateMealCalories(430, 1.2), 516.0);
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

  test('出生日期能换算成年龄', () {
    final today = DateTime.now();
    final birthday = '${today.year - 24}-01-01';
    expect(HealthRepository.ageFromBirthDate(birthday), greaterThanOrEqualTo(23));
  });
}
