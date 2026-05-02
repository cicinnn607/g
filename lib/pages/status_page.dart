import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../widgets/soft_card.dart';

class _StatusOption {
  final String label;
  final String emoji;

  const _StatusOption(this.label, this.emoji);
}

class StatusRecordPage extends StatefulWidget {
  const StatusRecordPage({super.key});

  @override
  State<StatusRecordPage> createState() => _StatusRecordPageState();
}

class _StatusRecordPageState extends State<StatusRecordPage> {
  final _notesCtrl = TextEditingController();
  final _levels = const [
    _StatusOption('极度疲劳', '😵'),
    _StatusOption('略感疲惫', '😮‍💨'),
    _StatusOption('状态平稳', '🙂'),
    _StatusOption('感觉不错', '😊'),
    _StatusOption('精力充沛', '⚡'),
  ];
  String _level = '状态平稳';
  DateTime _recordTime = DateTime.now();
  String? _relatedMealId;
  String? _relatedExerciseId;
  bool _showAssociations = false;

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
      _showAssociations = false;
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
                Column(
                  children: _levels
                      .map(
                        (option) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StatusChoiceTile(
                            option: option,
                            selected: _level == option.label,
                            onTap: () => setState(() => _level = option.label),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '具体感受',
                    hintText: '比如：饭后犯困、饿得快、注意力下降、精神不错',
                    helperText: '这里的内容会用于后续分析，帮你发现饮食、运动和状态之间的关系。',
                    helperMaxLines: 2,
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _AssociationSection(
                  expanded: _showAssociations,
                  mealHistory: provider.mealHistory,
                  exerciseHistory: provider.exerciseHistory,
                  relatedMealId: _relatedMealId,
                  relatedExerciseId: _relatedExerciseId,
                  selectDecoration: _selectDecoration,
                  onToggle: () => setState(
                    () => _showAssociations = !_showAssociations,
                  ),
                  onMealChanged: (value) =>
                      setState(() => _relatedMealId = value),
                  onExerciseChanged: (value) =>
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

class _StatusChoiceTile extends StatelessWidget {
  final _StatusOption option;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChoiceTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
            ),
          ),
          child: Row(
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.primaryDark : AppColors.text,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle_outlined,
                color: selected ? AppColors.primaryDark : AppColors.faint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssociationSection extends StatelessWidget {
  final bool expanded;
  final List<Map<String, dynamic>> mealHistory;
  final List<Map<String, dynamic>> exerciseHistory;
  final String? relatedMealId;
  final String? relatedExerciseId;
  final InputDecoration Function(String label) selectDecoration;
  final VoidCallback onToggle;
  final ValueChanged<String?> onMealChanged;
  final ValueChanged<String?> onExerciseChanged;

  const _AssociationSection({
    required this.expanded,
    required this.mealHistory,
    required this.exerciseHistory,
    required this.relatedMealId,
    required this.relatedExerciseId,
    required this.selectDecoration,
    required this.onToggle,
    required this.onMealChanged,
    required this.onExerciseChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link,
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '可选关联',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    Text(
                      expanded ? '收起' : '展开',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _AssociationDropdown(
                    value: relatedMealId,
                    label: '关联最近一餐',
                    emptyText: '暂无可关联餐食',
                    items: _mealItems(),
                    decoration: selectDecoration('关联最近一餐'),
                    onChanged: onMealChanged,
                  ),
                  const SizedBox(height: 12),
                  _AssociationDropdown(
                    value: relatedExerciseId,
                    label: '关联最近一次运动',
                    emptyText: '暂无可关联运动',
                    items: _exerciseItems(),
                    decoration: selectDecoration('关联最近一次运动'),
                    onChanged: onExerciseChanged,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<DropdownMenuItem<String?>> _mealItems() {
    if (mealHistory.isEmpty) {
      return const [
        DropdownMenuItem<String?>(
          value: null,
          child: _DropdownText('暂无可关联餐食'),
        ),
      ];
    }

    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: _DropdownText('不关联'),
      ),
      ...mealHistory.take(6).map(
        (meal) {
          final mealId = '${meal['id'] ?? meal['meal_id']}';
          return DropdownMenuItem<String?>(
            value: mealId,
            child: _DropdownText(
              '${meal['meal_type']} · ${meal['food_names'] ?? '这餐'}',
            ),
          );
        },
      ),
    ];
  }

  List<DropdownMenuItem<String?>> _exerciseItems() {
    if (exerciseHistory.isEmpty) {
      return const [
        DropdownMenuItem<String?>(
          value: null,
          child: _DropdownText('暂无可关联运动'),
        ),
      ];
    }

    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: _DropdownText('不关联'),
      ),
      ...exerciseHistory.take(6).map(
        (exercise) => DropdownMenuItem<String?>(
          value: '${exercise['id']}',
          child: _DropdownText(
            '${exercise['motion_name'] ?? '运动'} · ${exercise['duration']}分钟',
          ),
        ),
      ),
    ];
  }
}

class _AssociationDropdown extends StatelessWidget {
  final String? value;
  final String label;
  final String emptyText;
  final List<DropdownMenuItem<String?>> items;
  final InputDecoration decoration;
  final ValueChanged<String?> onChanged;

  const _AssociationDropdown({
    required this.value,
    required this.label,
    required this.emptyText,
    required this.items,
    required this.decoration,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: decoration,
      hint: _DropdownText(
        items.length == 1 && items.first.value == null ? emptyText : '不关联',
      ),
      items: items,
      selectedItemBuilder: (context) => items
          .map(
            (item) => Align(
              alignment: Alignment.centerLeft,
              child: _DropdownText(
                item.child is _DropdownText
                    ? (item.child as _DropdownText).text
                    : label,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _DropdownText extends StatelessWidget {
  final String text;

  const _DropdownText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
