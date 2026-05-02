import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_service.dart';
import '../widgets/soft_card.dart';
import 'profile_settings_page.dart';
import 'status_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 9) return '早安';
    if (hour < 12) return '上午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: provider.loadDashboardData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              _Header(provider: provider, greeting: _greeting()),
              const SizedBox(height: 16),
              _TodayOverview(provider: provider),
              const SizedBox(height: 16),
              _FoodSignals(signals: provider.homeFoodSignals),
              const SizedBox(height: 16),
              _GlucoseChart(records: provider.glucoseHistory),
              const SizedBox(height: 16),
              _RecentRecords(provider: provider),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final HealthProvider provider;
  final String greeting;

  const _Header({required this.provider, required this.greeting});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SoftCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatusRecordPage()),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting，${provider.displayName}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('今天状态稳吗？', style: AppTextStyles.title),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _MiniMetric(
                      label: '最新血糖',
                      value: provider.latestGlucose > 0
                          ? provider.latestGlucose.toStringAsFixed(1)
                          : '--',
                      unit: 'mmol/L',
                    ),
                    const SizedBox(width: 12),
                    _MiniMetric(
                      label: '状态',
                      value: provider.latestStatusLabel,
                      unit: '',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.edit_note,
                        size: 18,
                        color: AppColors.primaryDark,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '点这里记录今天状态',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.primaryDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
          ),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                provider.displayName.isEmpty
                    ? '稳'
                    : provider.displayName.characters.first,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Text(
              unit.isEmpty ? value : '$value $unit',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayOverview extends StatelessWidget {
  final HealthProvider provider;

  const _TodayOverview({required this.provider});

  @override
  Widget build(BuildContext context) {
    final latest = provider.latestGlucose;
    final progress = latest <= 0
        ? 0.18
        : (latest / 10).clamp(0.08, 1.0).toDouble();
    return SoftCard(
      child: Row(
        children: [
          RingMetric(
            progress: progress,
            value: latest > 0 ? latest.toStringAsFixed(1) : '--',
            label: '最新血糖',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricPill(
                        label: '记录',
                        value: '${provider.totalRecords}',
                        unit: '条',
                        color: AppColors.lavender,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricPill(
                        label: '状态',
                        value: provider.latestStatusLabel,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    provider.homeReminder,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodSignals extends StatelessWidget {
  final List<FoodSignal> signals;

  const _FoodSignals({required this.signals});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      title: '红绿灯食物',
      child: Column(
        children: signals
            .map(
              (signal) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _signalColor(signal).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _signalColor(signal),
                        shape: BoxShape.circle,
                      ),
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
                          const SizedBox(height: 3),
                          Text(signal.reason, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Color _signalColor(FoodSignal signal) {
    if (signal.isRed) return AppColors.red;
    if (signal.isYellow) return AppColors.yellow;
    return AppColors.green;
  }
}

class _GlucoseChart extends StatelessWidget {
  final List<Map<String, dynamic>> records;

  const _GlucoseChart({required this.records});

  @override
  Widget build(BuildContext context) {
    final data = records.reversed.toList();
    final values = data
        .map((item) => double.tryParse('${item['value']}') ?? 0.0)
        .where((value) => value > 0)
        .toList();
    final minValue = values.isEmpty ? 3.0 : values.reduce(math.min);
    final maxValue = values.isEmpty ? 10.0 : values.reduce(math.max);
    final minY = math.max(0.0, minValue - 1.2);
    final maxY = math.max(11.0, maxValue + 1.2);

    return SoftCard(
      title: '血糖波动',
      trailing: const Text('3.9-10.0 参考', style: AppTextStyles.caption),
      child: SizedBox(
        height: 240,
        child: data.isEmpty
            ? const Center(child: Text('还没有血糖记录', style: AppTextStyles.caption))
            : LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(1, data.length - 1).toDouble(),
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
                        y: 3.9,
                        color: AppColors.yellow.withValues(alpha: 0.7),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                      HorizontalLine(
                        y: 10.0,
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
                        reservedSize: 32,
                        interval: data.length > 5
                            ? (data.length / 4).ceilToDouble()
                            : 1,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= data.length) {
                            return const SizedBox.shrink();
                          }
                          final label = AppFormat.compactDateTime(
                            data[index]['record_time'],
                          ).replaceFirst(' ', '\n');
                          return Text(
                            label,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.asMap().entries.map((entry) {
                        final y =
                            double.tryParse('${entry.value['value']}') ?? 0;
                        return FlSpot(entry.key.toDouble(), y);
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

class _RecentRecords extends StatelessWidget {
  final HealthProvider provider;

  const _RecentRecords({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      title: '最近记录',
      child: Column(
        children: [
          _RecordLine(
            icon: Icons.restaurant,
            color: AppColors.green,
            title: provider.mealHistory.isEmpty
                ? '还没有饮食记录'
                : '${provider.mealHistory.first['food_names']}',
            subtitle: provider.mealHistory.isEmpty
                ? '记录一餐后就能开始观察'
                : '${provider.mealHistory.first['meal_type']} · ${provider.mealHistory.first['calories_final']} kcal',
          ),
          const Divider(height: 1),
          _RecordLine(
            icon: Icons.directions_run,
            color: AppColors.primary,
            title: provider.exerciseHistory.isEmpty
                ? '还没有运动记录'
                : '${provider.exerciseHistory.first['motion_name']}',
            subtitle: provider.exerciseHistory.isEmpty
                ? '饭后走几分钟也算'
                : '${provider.exerciseHistory.first['duration']} 分钟 · ${provider.exerciseHistory.first['calories_burned']} kcal',
          ),
          const Divider(height: 1),
          _RecordLine(
            icon: Icons.battery_5_bar,
            color: AppColors.lavender,
            title: provider.statusHistory.isEmpty
                ? '还没有状态记录'
                : '${provider.statusHistory.first['status_level']}',
            subtitle: provider.statusHistory.isEmpty
                ? '点首页问候卡片就能记录'
                : '${provider.statusHistory.first['record_time']}',
          ),
        ],
      ),
    );
  }
}

class _RecordLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _RecordLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
