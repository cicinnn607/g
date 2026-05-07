import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../core/app_messages.dart';
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
      appBar: AppBar(title: const Text('分析报告')),
      body: Consumer<HealthProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadAnalysisReport();
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
        provider.mealHistory.isEmpty &&
        provider.mealItems.isEmpty &&
        provider.exerciseHistory.isEmpty &&
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
        _ComprehensiveReportCard(
          provider: provider,
          data: data,
          isCgmMode: isCgmMode,
        ),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  final _AnalysisDisplayData data;

  const _MetricsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rangeLabel = data.isCgmMode ? 'TIR' : '达标占比';
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
              helper: '日常基准水平',
              tier: _avgTier(data.avgGlucose),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCell(
              label: '变异系数',
              value: data.cv == null ? '--' : data.cv!.toStringAsFixed(1),
              unit: data.cv == null ? '数据不足' : '%',
              helper: '血糖过山车指数',
              tier: _cvTier(data.cv),
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
              helper: '满血状态时长',
              tier: _rangeTier(data.inRangeRatio),
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

  String _avgTier(double? value) {
    if (value == null) return '样本不足';
    if (value < AnalysisService.glucoseLowTarget) return '偏低，留意低值时段';
    if (value <= 7.8) return '整体较稳';
    if (value <= AnalysisService.glucoseHighTarget) return '略高，继续观察';
    return '偏高，关注餐后记录';
  }

  String _cvTier(double? value) {
    if (value == null) return '样本不足';
    if (value < 20) return '很平稳';
    if (value < AnalysisService.glucoseCvStableThreshold) return '有波动，可接受';
    return '波动明显';
  }

  String _rangeTier(double? value) {
    if (value == null) return '样本不足';
    final percent = value * 100;
    if (percent >= 90) return '大部分时间稳定';
    if (percent >= 70) return '总体还可以';
    return '偏离目标较多';
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String helper;
  final String tier;
  final Color color;

  const _MetricCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.helper,
    required this.tier,
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
            const SizedBox(height: 8),
            Text(
              '💡 $helper',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: AppColors.text),
            ),
            const SizedBox(height: 4),
            Text(
              tier,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
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
            const _InlineLoading(text: '正在生成 AI 分析报告'),
          ],
          if (provider.analysisCardsError != null) ...[
            const SizedBox(height: 12),
            const Text(
              '当前为基础分析，可点击下方按钮重新生成 AI 报告。',
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

class _ComprehensiveReportCard extends StatelessWidget {
  final HealthProvider provider;
  final bool isCgmMode;
  final _AnalysisDisplayData data;

  const _ComprehensiveReportCard({
    required this.provider,
    required this.data,
    required this.isCgmMode,
  });

  @override
  Widget build(BuildContext context) {
    final markdown = isCgmMode
        ? _buildCgmReportMarkdown(provider)
        : _manualReportMarkdown(provider, data);
    final source = _reportSource(provider);
    final sourceColor = _reportSourceColor(source);
    return SoftCard(
      title: '综合分析报告',
      trailing: _StatusChip(text: source, color: sourceColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isCgmMode) ...[
            _GenerateAiReportButton(provider: provider),
            const SizedBox(height: 12),
            if (!_hasRequestedAi(provider)) ...[
              const _ReportNotice(text: '当前显示基础规则报告。点击按钮可连接 AI 生成完整分析报告。'),
              const SizedBox(height: 12),
            ],
          ],
          if (!isCgmMode && provider.isLoadingAnalysisCards)
            const _ReportLoading()
          else ...[
            MarkdownBody(
              data: markdown,
              selectable: false,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    h3: AppTextStyles.section.copyWith(
                      fontSize: 16,
                      height: 1.35,
                    ),
                    p: AppTextStyles.body.copyWith(height: 1.6),
                    listBullet: AppTextStyles.body,
                    strong: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
            ),
            if (!isCgmMode && provider.analysisCards.error != null) ...[
              const SizedBox(height: 12),
              _ReportNotice(
                text: _reportErrorLabel(provider.analysisCards.error),
              ),
            ],
            if (!isCgmMode && provider.analysisCardsError != null) ...[
              const SizedBox(height: 12),
              _ReportNotice(
                text: friendlyAnalysisReportError(provider.analysisCardsError!),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              provider.analysisCards.safetyNote,
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }

  String _reportSource(HealthProvider provider) {
    if (isCgmMode) return 'CGM 预留';
    if (provider.isLoadingAnalysisCards) return '等待 AI';
    if (provider.analysisCards.isLifestyleNoGlucose) {
      if (provider.analysisCards.isLlm && provider.analysisCardsError == null) {
        return 'AI 生活记录报告';
      }
      return '基础生活记录报告';
    }
    if (provider.analysisCards.isLlm && provider.analysisCardsError == null) {
      return 'AI 生成报告';
    }
    return '基础规则报告';
  }

  Color _reportSourceColor(String source) {
    if (source == 'AI 生成报告' || source == 'AI 生活记录报告') {
      return AppColors.lavender;
    }
    if (source == '等待 AI') return AppColors.primary;
    if (source == 'CGM 预留') return AppColors.green;
    return AppColors.yellow;
  }

  String _reportErrorLabel(String? error) {
    switch (error) {
      case 'missing_llm_config':
        return 'AI 配置缺失，当前显示基础规则报告。';
      case 'insufficient_data':
        return '可用于 AI 报告的数据不足，当前显示基础规则报告。';
      case 'llm_timeout':
        return 'AI 等待超时，当前显示基础规则报告。';
      case 'invalid_analysis_report':
        return 'AI 输出未通过安全校验，当前显示基础规则报告。';
      case 'llm_exception':
        return 'AI 生成异常，当前显示基础规则报告。';
      default:
        if (error != null && error.startsWith('llm_http_400')) {
          return 'AI 请求参数异常，当前显示基础规则报告。技术信息：$error';
        }
        if (error != null &&
            (error.startsWith('llm_http_401') ||
                error.startsWith('llm_http_403'))) {
          return 'AI 服务鉴权失败，当前显示基础规则报告。技术信息：$error';
        }
        if (error != null && error.startsWith('llm_http_429')) {
          return 'AI 服务额度或频率受限，当前显示基础规则报告。技术信息：$error';
        }
        if (error != null && error.startsWith('llm_http_')) {
          return 'AI 服务返回异常，当前显示基础规则报告。技术信息：$error';
        }
        return '当前显示基础规则报告。';
    }
  }

  String _manualReportMarkdown(
    HealthProvider provider,
    _AnalysisDisplayData data,
  ) {
    final cards = provider.analysisCards;
    if (provider.analysisCardsError == null &&
        cards.reportMarkdown.trim().isNotEmpty) {
      return cards.reportMarkdown;
    }
    return _buildManualReportMarkdown(provider, data);
  }

  bool _hasRequestedAi(HealthProvider provider) {
    return provider.analysisCards != AnalysisCards.empty ||
        provider.analysisCardsError != null ||
        provider.isLoadingAnalysisCards;
  }
}

class _GenerateAiReportButton extends StatelessWidget {
  final HealthProvider provider;

  const _GenerateAiReportButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isLoading = provider.isLoadingAnalysisCards;
    final hasAiReport =
        provider.analysisCards.isLlm && provider.analysisCardsError == null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading
            ? null
            : () => provider.loadAnalysisCards(force: true),
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(hasAiReport ? Icons.refresh : Icons.auto_awesome),
        label: Text(
          isLoading
              ? 'AI 正在生成...'
              : hasAiReport
              ? '重新生成 AI 分析报告'
              : '生成 AI 分析报告',
        ),
        style: AppButtonStyles.primary,
      ),
    );
  }
}

class _ReportLoading extends StatelessWidget {
  const _ReportLoading();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '正在生成 AI 分析报告，会尽量多等一会儿，不提前用规则报告顶替。',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportNotice extends StatelessWidget {
  final String text;

  const _ReportNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.yellowSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          text,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
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
            child: Text(_expanded ? '收起' : '展开阅读全部 🔽'),
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
  final String summaryText;

  const _AnalysisDisplayData({
    required this.isCgmMode,
    required this.avgGlucose,
    required this.cv,
    required this.inRangeRatio,
    required this.summaryText,
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
        summaryText: report.summaryText,
      );
    }

    final local = _LocalGlucoseStats.fromRecords(provider.glucoseHistory);
    return _AnalysisDisplayData(
      isCgmMode: false,
      avgGlucose: local.avgGlucose,
      cv: local.cv,
      inRangeRatio: local.inRangeRatio,
      summaryText: _buildLocalSummaryText(local, provider.statusHistory),
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
      summaryText: cgmRecords.isEmpty
          ? 'CGM 分析会重点查看连续波动、TIR、夜间偏低和餐后回落速度；当前版本先保留扩展入口。'
          : '当前有 ${cgmRecords.length} 条 CGM 记录，可先观察目标范围内时间和波动幅度，具体建议仍需结合饮食、运动和状态记录。',
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

String _buildManualReportMarkdown(
  HealthProvider provider,
  _AnalysisDisplayData data,
) {
  final glucoseCount = provider.glucoseHistory.length;
  final mealCount = provider.mealHistory.length;
  final exerciseMinutes = provider.exerciseHistory.fold<int>(0, (sum, item) {
    return sum + (int.tryParse('${item['duration']}') ?? 0);
  });
  final statusCount = provider.statusHistory.length;
  final foodSignals = provider.analysisReport.foodSignals.isNotEmpty
      ? provider.analysisReport.foodSignals
            .take(2)
            .map((item) => item.foodName)
            .join('、')
      : provider.foodSignals.take(2).map((item) => item.name).join('、');
  final avgText = data.avgGlucose == null
      ? '平均血糖还需要更多记录来判断'
      : '平均血糖约 ${data.avgGlucose!.toStringAsFixed(1)} mmol/L';
  final rangeText = data.inRangeRatio == null
      ? '达标占比还需要继续观察'
      : '达标占比约 ${(data.inRangeRatio! * 100).toStringAsFixed(0)}%';
  final cvText = data.cv == null
      ? '波动程度暂时样本不足'
      : '血糖过山车指数约 ${data.cv!.toStringAsFixed(1)}%';
  final foodText = foodSignals.isEmpty
      ? '目前饮食样本还少，暂时不对某个食物下结论。先固定记录一类早餐或午餐，更容易看出它和精力之间的关系。'
      : '目前可以优先观察 $foodSignals 这些记录较多的餐食，结合餐后血糖和状态备注判断它们是否让你更犯困或更稳定。';
  final exerciseText = exerciseMinutes > 0
      ? '本周已经记录运动约 $exerciseMinutes 分钟，可以继续观察饭后轻走、快走或其他运动后，餐后状态是否更平稳。'
      : '本周运动记录还少，先从饭后轻走 10 分钟开始，比一上来安排高强度运动更容易坚持。';

  return '''
### 🌟 本周整体概览
本周已有 $glucoseCount 条血糖、$mealCount 餐饮食、$statusCount 条状态记录。$avgText，$cvText，$rangeText。整体报告先以趋势观察为主，继续补齐配对记录后会更准确。

### 🥗 饮食与精力追踪
$foodText

### 🏃‍♂️ 运动与代谢反馈
$exerciseText

### 💡 下一步微量改变
下周先选一个最容易做到的小动作：给一餐补上餐后 2 小时血糖，再写一句当时的精力状态，比如“犯困”“饥饿感强”或“状态稳定”。
''';
}

String _buildCgmReportMarkdown(HealthProvider provider) {
  final count = provider.glucoseHistory
      .where((record) => '${record['source']}' == 'cgm')
      .length;
  if (count == 0) {
    return '''
### 🌟 本周整体概览
CGM 是连续血糖分析的预留入口，当前还没有连续血糖记录。

### 🥗 饮食与精力追踪
接入 CGM 后，这里会结合餐次查看峰值、回落速度和精力状态变化。

### 🏃‍♂️ 运动与代谢反馈
接入连续数据后，可以观察饭后轻运动是否让餐后波动更平缓。

### 💡 下一步微量改变
当前版本先继续使用手动记录；如果后续接入 CGM，再把连续曲线和餐食、运动、状态一起分析。
''';
  }
  return '''
### 🌟 本周整体概览
当前有 $count 条 CGM 记录，可先观察日内波动、目标范围内时间和夜间偏低情况。

### 🥗 饮食与精力追踪
CGM 数据需要和餐食时间配对，才能更清楚地看到某一餐后的峰值和回落节奏。

### 🏃‍♂️ 运动与代谢反馈
饭后轻运动如果记录完整，后续可以和连续曲线对照，看波动是否更平缓。

### 💡 下一步微量改变
继续补齐餐食、运动和状态记录，让 CGM 曲线不只是数字，而能对应到真实生活行为。
''';
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
