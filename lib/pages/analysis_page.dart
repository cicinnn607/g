import 'dart:math' as math;

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

  bool get _isCgmMode => _mode == 1;

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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('数据分析')),
      body: Consumer<HealthProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadAnalysisReport();
              await provider.loadAnalysisCards(force: true);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ModeSwitch(
                          mode: _mode,
                          onChanged: (value) => setState(() => _mode = value),
                        ),
                        const SizedBox(height: 16),
                        if (provider.isLoadingAnalysis)
                          const _AnalysisSkeleton()
                        else if (_shouldShowEmptyState(provider))
                          const _AnalysisEmptyState()
                        else
                          _AnalysisCardStack(
                            provider: provider,
                            isCgmMode: _isCgmMode,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _shouldShowEmptyState(HealthProvider provider) {
    if (provider.analysisReport.hasRemoteData) return false;
    return provider.glucoseHistory.isEmpty &&
        provider.mealItems.isEmpty &&
        provider.statusHistory.isEmpty;
  }
}

class _ModeSwitch extends StatelessWidget {
  final int mode;
  final ValueChanged<int> onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
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
      selected: {mode},
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryDark
              : AppColors.text,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
        ),
      ),
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _AnalysisCardStack extends StatelessWidget {
  final HealthProvider provider;
  final bool isCgmMode;

  const _AnalysisCardStack({required this.provider, required this.isCgmMode});

  @override
  Widget build(BuildContext context) {
    final data = isCgmMode
        ? _AnalysisDisplayData.fromCgm(provider)
        : _AnalysisDisplayData.fromManual(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeeklyFocusCard(provider: provider, data: data),
        const SizedBox(height: 16),
        _MetricsCard(data: data),
        const SizedBox(height: 16),
        _DietObservationCard(provider: provider, isCgmMode: isCgmMode),
        const SizedBox(height: 16),
        _ExerciseAdviceCard(provider: provider),
        const SizedBox(height: 16),
        _NextStepsCard(provider: provider),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  final _AnalysisDisplayData data;

  const _MetricsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rangeLabel = data.isCgmMode ? 'TIR' : '目标范围内记录占比';
    return SoftCard(
      title: '核心指标',
      child: Row(
        children: [
          Expanded(
            child: _MetricCell(
              label: '平均血糖',
              value: data.avgGlucose == null
                  ? '--'
                  : data.avgGlucose!.toStringAsFixed(1),
              unit: 'mmol/L',
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCell(
              label: '变异系数',
              value: data.cv == null ? '--' : data.cv!.toStringAsFixed(1),
              unit: data.cv == null ? '数据不足' : '%',
              color: data.cv == null ? AppColors.yellow : _cvColor(data.cv),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCell(
              label: rangeLabel,
              value: data.inRangeRatio == null
                  ? '--'
                  : (data.inRangeRatio! * 100).toStringAsFixed(0),
              unit: data.inRangeRatio == null ? '' : '%',
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }

  Color _cvColor(double? cv) {
    if (cv == null) return AppColors.yellow;
    return cv < AnalysisService.glucoseCvStableThreshold
        ? AppColors.green
        : AppColors.red;
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MetricCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 34,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
            ),
            const SizedBox(height: 8),
            RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                text: value,
                style: AppTextStyles.title.copyWith(
                  fontSize: 22,
                  color: AppColors.text,
                ),
                children: [
                  if (unit.isNotEmpty)
                    TextSpan(text: ' $unit', style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyFocusCard extends StatelessWidget {
  final HealthProvider provider;
  final _AnalysisDisplayData data;

  const _WeeklyFocusCard({required this.provider, required this.data});

  @override
  Widget build(BuildContext context) {
    final cards = provider.analysisCards;
    final isLlm = cards.isLlm && provider.analysisCardsError == null;
    final fallbackSummary = data.summaryText.trim().isNotEmpty
        ? data.summaryText.trim()
        : '样本还少，建议继续记录餐食、血糖和状态来观察趋势。';
    final title = isLlm ? cards.overall.title : '本周重点';
    final summary = isLlm ? cards.overall.summary : fallbackSummary;
    final confidence = isLlm
        ? _confidenceLabel(cards.overall.confidence)
        : _confidenceLabel(_fallbackConfidence(provider));

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLlm ? Icons.auto_awesome : Icons.insights,
                  color: isLlm ? AppColors.lavender : AppColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTextStyles.section)),
              _StatusChip(
                text: isLlm ? 'AI 分析' : '基础分析',
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ExpandableText(summary, style: AppTextStyles.body),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(text: confidence, color: AppColors.lavender),
              _StatusChip(
                text: '血糖 ${provider.glucoseHistory.length} 条',
                color: AppColors.primary,
              ),
              _StatusChip(
                text: '饮食 ${provider.mealHistory.length} 餐',
                color: AppColors.green,
              ),
              _StatusChip(
                text: '状态 ${provider.statusHistory.length} 条',
                color: AppColors.yellow,
              ),
            ],
          ),
          if (provider.isLoadingAnalysisCards) ...[
            const SizedBox(height: 12),
            const _InlineLoading(text: '正在生成 AI 分析卡片'),
          ],
          if (provider.analysisCardsError != null) ...[
            const SizedBox(height: 12),
            const Text(
              '当前为基础分析，下拉刷新可重新生成 AI 卡片。',
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }

  String _fallbackConfidence(HealthProvider provider) {
    if (provider.glucoseHistory.length >= 8 &&
        provider.mealHistory.length >= 4 &&
        provider.statusHistory.length >= 3) {
      return 'medium';
    }
    return 'low';
  }

  String _confidenceLabel(String confidence) {
    switch (confidence) {
      case 'high':
        return '可信度较高';
      case 'medium':
        return '观察中';
      default:
        return '样本少';
    }
  }
}

class _DietObservationCard extends StatelessWidget {
  final HealthProvider provider;
  final bool isCgmMode;

  const _DietObservationCard({required this.provider, required this.isCgmMode});

  @override
  Widget build(BuildContext context) {
    final cards = provider.analysisCards.isLlm
        ? provider.analysisCards.dietCards
        : _fallbackDietCards(provider, isCgmMode);
    return SoftCard(
      title: '饮食观察',
      child: Column(
        children: List.generate(cards.length, (index) {
          final card = cards[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == cards.length - 1 ? 0 : 10,
            ),
            child: _DietObservationTile(card: card),
          );
        }),
      ),
    );
  }

  List<AnalysisDietCard> _fallbackDietCards(
    HealthProvider provider,
    bool isCgmMode,
  ) {
    if (isCgmMode) {
      final count = provider.glucoseHistory
          .where((record) => '${record['source']}' == 'cgm')
          .length;
      return [
        AnalysisDietCard(
          title: count > 0 ? 'CGM 演示观察' : 'CGM 预留入口',
          signal: 'observe',
          evidence: count > 0 ? '当前有 $count 条 CGM 记录' : '当前还没有连续血糖记录',
          suggestion: '可结合餐次查看峰值、回落和目标范围内时间。',
          nextRecord: '演示账号可预置 CGM 数据',
        ),
      ];
    }
    final signals = provider.analysisReport.foodSignals;
    if (signals.isNotEmpty) {
      return signals.take(3).map((signal) {
        final avg = signal.avgExcursion == null
            ? '暂无足量升幅样本'
            : '平均餐后升幅 ${signal.avgExcursion!.toStringAsFixed(1)} mmol/L';
        return AnalysisDietCard(
          title: signal.foodName,
          signal: signal.signalLevel,
          evidence: '参与 ${signal.mealCount} 餐，$avg',
          suggestion: signal.reason.isEmpty ? '先保持观察，继续配对记录。' : signal.reason,
          nextRecord: '下次补餐后2小时血糖',
        );
      }).toList();
    }
    final localSignals = provider.foodSignals.take(3).map((signal) {
      return AnalysisDietCard(
        title: signal.name,
        signal: signal.level,
        evidence: '基于当前饮食、血糖和状态记录观察',
        suggestion: signal.reason,
        nextRecord: '继续补餐后血糖和状态',
      );
    }).toList();
    return localSignals.isEmpty
        ? const [
            AnalysisDietCard(
              title: '饮食观察',
              signal: 'observe',
              evidence: '样本还少，暂时看不出稳定规律。',
              suggestion: '先选择一餐固定记录餐后血糖和状态。',
              nextRecord: '餐后2小时补血糖',
            ),
          ]
        : localSignals;
  }
}

class _DietObservationTile extends StatelessWidget {
  final AnalysisDietCard card;

  const _DietObservationTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final color = _signalColor(card.signal);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                _StatusChip(text: _signalLabel(card.signal), color: color),
              ],
            ),
            const SizedBox(height: 10),
            _LabelText(label: '证据', text: card.evidence),
            const SizedBox(height: 8),
            _LabelText(label: '建议', text: card.suggestion),
            const SizedBox(height: 8),
            _LabelText(label: '下次补', text: card.nextRecord),
          ],
        ),
      ),
    );
  }

  Color _signalColor(String signal) {
    if (signal == 'red') return AppColors.red;
    if (signal == 'yellow') return AppColors.yellow;
    if (signal == 'green') return AppColors.green;
    return AppColors.lavender;
  }

  String _signalLabel(String signal) {
    if (signal == 'red') return '红灯';
    if (signal == 'yellow') return '黄灯';
    if (signal == 'green') return '绿灯';
    return '观察';
  }
}

class _ExerciseAdviceCard extends StatelessWidget {
  final HealthProvider provider;

  const _ExerciseAdviceCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final card = provider.analysisCards.isLlm
        ? provider.analysisCards.exerciseCard
        : _fallbackExerciseCard(provider);
    return SoftCard(
      title: '运动建议',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.lavenderSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.directions_walk,
                    size: 20,
                    color: AppColors.lavender,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(card.title, style: AppTextStyles.section),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _LabelText(label: '证据', text: card.evidence),
              const SizedBox(height: 8),
              _LabelText(label: '建议', text: card.suggestion),
            ],
          ),
        ),
      ),
    );
  }

  AnalysisExerciseCard _fallbackExerciseCard(HealthProvider provider) {
    final minutes = provider.exerciseHistory.fold<int>(0, (sum, item) {
      return sum + (int.tryParse('${item['duration']}') ?? 0);
    });
    return AnalysisExerciseCard(
      title: minutes > 0 ? '继续轻运动' : '饭后轻动',
      evidence: minutes > 0 ? '本周已记录运动约 $minutes 分钟' : '本周运动记录偏少',
      suggestion: provider.exerciseSuggestion,
    );
  }
}

class _NextStepsCard extends StatelessWidget {
  final HealthProvider provider;

  const _NextStepsCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final steps = provider.analysisCards.isLlm
        ? provider.analysisCards.nextSteps
        : _fallbackNextSteps(provider);
    return SoftCard(
      title: '下一步补记录',
      child: Column(
        children: [
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == steps.length - 1 ? 0 : 10,
              ),
              child: _NextStepTile(step: step),
            );
          }),
          const SizedBox(height: 14),
          Text(provider.analysisCards.safetyNote, style: AppTextStyles.caption),
        ],
      ),
    );
  }

  List<AnalysisNextStep> _fallbackNextSteps(HealthProvider provider) {
    final steps = <AnalysisNextStep>[];
    if (provider.glucoseHistory.length < 4 || provider.mealHistory.isNotEmpty) {
      steps.add(const AnalysisNextStep(type: 'glucose', task: '餐后2小时补血糖'));
    }
    if (provider.statusHistory.length < provider.mealHistory.length) {
      steps.add(const AnalysisNextStep(type: 'status', task: '餐后犯困时记状态'));
    }
    if (provider.exerciseHistory.isEmpty) {
      steps.add(const AnalysisNextStep(type: 'exercise', task: '饭后轻走后记运动'));
    }
    if (steps.isEmpty) {
      steps.add(const AnalysisNextStep(type: 'diet', task: '继续记录下一餐搭配'));
    }
    return steps.take(4).toList();
  }
}

class _NextStepTile extends StatelessWidget {
  final AnalysisNextStep step;

  const _NextStepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(step.type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_typeIcon(step.type), color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(step.task, style: AppTextStyles.body)),
      ],
    );
  }

  Color _typeColor(String type) {
    if (type == 'glucose') return AppColors.primary;
    if (type == 'exercise') return AppColors.lavender;
    if (type == 'status') return AppColors.yellow;
    return AppColors.green;
  }

  IconData _typeIcon(String type) {
    if (type == 'glucose') return Icons.water_drop;
    if (type == 'exercise') return Icons.directions_walk;
    if (type == 'status') return Icons.mood;
    return Icons.restaurant;
  }
}

class _LabelText extends StatelessWidget {
  final String label;
  final String text;

  const _LabelText({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: '$label：',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(
            text: text,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(color: AppColors.text),
        ),
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  final String text;

  const _InlineLoading({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(text, style: AppTextStyles.caption),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableText(this.text, {required this.style});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.text.length > 90;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: widget.style,
        ),
        if (canExpand)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.only(top: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? '收起' : '展开'),
          ),
      ],
    );
  }
}

class _AnalysisEmptyState extends StatelessWidget {
  const _AnalysisEmptyState();

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      child: SizedBox(
        height: 180,
        child: Center(
          child: Text(
            '暂无足够数据，请继续记录',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
        ),
      ),
    );
  }
}

class _AnalysisSkeleton extends StatelessWidget {
  const _AnalysisSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Column(
        children: [
          _SkeletonSoftCard(height: 92),
          SizedBox(height: 16),
          _SkeletonSoftCard(height: 260),
          SizedBox(height: 16),
          _SkeletonSoftCard(height: 150),
        ],
      ),
    );
  }
}

class _SkeletonSoftCard extends StatelessWidget {
  final double height;

  const _SkeletonSoftCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SkeletonBlock(width: 124, height: 14),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: const [
                  Expanded(child: _SkeletonBlock()),
                  SizedBox(width: 12),
                  Expanded(child: _SkeletonBlock()),
                  SizedBox(width: 12),
                  Expanded(child: _SkeletonBlock()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double? width;
  final double? height;

  const _SkeletonBlock({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final width = bounds.width;
            final dx = (width * 2) * _controller.value - width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.line.withValues(alpha: 0.55),
                AppColors.surface.withValues(alpha: 0.75),
                AppColors.line.withValues(alpha: 0.55),
              ],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlidingGradientTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double dx;

  const _SlidingGradientTransform(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

class _AnalysisDisplayData {
  final bool isCgmMode;
  final double? avgGlucose;
  final double? cv;
  final double? inRangeRatio;
  final List<_EnergyItem> energyItems;
  final String summaryText;
  final String summarySource;
  final List<String> qualityMessages;

  const _AnalysisDisplayData({
    required this.isCgmMode,
    required this.avgGlucose,
    required this.cv,
    required this.inRangeRatio,
    required this.energyItems,
    required this.summaryText,
    required this.summarySource,
    required this.qualityMessages,
  });

  factory _AnalysisDisplayData.fromManual(HealthProvider provider) {
    final report = provider.analysisReport;
    final useRemote = provider.analysisError == null && report.hasRemoteData;
    if (useRemote) {
      return _AnalysisDisplayData(
        isCgmMode: false,
        avgGlucose: report.weeklySummaryMetrics.avgGlucose,
        cv: report.weeklySummaryMetrics.cv,
        inRangeRatio: report.weeklySummaryMetrics.inRangeRatio,
        energyItems: report.energyCorrelation.map(_EnergyItem.remote).toList(),
        summaryText: report.summaryText,
        summarySource: report.summarySource,
        qualityMessages: report.dataQuality.messages,
      );
    }

    final local = _LocalGlucoseStats.fromRecords(provider.glucoseHistory);
    final insight = provider.manualInsight;
    return _AnalysisDisplayData(
      isCgmMode: false,
      avgGlucose: local.avgGlucose,
      cv: local.cv,
      inRangeRatio: local.inRangeRatio,
      energyItems: [
        _EnergyItem(
          text: '观察到的相关性：${insight.possibleCause}',
          scoreText: provider.statusHistory.isEmpty ? null : '已记录状态',
        ),
      ],
      summaryText: _buildLocalSummaryText(local, provider.statusHistory),
      summarySource: 'local',
      qualityMessages: const ['继续记录后，这里会给出更准确的趋势分析。'],
    );
  }

  factory _AnalysisDisplayData.fromCgm(HealthProvider provider) {
    final cgmRecords = provider.glucoseHistory
        .where((record) => '${record['source']}' == 'cgm')
        .toList();
    final local = _LocalGlucoseStats.fromRecords(cgmRecords);
    return _AnalysisDisplayData(
      isCgmMode: true,
      avgGlucose: local.avgGlucose,
      cv: local.cv,
      inRangeRatio: local.inRangeRatio,
      energyItems: [
        _EnergyItem(
          text: cgmRecords.isEmpty
              ? '观察到的相关性：CGM 视图是预留能力，接入连续血糖后再比较波动和精力。'
              : '观察到的相关性：当前 CGM 记录可先用于查看日内波动，暂不直接推断原因。',
        ),
      ],
      summaryText: cgmRecords.isEmpty
          ? 'CGM 分析会重点查看连续波动、TIR、夜间偏低和餐后回落速度；当前版本先保留扩展入口。'
          : '当前有 ${cgmRecords.length} 条 CGM 记录，可先观察目标范围内时间和波动幅度，具体建议仍需结合饮食、运动和状态记录。',
      summarySource: 'template',
      qualityMessages: const ['CGM 指标只在连续血糖数据充足时使用。'],
    );
  }
}

class _LocalGlucoseStats {
  final double? avgGlucose;
  final double? cv;
  final double? inRangeRatio;
  final double? minGlucose;
  final double? maxGlucose;
  final double? latestGlucose;

  const _LocalGlucoseStats({
    required this.avgGlucose,
    required this.cv,
    required this.inRangeRatio,
    required this.minGlucose,
    required this.maxGlucose,
    required this.latestGlucose,
  });

  factory _LocalGlucoseStats.fromRecords(List<Map<String, dynamic>> records) {
    final normalized =
        records
            .map(_LocalGlucoseReading.fromRecord)
            .whereType<_LocalGlucoseReading>()
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (normalized.isEmpty) {
      return const _LocalGlucoseStats(
        avgGlucose: null,
        cv: null,
        inRangeRatio: null,
        minGlucose: null,
        maxGlucose: null,
        latestGlucose: null,
      );
    }

    final values = normalized.map((item) => item.value).toList();
    final avg = _average(values);
    final sd = _stddevSample(values);
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);

    return _LocalGlucoseStats(
      avgGlucose: _round(avg),
      cv: avg == null || sd == null || avg <= 0
          ? null
          : _round(sd / avg * 100, 1),
      inRangeRatio: _round(_inRangeRatio(values), 3),
      minGlucose: _round(min),
      maxGlucose: _round(max),
      latestGlucose: _round(normalized.last.value),
    );
  }
}

class _LocalGlucoseReading {
  final DateTime time;
  final double value;

  const _LocalGlucoseReading({required this.time, required this.value});

  static _LocalGlucoseReading? fromRecord(Map<String, dynamic> record) {
    final time = DateTime.tryParse('${record['record_time'] ?? ''}')?.toLocal();
    final value = _normalizeGlucose(record['value'], record['unit']);
    if (time == null || value == null) return null;
    return _LocalGlucoseReading(time: time, value: value);
  }
}

class _EnergyItem {
  final String text;
  final String? scoreText;

  const _EnergyItem({required this.text, this.scoreText});

  factory _EnergyItem.remote(EnergyCorrelationItem item) {
    return _EnergyItem(
      text: '观察到的相关性：${item.insight}',
      scoreText: item.avgEnergy == null
          ? '${item.dayCount} 天'
          : '${item.avgEnergy!.toStringAsFixed(1)} / 5',
    );
  }
}

String _buildLocalSummaryText(
  _LocalGlucoseStats stats,
  List<Map<String, dynamic>> statusHistory,
) {
  final min = stats.minGlucose;
  final max = stats.maxGlucose;
  final latest = stats.latestGlucose;
  if (min == null || max == null || latest == null) {
    return '近期记录的数据较少，继续保持日常打卡，我会为您提供更准确的趋势分析哦。';
  }

  final spread = max - min;
  final stability = stats.cv == null
      ? (spread <= 2.0 ? '比较平稳' : '略有波动')
      : (stats.cv! < AnalysisService.glucoseCvStableThreshold
            ? '比较平稳'
            : '略有波动');
  final statusText = statusHistory.isEmpty
      ? ''
      : '最近状态记录显示${statusHistory.first['status_level']}，';
  return '近期血糖主要在 ${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)} mmol/L 之间，最新记录为 ${latest.toStringAsFixed(1)}，整体表现$stability。$statusText请继续给容易犯困或饥饿的餐次打标签，这样能帮您发现更多饮食规律哦。';
}

double? _normalizeGlucose(Object? value, Object? unit) {
  final parsed = double.tryParse('${value ?? ''}');
  if (parsed == null || parsed <= 0) return null;
  if ('${unit ?? 'mmol/L'}' == 'mg/dL') return parsed / 18.0;
  return parsed;
}

double? _average(List<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((sum, value) => sum + value) / values.length;
}

double? _stddevSample(List<double> values) {
  if (values.length < 2) return null;
  final avg = _average(values)!;
  final variance =
      values.fold<double>(
        0,
        (sum, value) => sum + math.pow(value - avg, 2).toDouble(),
      ) /
      (values.length - 1);
  return math.sqrt(variance);
}

double? _inRangeRatio(List<double> values) {
  if (values.isEmpty) return null;
  final inRange = values.where((value) {
    return value >= AnalysisService.glucoseLowTarget &&
        value <= AnalysisService.glucoseHighTarget;
  }).length;
  return inRange / values.length;
}

double? _round(double? value, [int digits = 2]) {
  if (value == null || !value.isFinite) return null;
  final factor = math.pow(10, digits).toDouble();
  return (value * factor).round() / factor;
}
