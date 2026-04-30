import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_service.dart';
import '../widgets/soft_card.dart';

class GlucoseRecordPage extends StatefulWidget {
  const GlucoseRecordPage({super.key});

  @override
  State<GlucoseRecordPage> createState() => _GlucoseRecordPageState();
}

class _GlucoseRecordPageState extends State<GlucoseRecordPage> {
  final _periods = const [
    '空腹',
    '早餐后',
    '午餐前',
    '午餐后',
    '晚餐前',
    '晚餐后',
    '睡前',
    '凌晨',
    '随机',
  ];
  double _value = 5.5;
  String _period = '早餐后';
  String _unit = 'mmol/L';
  String _source = 'manual';
  DateTime _recordTime = DateTime.now();

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
    await provider.repository.saveGlucose(
      value: double.parse(_value.toStringAsFixed(1)),
      recordTime: _recordTime,
      timePeriod: _period,
      unit: _unit,
      source: _source,
    );
    await provider.loadDashboardData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('血糖已记录')));
  }

  Future<void> _delete(String id) async {
    final provider = context.read<HealthProvider>();
    await provider.repository.deleteGlucose(id);
    await provider.loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    final color = _glucoseColor(_value);
    return Scaffold(
      appBar: AppBar(title: const Text('血糖')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        _value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 44,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$_unit · ${AnalysisService.glucoseStatus(_value)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Slider(
                  value: _value,
                  min: 0.6,
                  max: 33.3,
                  divisions: 327,
                  activeColor: color,
                  onChanged: (value) => setState(() => _value = value),
                ),
                const Text(
                  '参考范围：3.9-10.0 mmol/L',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _periods
                      .map(
                        (period) => ChoiceChip(
                          label: Text(period),
                          selected: _period == period,
                          selectedColor: AppColors.primary.withValues(alpha: 0.14),
                          onSelected: (_) => setState(() => _period = period),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: _selectDecoration('单位'),
                        items: const [
                          DropdownMenuItem(
                            value: 'mmol/L',
                            child: Text('mmol/L'),
                          ),
                          DropdownMenuItem(
                            value: 'mg/dL',
                            child: Text('mg/dL'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _unit = value ?? _unit),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _source,
                        decoration: _selectDecoration('来源'),
                        items: const [
                          DropdownMenuItem(value: 'manual', child: Text('手动')),
                          DropdownMenuItem(value: 'cgm', child: Text('CGM')),
                        ],
                        onChanged: (value) =>
                            setState(() => _source = value ?? _source),
                      ),
                    ),
                  ],
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
                    child: const Text('保存记录'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            title: '历史记录',
            child: provider.glucoseHistory.isEmpty
                ? const SizedBox(
                    height: 90,
                    child: Center(
                      child: Text('暂无记录', style: AppTextStyles.caption),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.glucoseHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = provider.glucoseHistory[index];
                      final value = double.tryParse('${record['value']}') ?? 0;
                      return Dismissible(
                        key: Key('bg_${record['id']}'),
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
                            backgroundColor: _glucoseColor(
                              value,
                            ).withValues(alpha: 0.12),
                            child: Icon(
                              Icons.water_drop,
                              color: _glucoseColor(value),
                            ),
                          ),
                          title: Text(
                            '${value.toStringAsFixed(1)} ${record['unit']}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${record['time_period']} · ${record['source'] == 'cgm' ? 'CGM' : '手动'}\n${AppFormat.compactDateTime(record['record_time'])}',
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

  Color _glucoseColor(double value) {
    if (value < 3.9) return AppColors.yellow;
    if (value > 10.0) return AppColors.red;
    return AppColors.primary;
  }

  String _formatDateTime(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
