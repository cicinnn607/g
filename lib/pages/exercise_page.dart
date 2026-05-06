import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _allExerciseGroup = '全部';
  static const _commonExerciseGroup = '常用';
  static const _minDuration = 5;
  static const _maxDuration = 180;
  static const _exerciseGroups = [
    _commonExerciseGroup,
    '走路跑步',
    '骑行游泳',
    '球类运动',
    '力量塑形',
    '日常活动',
    _allExerciseGroup,
  ];

  final TextEditingController _exerciseSearchController =
      TextEditingController();
  final TextEditingController _durationController = TextEditingController(
    text: '15',
  );

  String? _motionId;
  String _exerciseQuery = '';
  String _exerciseGroup = _commonExerciseGroup;
  DateTime _exerciseTime = DateTime.now();
  bool _saving = false;

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
    final duration = _durationMinutes;
    if (duration == null) {
      _showSnack('运动时长请输入 $_minDuration-$_maxDuration 分钟');
      return;
    }
    setState(() => _saving = true);
    try {
      await provider.repository.saveExercise(
        motionId: motionId,
        duration: duration,
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
    try {
      await provider.deleteExerciseRecord(id);
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '删除运动'));
    }
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
    final duration = _durationMinutes ?? 0;
    final calories = AnalysisService.calculateExerciseCalories(
      met,
      provider.weight,
      duration,
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
                TextField(
                  controller: _exerciseSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索运动',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _exerciseQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _exerciseSearchController.clear();
                              setState(() => _exerciseQuery = '');
                            },
                          ),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _exerciseQuery = value.trim());
                  },
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _exerciseGroups.map((group) {
                      final selectedGroup = _exerciseGroup == group;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(group),
                          labelStyle: AppTextStyles.chip.copyWith(
                            color: selectedGroup
                                ? AppColors.primaryDark
                                : AppColors.muted,
                          ),
                          selected: selectedGroup,
                          selectedColor: AppColors.primarySoft,
                          backgroundColor: AppColors.background,
                          side: const BorderSide(color: AppColors.line),
                          onSelected: (_) {
                            setState(() => _exerciseGroup = group);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                if (visibleCatalog.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Center(
                      child: Text('没有找到匹配的运动', style: AppTextStyles.caption),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: visibleCatalog
                        .map(
                          (item) => ChoiceChip(
                            label: Text('${item['name']}'),
                            labelStyle: AppTextStyles.chip.copyWith(
                              color: selectedId == '${item['id']}'
                                  ? AppColors.primaryDark
                                  : AppColors.text,
                            ),
                            selected: selectedId == '${item['id']}',
                            selectedColor: AppColors.primarySoft,
                            backgroundColor: AppColors.surface,
                            side: BorderSide(
                              color: selectedId == '${item['id']}'
                                  ? AppColors.primary
                                  : AppColors.line,
                            ),
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
                const Text('时长', style: AppTextStyles.section),
                const SizedBox(height: 8),
                TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '输入运动时长',
                    helperText: '$_minDuration-$_maxDuration 分钟',
                    suffixText: '分钟',
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
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
                    onPressed:
                        selectedId == null ||
                            _durationMinutes == null ||
                            _saving
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.listTitle,
                          ),
                          subtitle: Text(
                            AppFormat.compactDateTime(record['exercise_time']),
                            style: AppTextStyles.listSubtitle,
                          ),
                          trailing: Text(
                            '-${(double.tryParse('${record['calories_burned']}') ?? 0).toStringAsFixed(0)} kcal',
                            style: AppTextStyles.listMeta.copyWith(
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
    final query = _exerciseQuery.toLowerCase();
    final filtered = all.where((item) {
      final name = '${item['name']}';
      final description = '${item['description'] ?? ''}';
      final category = '${item['category'] ?? ''}';
      final matchesQuery =
          query.isEmpty ||
          name.toLowerCase().contains(query) ||
          description.toLowerCase().contains(query) ||
          category.toLowerCase().contains(query);
      final matchesGroup =
          _exerciseGroup == _allExerciseGroup ||
          _exerciseItemGroup(item) == _exerciseGroup ||
          (_exerciseGroup == _commonExerciseGroup &&
              _isCommonExerciseItem(item));
      return matchesQuery && matchesGroup;
    }).toList();

    final visible = [...filtered];
    final seen = <String>{};
    for (final item in visible) {
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

  int? get _durationMinutes {
    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null ||
        duration < _minDuration ||
        duration > _maxDuration) {
      return null;
    }
    return duration;
  }

  bool _isCommonExerciseItem(Map<String, dynamic> item) {
    final name = '${item['name']}';
    const commonKeywords = ['步行', '快走', '慢跑', '瑜伽', '普拉提', '骑行', '力量训练', '家务'];
    return commonKeywords.any(name.contains);
  }

  String _exerciseItemGroup(Map<String, dynamic> item) {
    final name = '${item['name']}';
    if (_containsAny(name, const ['步行', '走', '跑', '冲刺', '楼梯'])) {
      return '走路跑步';
    }
    if (_containsAny(name, const ['骑行', '单车', '游泳', '划船机'])) {
      return '骑行游泳';
    }
    if (_containsAny(name, const ['羽毛球', '乒乓球', '网球', '篮球', '足球'])) {
      return '球类运动';
    }
    if (_containsAny(name, const ['瑜伽', '普拉提', '力量', 'HIIT', '波比', '跳绳'])) {
      return '力量塑形';
    }
    return '日常活动';
  }

  bool _containsAny(String value, List<String> keywords) {
    return keywords.any(value.contains);
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

  @override
  void dispose() {
    _exerciseSearchController.dispose();
    _durationController.dispose();
    super.dispose();
  }
}
