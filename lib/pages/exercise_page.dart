import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_service.dart';
import '../widgets/soft_card.dart';

class ExerciseRecordPage extends StatefulWidget {
  const ExerciseRecordPage({super.key});

  @override
  State<ExerciseRecordPage> createState() => _ExerciseRecordPageState();
}

class _ExerciseRecordPageState extends State<ExerciseRecordPage> {
  String? _motionId;
  double _duration = 15;
  DateTime _exerciseTime = DateTime.now();

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _exerciseTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_exerciseTime),
    );
    if (time == null) return;
    setState(() {
      _exerciseTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save(HealthProvider provider) async {
    final motionId = _currentMotionId(provider);
    if (motionId == null) return;
    await provider.repository.saveExercise(
      motionId: motionId,
      duration: _duration.round(),
      exerciseTime: _exerciseTime,
    );
    await provider.loadDashboardData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('运动已记录')));
  }

  Future<void> _delete(String id) async {
    final provider = context.read<HealthProvider>();
    await provider.repository.deleteExercise(id);
    await provider.loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    final selectedId = _currentMotionId(provider);
    final selected = selectedId == null
        ? null
        : provider.exerciseCatalog.firstWhere(
            (item) => '${item['id']}' == selectedId,
            orElse: () => const {},
          );
    final met = selected == null
        ? 0.0
        : double.tryParse('${selected['met_value']}') ?? 0.0;
    final calories = AnalysisService.calculateExerciseCalories(
      met,
      provider.weight,
      _duration.round(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('运动')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            title: '这次动了多久',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: provider.exerciseCatalog
                      .map(
                        (item) => ChoiceChip(
                          label: Text('${item['name']}'),
                          selected: selectedId == '${item['id']}',
                          selectedColor: AppColors.primarySoft,
                          onSelected: (_) =>
                              setState(() => _motionId = '${item['id']}'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected == null
                            ? '等待运动目录'
                            : '${selected['category']} · ${selected['description']}',
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$calories kcal',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      Text(
                        '按 ${provider.weight.toStringAsFixed(1)} kg、MET ${met.toStringAsFixed(1)} 估算',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('时长', style: AppTextStyles.section),
                    ),
                    Text(
                      '${_duration.round()} 分钟',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _duration,
                  min: 5,
                  max: 180,
                  divisions: 35,
                  activeColor: AppColors.primary,
                  onChanged: (value) => setState(() => _duration = value),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _pickDateTime,
                  icon: const Icon(Icons.access_time),
                  label: Text('运动时间：${_formatDateTime(_exerciseTime)}'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: selectedId == null
                        ? null
                        : () => _save(provider),
                    child: const Text('保存运动'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            title: '运动记录',
            child: provider.exerciseHistory.isEmpty
                ? const SizedBox(
                    height: 90,
                    child: Center(
                      child: Text('暂无运动记录', style: AppTextStyles.caption),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.exerciseHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = provider.exerciseHistory[index];
                      return Dismissible(
                        key: Key('exercise_${record['id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: AppColors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete('${record['id']}'),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.12,
                            ),
                            child: const Icon(
                              Icons.directions_run,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            '${record['motion_name'] ?? '运动'} · ${record['duration']} 分钟',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            AppFormat.compactDateTime(record['exercise_time']),
                          ),
                          trailing: Text(
                            '-${(double.tryParse('${record['calories_burned']}') ?? 0).toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String? _currentMotionId(HealthProvider provider) {
    if (provider.exerciseCatalog.isEmpty) return null;
    final exists = provider.exerciseCatalog.any(
      (item) => '${item['id']}' == _motionId,
    );
    return exists ? _motionId : '${provider.exerciseCatalog.first['id']}';
  }

  String _formatDateTime(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
