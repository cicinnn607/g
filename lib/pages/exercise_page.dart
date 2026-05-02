import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messages.dart';
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
  bool _saving = false;
  bool _showAllExercises = false;

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
    if (_saving) return;
    final motionId = _currentMotionId(provider);
    if (motionId == null) return;
    setState(() => _saving = true);
    try {
      await provider.repository.saveExercise(
        motionId: motionId,
        duration: _duration.round(),
        exerciseTime: _exerciseTime,
      );
      await provider.loadDashboardData();
      if (!mounted) return;
      _showSnack('运动已记录');
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '保存运动'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final visibleCatalog = _visibleExerciseCatalog(provider, selectedId);

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
                  children: visibleCatalog
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
                if (provider.exerciseCatalog.length > 8) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: AppButtonStyles.quiet,
                      onPressed: () => setState(
                        () => _showAllExercises = !_showAllExercises,
                      ),
                      icon: Icon(
                        _showAllExercises
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                      label: Text(_showAllExercises ? '收起运动' : '显示全部运动'),
                    ),
                  ),
                ],
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
                if (!provider.hasBodyMetric) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.yellowSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.yellow.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.yellow,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '还没有体重记录，当前先按 65.0 kg 估算。到个人设置保存体重后会更准。',
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    onPressed: selectedId == null || _saving
                        ? null
                        : () => _save(provider),
                    child: Text(_saving ? '保存中' : '保存运动'),
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

  List<Map<String, dynamic>> _visibleExerciseCatalog(
    HealthProvider provider,
    String? selectedId,
  ) {
    final all = provider.exerciseCatalog;
    if (_showAllExercises || all.length <= 8) return all;

    final visible = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in all.take(8)) {
      visible.add(item);
      seen.add('${item['id']}');
    }
    if (selectedId != null && !seen.contains(selectedId)) {
      for (final item in all) {
        if ('${item['id']}' == selectedId) {
          visible.add(item);
          break;
        }
      }
    }
    return visible;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.primaryDark),
    );
  }

  String _formatDateTime(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
