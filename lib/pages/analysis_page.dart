import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_report.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<HealthProvider>();
      if (provider.isSignedIn) {
        provider.loadAnalysisReport();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: RefreshIndicator(
        onRefresh: provider.loadAnalysisReport,
        child: ListView(
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
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 16),
            _DelayedSkeleton(
              isLoading: provider.isAnalysisLoading,
              loadingChild: const _AnalysisSkeleton(),
              child: _mode == 0
                  ? _ManualAnalysis(provider: provider)
                  : _CgmAnalysis(provider: provider),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualAnalysis extends StatelessWidget {
  final HealthProvider provider;

  const _ManualAnalysis({required this.provider});

  @override
  Widget build(BuildContext context) {
    final report = provider.analysisReport;
    final useRemote = provider.analysisError == null && report.hasRemoteData;
    if (useRemote) return _RemoteAnalysis(report: report);
    return _FallbackAnalysis(provider: provider);
  }
}

class _RemoteAnalysis extends StatelessWidget {
  final AnalysisReport report;

  const _RemoteAnalysis({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.weeklySummaryMetrics;
    final cv = summary.cv;
    final inRange = summary.inRangeRatio;
    final avg = summary.avgGlucose;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricPill(
                label: '平均血糖',
                value: avg == null ? '--' : avg.toStringAsFixed(1),
                unit: 'mmol/L',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricPill(
                label: 'CV',
                value: cv == null ? '继续记录' : '${cv.toStringAsFixed(1)}%',
                color: _cvColor(cv),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricPill(
                label: '目标占比',
                value: inRange == null
                    ? '--'
                    : '${(inRange * 100).toStringAsFixed(0)}%',
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DailyTrendChart(dailyStats: report.dailyStats),
        const SizedBox(height: 16),
        SoftCard(
          title: '个人红绿灯食物',
          child: report.foodSignals.isEmpty
              ? const _EmptyBlock(text: '餐食和餐后血糖配对还不够，先继续记录。')
              : Column(
                  children: report.foodSignals
                      .take(5)
                      .map((signal) => _ImpactSignalRow(signal: signal))
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          title: '精力关联',
          child: report.energyCorrelation.isEmpty
              ? const _TextBlock(text: '同一天的血糖和状态记录还不够，暂时先看血糖趋势。')
              : Column(
                  children: report.energyCorrelation
                      .map((item) => _EnergyLine(item: item))
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          title: '本周总结',
          child: _TextBlock(
            text: report.summaryText.isEmpty
                ? report.dataQuality.messages.join('。')
                : report.summaryText,
          ),
        ),
        const SizedBox(height: 16),
        const _TextBlock(text: '以上内容仅供生活习惯参考，不替代医疗诊断或治疗建议。'),
      ],
    );
  }

  Color _cvColor(double? cv) {
    if (cv == null) return AppColors.yellow;
    return cv < AnalysisService.glucoseCvStableThreshold
        ? AppColors.green
        : AppColors.red;
  }
}

class _FallbackAnalysis extends StatelessWidget {
  final HealthProvider provider;

  const _FallbackAnalysis({required this.provider});

  @override
  Widget build(BuildContext context) {
    final insight = provider.manualInsight;
    final error = provider.analysisError;
    return Column(
      children: [
        if (error != null) ...[
          SoftCard(
            color: AppColors.yellowSoft,
            child: const _TextBlock(text: '远端分析暂时不可用，当前展示本地规则分析。'),
          ),
          const SizedBox(height: 16),
        ],
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
    final max = hasData ? values.reduce(math.max) : 0.0;
    final min = hasData ? values.reduce(math.min) : 0.0;
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

class _DailyTrendChart extends StatelessWidget {
  final List<DailyGlucoseStat> dailyStats;

  const _DailyTrendChart({required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    final values = dailyStats
        .map((item) => item.avgGlucose)
        .whereType<double>()
        .toList();
    final minValue = values.isEmpty ? 3.0 : values.reduce(math.min);
    final maxValue = values.isEmpty ? 10.0 : values.reduce(math.max);
    final minY = math.max(0, math.min(3.9, minValue) - 1.2).toDouble();
    final maxY = math.max(11.0, math.max(10.0, maxValue) + 1.2);

    return SoftCard(
      title: '近 7 天趋势',
      trailing: const Text('手动记录目标范围占比', style: AppTextStyles.caption),
      child: SizedBox(
        height: 230,
        child: dailyStats.isEmpty
            ? const _EmptyBlock(text: '还没有足够血糖记录，先记录几次空腹或餐后血糖。')
            : LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(1, dailyStats.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: AppColors.line, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: AnalysisService.glucoseLowTarget,
                        color: AppColors.yellow.withValues(alpha: 0.7),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                      HorizontalLine(
                        y: AnalysisService.glucoseHighTarget,
                        color: AppColors.red.withValues(alpha: 0.6),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, _) => Text(
                          value.toStringAsFixed(0),
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: dailyStats.length > 5
                            ? (dailyStats.length / 4).ceilToDouble()
                            : 1,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= dailyStats.length) {
                            return const SizedBox.shrink();
                          }
                          final date = dailyStats[index].recordDate;
                          final label = date.length >= 10
                              ? date.substring(5).replaceFirst('-', '/')
                              : date;
                          return Text(label, style: AppTextStyles.caption);
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dailyStats.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.avgGlucose ?? 0,
                        );
                      }).toList(),
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeColor: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ImpactSignalRow extends StatelessWidget {
  final FoodImpactSignal signal;

  const _ImpactSignalRow({required this.signal});

  @override
  Widget build(BuildContext context) {
    final color = signal.isRed
        ? AppColors.red
        : signal.isYellow
        ? AppColors.yellow
        : AppColors.green;
    final excursion = signal.avgExcursion == null
        ? '继续观察'
        : '+${signal.avgExcursion!.toStringAsFixed(1)} mmol/L';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.restaurant, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(signal.foodName, style: AppTextStyles.listTitle),
                const SizedBox(height: 3),
                Text(signal.reason, style: AppTextStyles.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(excursion, style: AppTextStyles.listMeta.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _EnergyLine extends StatelessWidget {
  final EnergyCorrelationItem item;

  const _EnergyLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final score = item.avgEnergy == null
        ? '样本不足'
        : '${item.avgEnergy!.toStringAsFixed(1)} / 5';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 20, color: AppColors.lavender),
          const SizedBox(width: 10),
          Expanded(child: Text(item.insight, style: AppTextStyles.body)),
          Text(score, style: AppTextStyles.listMeta),
        ],
      ),
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
                Text(signal.name, style: AppTextStyles.listTitle),
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

class _EmptyBlock extends StatelessWidget {
  final String text;

  const _EmptyBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ),
    );
  }
}

class _DelayedSkeleton extends StatefulWidget {
  final bool isLoading;
  final Widget loadingChild;
  final Widget child;

  const _DelayedSkeleton({
    required this.isLoading,
    required this.loadingChild,
    required this.child,
  });

  @override
  State<_DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<_DelayedSkeleton> {
  Timer? _timer;
  bool _showSkeleton = false;

  @override
  void initState() {
    super.initState();
    _syncLoading();
  }

  @override
  void didUpdateWidget(covariant _DelayedSkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading) {
      _syncLoading();
    }
  }

  void _syncLoading() {
    _timer?.cancel();
    if (!widget.isLoading) {
      if (_showSkeleton) setState(() => _showSkeleton = false);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && widget.isLoading) {
        setState(() => _showSkeleton = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showSkeleton) return widget.loadingChild;
    return widget.child;
  }
}

class _AnalysisSkeleton extends StatelessWidget {
  const _AnalysisSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _SkeletonCard(height: 74),
        SizedBox(height: 16),
        _SkeletonCard(height: 230),
        SizedBox(height: 16),
        _SkeletonCard(height: 150),
        SizedBox(height: 16),
        _SkeletonCard(height: 110),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;

  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 120, height: 14, decoration: _skeletonDecoration()),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: _skeletonDecoration(),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _skeletonDecoration() {
    return BoxDecoration(
      color: AppColors.line.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
    );
  }
}
