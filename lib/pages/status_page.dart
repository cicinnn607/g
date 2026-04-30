import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../widgets/soft_card.dart';

class StatusRecordPage extends StatefulWidget {
  const StatusRecordPage({super.key});

  @override
  State<StatusRecordPage> createState() => _StatusRecordPageState();
}

class _StatusRecordPageState extends State<StatusRecordPage> {
  final _notesCtrl = TextEditingController();
  final _levels = const ['极度疲劳', '略感疲惫', '状态平稳', '感觉不错', '精力充沛'];
  String _level = '状态平稳';
  DateTime _recordTime = DateTime.now();
  String? _relatedMealId;
  String? _relatedExerciseId;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _recordTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordTime),
    );
    if (time == null) return;
    setState(() {
      _recordTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final provider = context.read<HealthProvider>();
    await provider.repository.saveStatus(
      statusLevel: _level,
      recordTime: _recordTime,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      relatedMealId: _relatedMealId,
      relatedExerciseId: _relatedExerciseId,
    );
    _notesCtrl.clear();
    setState(() {
      _level = '状态平稳';
      _recordTime = DateTime.now();
      _relatedMealId = null;
      _relatedExerciseId = null;
    });
    await provider.loadDashboardData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('状态已记录')));
  }

  Future<void> _delete(String id) async {
    final provider = context.read<HealthProvider>();
    await provider.repository.deleteStatus(id);
    await provider.loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('状态记录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            title: '现在感觉怎么样',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _levels
                      .map(
                        (level) => ChoiceChip(
                          label: Text(level),
                          selected: _level == level,
                          selectedColor: AppColors.primary.withValues(alpha: 0.14),
                          labelStyle: TextStyle(
                            color: _level == level
                                ? AppColors.primaryDark
                                : AppColors.text,
                            fontWeight: _level == level
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                          onSelected: (_) => setState(() => _level = level),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '备注',
                    hintText: '比如：下午困、饿得快、精神不错',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _relatedMealId,
                  decoration: _selectDecoration('关联最近一餐'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不关联'),
                    ),
                    ...provider.mealHistory
                        .take(6)
                        .map(
                          (meal) => DropdownMenuItem<String?>(
                            value: '${meal['meal_id']}',
                            child: Text(
                              '${meal['meal_type']} · ${meal['food_names'] ?? '这餐'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) => setState(() => _relatedMealId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _relatedExerciseId,
                  decoration: _selectDecoration('关联最近一次运动'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不关联'),
                    ),
                    ...provider.exerciseHistory
                        .take(6)
                        .map(
                          (exercise) => DropdownMenuItem<String?>(
                            value: '${exercise['id']}',
                            child: Text(
                              '${exercise['motion_name'] ?? '运动'} · ${exercise['duration']}分钟',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _relatedExerciseId = value),
                ),
                const SizedBox(height: 12),
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
                  label: Text('记录时间：${_formatDateTime(_recordTime)}'),
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
                    onPressed: _save,
                    child: const Text('保存状态'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            title: '最近状态',
            child: provider.statusHistory.isEmpty
                ? const SizedBox(
                    height: 90,
                    child: Center(
                      child: Text('还没有状态记录', style: AppTextStyles.caption),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.statusHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = provider.statusHistory[index];
                      return Dismissible(
                        key: Key('status_${record['id']}'),
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
                            backgroundColor: _statusColor(
                              '${record['status_level']}',
                            ).withValues(alpha: 0.12),
                            child: Icon(
                              _statusIcon('${record['status_level']}'),
                              color: _statusColor('${record['status_level']}'),
                            ),
                          ),
                          title: Text(
                            '${record['status_level']}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${AppFormat.compactDateTime(record['record_time'])}\n${record['notes'] ?? '没有备注'}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  InputDecoration _selectDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }

  Color _statusColor(String level) {
    if (level.contains('疲劳')) return AppColors.red;
    if (level.contains('疲惫')) return AppColors.yellow;
    if (level.contains('不错')) return AppColors.primary;
    if (level.contains('充沛')) return AppColors.green;
    return AppColors.lavender;
  }

  IconData _statusIcon(String level) {
    if (level.contains('疲劳')) return Icons.battery_0_bar;
    if (level.contains('疲惫')) return Icons.battery_2_bar;
    if (level.contains('不错')) return Icons.battery_5_bar;
    if (level.contains('充沛')) return Icons.battery_full;
    return Icons.battery_4_bar;
  }

  String _formatDateTime(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }
}
