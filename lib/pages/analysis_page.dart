import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_service.dart';
import '../widgets/soft_card.dart';

class DataAnalysisPage extends StatefulWidget {
  const DataAnalysisPage({super.key});

  @override
  State<DataAnalysisPage> createState() => _DataAnalysisPageState();
}

class _DataAnalysisPageState extends State<DataAnalysisPage> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.edit_note),
                label: Text('手动记录'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.show_chart),
                label: Text('CGM'),
              ),
            ],
            selected: {_mode},
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primaryDark
                    : AppColors.text,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.white,
              ),
            ),
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 0)
            _ManualAnalysis(provider: provider)
          else
            _CgmAnalysis(provider: provider),
        ],
      ),
    );
  }
}

class _ManualAnalysis extends StatelessWidget {
  final HealthProvider provider;

  const _ManualAnalysis({required this.provider});

  @override
  Widget build(BuildContext context) {
    final insight = provider.manualInsight;
    return Column(
      children: [
        SoftCard(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.insights, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insight.headline, style: AppTextStyles.section),
                    const SizedBox(height: 4),
                    Text(insight.observation, style: AppTextStyles.body),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          title: '可能有关',
          child: _TextBlock(text: insight.possibleCause),
        ),
        const SizedBox(height: 16),
        SoftCard(
          title: '下次试试',
          child: Column(
            children: [
              _TipLine(icon: Icons.restaurant, text: insight.nextStep),
              const SizedBox(height: 10),
              _TipLine(icon: Icons.directions_walk, text: insight.exerciseTip),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          title: '红绿灯食物',
          child: Column(
            children: provider.foodSignals
                .map((signal) => _FoodSignalRow(signal: signal))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _CgmAnalysis extends StatelessWidget {
  final HealthProvider provider;

  const _CgmAnalysis({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cgmRecords = provider.glucoseHistory
        .where((record) => '${record['source']}' == 'cgm')
        .toList();
    final values = cgmRecords
        .map((record) => double.tryParse('${record['value']}') ?? 0)
        .where((value) => value > 0)
        .toList();
    final hasData = values.isNotEmpty;
    final max = hasData ? values.reduce((a, b) => a > b ? a : b) : 0.0;
    final min = hasData ? values.reduce((a, b) => a < b ? a : b) : 0.0;
    final spread = max - min;

    return Column(
      children: [
        SoftCard(
          title: '连续血糖会看这些',
          child: _TextBlock(
            text: hasData
                ? '现在有 ${values.length} 条 CGM 记录，最高 ${max.toStringAsFixed(1)}，最低 ${min.toStringAsFixed(1)}，波动大约 ${spread.toStringAsFixed(1)}。'
                : '如果后面接入 CGM，就重点看一天里哪里忽高忽低、哪顿饭升得快、晚上有没有偏低。',
          ),
        ),
        const SizedBox(height: 16),
        const SoftCard(
          title: '看曲线时先抓三件事',
          child: Column(
            children: [
              _TipLine(icon: Icons.timeline, text: '餐后 0-2 小时升得快不快。'),
              SizedBox(height: 10),
              _TipLine(icon: Icons.speed, text: '一顿饭后多久能回到平稳区间。'),
              SizedBox(height: 10),
              _TipLine(icon: Icons.bedtime_outlined, text: '夜间有没有偏低或大幅波动。'),
            ],
          ),
        ),
      ],
    );
  }
}

class _FoodSignalRow extends StatelessWidget {
  final FoodSignal signal;

  const _FoodSignalRow({required this.signal});

  @override
  Widget build(BuildContext context) {
    final color = signal.isRed
        ? AppColors.red
        : signal.isYellow
        ? AppColors.yellow
        : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                Text(signal.reason, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.body)),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  final String text;

  const _TextBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.body);
  }
}
