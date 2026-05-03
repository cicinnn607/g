import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/app_messages.dart';
import '../core/app_style.dart';
import '../provider/health_provider.dart';
import '../services/analysis_service.dart';
import '../services/health_repository.dart';
import '../widgets/soft_card.dart';

class DietRecordPage extends StatefulWidget {
  const DietRecordPage({super.key});

  @override
  State<DietRecordPage> createState() => _DietRecordPageState();
}

class _DietRecordPageState extends State<DietRecordPage> {
  final _mealTypes = const ['早餐', '午餐', '晚餐', '加餐'];
  final ImagePicker _picker = ImagePicker();
  final List<_FoodDraft> _drafts = [_FoodDraft.empty()];

  String _mealType = '午餐';
  DateTime _mealTime = DateTime.now();
  XFile? _pickedImage;
  bool _recognizing = false;
  bool _saving = false;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _mealTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_mealTime),
    );
    if (time == null) return;
    setState(() {
      _mealTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _mealType = _guessMealType(_mealTime);
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final repository = context.read<HealthProvider>().repository;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;

    setState(() {
      _pickedImage = picked;
      _recognizing = true;
    });

    try {
      final result = await repository.recognizeMealImage(picked);
      if (result.items.isEmpty) {
        _replaceDrafts([_FoodDraft.empty(imageUrl: result.storagePath)]);
        _showSnack('没识别清楚，可以手动填一下');
      } else if (mounted) {
        final selected = await _showRecognitionSheet(
          items: result.items,
          imageUrl: result.storagePath,
        );
        if (selected != null) {
          _replaceDrafts([selected]);
        }
      }
    } catch (error) {
      _replaceDrafts([_FoodDraft.empty()]);
      _showSnack('识别没跑通，先手动记录也可以：$error');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  Future<_FoodDraft?> _showRecognitionSheet({
    required List<MealRecognitionItem> items,
    required String imageUrl,
  }) async {
    return showModalBottomSheet<_FoodDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FoodRecognitionBottomSheet(items: items, imageUrl: imageUrl);
      },
    );
  }

  void _addManualDraft() {
    setState(() {
      _drafts.add(_FoodDraft.empty());
    });
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) {
      final replacement = _FoodDraft.empty();
      final removed = _drafts[index];
      setState(() {
        _drafts[index] = replacement;
      });
      removed.dispose();
      return;
    }

    final removed = _drafts.removeAt(index);
    setState(() {});
    removed.dispose();
  }

  void _replaceDrafts(List<_FoodDraft> drafts) {
    for (final draft in _drafts) {
      draft.dispose();
    }
    setState(() {
      _drafts
        ..clear()
        ..addAll(drafts);
    });
  }

  Future<void> _save() async {
    final items = _drafts
        .where((draft) => draft.confirmedName.trim().isNotEmpty)
        .map(
          (draft) => MealItemDraft(
            foodNameRaw: draft.rawName.trim(),
            foodNameConfirmed: draft.confirmedName.trim(),
            caloriesRaw: draft.rawCalories,
            carbsRaw: draft.carbsPer100g,
            proteinRaw: draft.proteinPer100g,
            fatRaw: draft.fatPer100g,
            giValueSnapshot: draft.giValue,
            grams: draft.grams,
            servingUnit: draft.servingUnit,
            caloriesUserOverride: draft.caloriesUserOverride,
            imageUrl: draft.imageUrl,
          ),
        )
        .toList();
    if (items.isEmpty) {
      _showSnack('至少填一个食物名');
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<HealthProvider>();
    try {
      await provider.repository.saveMeal(
        mealType: _mealType,
        mealTime: _mealTime,
        items: items,
      );
      await provider.loadDashboardData();
      if (!mounted) return;
      _replaceDrafts([_FoodDraft.empty()]);
      setState(() {
        _pickedImage = null;
        _mealTime = DateTime.now();
        _mealType = _guessMealType(_mealTime);
      });
      _showSnack('这一餐记好了');
    } catch (error) {
      _showSnack(friendlyActionError(error, action: '保存饮食'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String mealId) async {
    final provider = context.read<HealthProvider>();
    await provider.repository.deleteMeal(mealId);
    await provider.loadDashboardData();
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.primaryDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('饮食')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          SoftCard(
            title: '拍一下这餐',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pickedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.file(
                        File(_pickedImage!.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: AppButtonStyles.outline,
                        onPressed: _recognizing
                            ? null
                            : () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('拍照'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: AppButtonStyles.outline,
                        onPressed: _recognizing
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('相册'),
                      ),
                    ),
                  ],
                ),
                if (_recognizing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.primary,
                    backgroundColor: AppColors.line,
                  ),
                  const SizedBox(height: 8),
                  const Text('正在识别，等它一小会儿', style: AppTextStyles.caption),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _mealTypes
                      .map(
                        (type) => ChoiceChip(
                          label: Text(type),
                          selected: _mealType == type,
                          selectedColor: AppColors.primarySoft,
                          onSelected: (_) => setState(() => _mealType = type),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: AppButtonStyles.outline.copyWith(
                    minimumSize: const WidgetStatePropertyAll(
                      Size.fromHeight(46),
                    ),
                  ),
                  onPressed: _pickDateTime,
                  icon: const Icon(Icons.access_time),
                  label: Text('用餐时间：${_formatDateTime(_mealTime)}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('本餐食物', style: AppTextStyles.section)),
              TextButton.icon(
                style: AppButtonStyles.quiet,
                onPressed: _addManualDraft,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加食物'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _drafts.length; i++) ...[
            Builder(
              builder: (context) {
                final index = i;
                return _FoodDraftCard(
                  index: index,
                  draft: _drafts[index],
                  canRemove: _drafts.length > 1,
                  onChanged: () => setState(() {}),
                  onSearchCatalog: (query) {
                    return context
                        .read<HealthProvider>()
                        .repository
                        .searchFoodCalorieCatalog(query);
                  },
                  onRemove: () => _removeDraft(index),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: AppButtonStyles.primary,
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? '保存中' : '保存这一餐'),
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            title: '最近吃过',
            child: provider.mealHistory.isEmpty
                ? const SizedBox(
                    height: 90,
                    child: Center(
                      child: Text('还没有饮食记录', style: AppTextStyles.caption),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.mealHistory.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final meal = provider.mealHistory[index];
                      final mealId = '${meal['id'] ?? meal['meal_id']}';
                      return Dismissible(
                        key: Key('meal_$mealId'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: AppColors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete(mealId),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.greenSoft,
                            child: const Icon(
                              Icons.restaurant,
                              color: AppColors.green,
                            ),
                          ),
                          title: Text(
                            '${meal['serving_summary'] ?? meal['food_names'] ?? '这一餐'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.listTitle,
                          ),
                          subtitle: Text(
                            '${meal['meal_type']} · ${AppFormat.compactDateTime(meal['meal_time'])}',
                            style: AppTextStyles.listSubtitle,
                          ),
                          trailing: Text(
                            '${(double.tryParse('${meal['calories_final']}') ?? 0).toStringAsFixed(0)} kcal',
                            style: AppTextStyles.listMeta,
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

  String _guessMealType(DateTime time) {
    if (time.hour < 10) return '早餐';
    if (time.hour < 15) return '午餐';
    if (time.hour < 20) return '晚餐';
    return '加餐';
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
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }
}

enum _RecognitionStep { selectFood, selectPortion }

class _FoodRecognitionBottomSheet extends StatefulWidget {
  final List<MealRecognitionItem> items;
  final String imageUrl;

  const _FoodRecognitionBottomSheet({
    required this.items,
    required this.imageUrl,
  });

  @override
  State<_FoodRecognitionBottomSheet> createState() =>
      _FoodRecognitionBottomSheetState();
}

class _FoodRecognitionBottomSheetState
    extends State<_FoodRecognitionBottomSheet> {
  _RecognitionStep _step = _RecognitionStep.selectFood;
  late MealRecognitionItem _selected = widget.items.first;
  late double _selectedWeight = _initialWeight(_selected);
  late String _selectedServing = _initialServing(_selected);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _step == _RecognitionStep.selectFood
              ? _buildFoodSelection()
              : _buildPortionSelection(),
        ),
      ),
    );
  }

  Widget _buildFoodSelection() {
    return Column(
      key: const ValueKey('food-selection'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('选择识别结果', style: AppTextStyles.pageTitle),
        const SizedBox(height: 4),
        const Text('确认后再选择这一份大概有多少克', style: AppTextStyles.caption),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: item.isAiGenerated
                      ? AppColors.yellowSoft
                      : AppColors.greenSoft,
                  child: Icon(
                    item.isAiGenerated
                        ? Icons.auto_awesome
                        : Icons.restaurant_menu,
                    color: item.isAiGenerated
                        ? AppColors.yellow
                        : AppColors.green,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.foodNameConfirmed ?? item.foodNameRaw,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.listTitle,
                      ),
                    ),
                    if (item.isAiGenerated) const _AiEstimateBadge(),
                  ],
                ),
                subtitle: Text(
                  '${item.caloriesRaw.toStringAsFixed(0)} kcal/100g'
                  '${item.confidence > 0 ? ' · 匹配 ${(item.confidence * 100).toStringAsFixed(0)}%' : ''}',
                  style: AppTextStyles.listSubtitle,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _selected = item;
                    _selectedWeight = _initialWeight(item);
                    _selectedServing = _initialServing(item);
                    _step = _RecognitionStep.selectPortion;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPortionSelection() {
    final totalCalories = AnalysisService.calculateMealCaloriesByGrams(
      _selected.caloriesRaw,
      _selectedWeight,
    );
    final totalCarbs = AnalysisService.calculateNutrientByGrams(
      _selected.carbsPer100g,
      _selectedWeight,
    );
    final options = _selected.servingOptions.isEmpty
        ? const {'100克': 100.0}
        : _selected.servingOptions;

    return Column(
      key: const ValueKey('portion-selection'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: () {
                setState(() => _step = _RecognitionStep.selectFood);
              },
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                _selected.foodNameConfirmed ?? _selected.foodNameRaw,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.pageTitle,
              ),
            ),
            if (_selected.isAiGenerated) const _AiEstimateBadge(),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricPill(
                label: '热量',
                value: totalCalories.toStringAsFixed(0),
                unit: 'kcal',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricPill(
                label: '碳水',
                value: totalCarbs.toStringAsFixed(1),
                unit: 'g',
                color: AppColors.yellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('常见份量', style: AppTextStyles.section),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            final selected = _selectedServing == entry.key;
            return ChoiceChip(
              label: Text('${entry.key} · ${entry.value.toStringAsFixed(0)}g'),
              selected: selected,
              selectedColor: AppColors.primarySoft,
              onSelected: (_) {
                setState(() {
                  _selectedServing = entry.key;
                  _selectedWeight = entry.value;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: AppButtonStyles.primary,
            onPressed: () {
              final draft = _FoodDraft.fromRecognition(
                _selected,
                imageUrl: widget.imageUrl,
              );
              draft.selectServing(_selectedServing, _selectedWeight);
              Navigator.of(context).pop(draft);
            },
            icon: const Icon(Icons.check),
            label: const Text('确认这份'),
          ),
        ),
      ],
    );
  }

  static double _initialWeight(MealRecognitionItem item) {
    if (item.servingOptions.isEmpty) return 100;
    return item.servingOptions.values.first;
  }

  static String _initialServing(MealRecognitionItem item) {
    if (item.servingOptions.isEmpty) return '100克';
    return item.servingOptions.keys.first;
  }
}

class _FoodDraftCard extends StatefulWidget {
  final int index;
  final _FoodDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final Future<List<FoodCalorieCatalogItem>> Function(String query)
  onSearchCatalog;

  const _FoodDraftCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onSearchCatalog,
  });

  @override
  State<_FoodDraftCard> createState() => _FoodDraftCardState();
}

class _FoodDraftCardState extends State<_FoodDraftCard> {
  int _searchToken = 0;
  bool _searching = false;

  _FoodDraft get draft => widget.draft;

  Future<void> _searchCatalog(String query) async {
    final normalized = query.trim();
    final token = ++_searchToken;
    if (normalized.length < 2) {
      setState(() => _searching = false);
      draft.catalogMatches = const [];
      widget.onChanged();
      return;
    }

    setState(() => _searching = true);
    final matches = await widget.onSearchCatalog(normalized);
    if (!mounted || token != _searchToken) return;

    setState(() => _searching = false);
    draft.catalogMatches = matches;
    if (matches.isNotEmpty) {
      draft.applyCatalogItem(matches.first);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '食物 ${widget.index + 1}',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (draft.isAiGenerated) ...[
                const _AiEstimateBadge(),
                const SizedBox(width: 6),
              ],
              IconButton(
                tooltip: widget.canRemove ? '删除' : '清空',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: widget.onRemove,
                icon: Icon(
                  widget.canRemove ? Icons.close : Icons.refresh,
                  size: 18,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          if (draft.isFromRecognition && draft.rawName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('识别：${draft.rawName}', style: AppTextStyles.tiny),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: draft.confirmedNameCtrl,
            textInputAction: TextInputAction.next,
            decoration: _compactDecoration('食物名', Icons.restaurant_outlined),
            onChanged: _searchCatalog,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.rawCalCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: _compactDecoration(
                    '每100g',
                    Icons.local_fire_department_outlined,
                    suffix: 'kcal',
                  ),
                  onChanged: (_) {
                    draft.manualFinalCalories = false;
                    draft.syncFinalCalories();
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.gramsCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: _compactDecoration(
                    '克重',
                    Icons.scale_outlined,
                    suffix: 'g',
                  ),
                  onChanged: (_) {
                    draft.servingUnit = 'g';
                    draft.manualFinalCalories = false;
                    draft.syncFinalCalories();
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.finalCalCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: _compactDecoration(
                    '总热量',
                    Icons.calculate_outlined,
                    suffix: 'kcal',
                  ),
                  onChanged: (_) {
                    draft.manualFinalCalories = true;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          if (_searching) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.line,
            ),
          ],
          if (draft.catalogMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: draft.catalogMatches.take(4).map((item) {
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: AppTextStyles.tiny.copyWith(
                    color: AppColors.text,
                  ),
                  label: Text(
                    '${item.name} · '
                    '${item.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
                  ),
                  onPressed: () {
                    setState(() => draft.applyCatalogItem(item));
                    widget.onChanged();
                  },
                );
              }).toList(),
            ),
          ],
          if (draft.servingOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: draft.servingOptions.entries.map((entry) {
                final selected = draft.servingUnit == entry.key;
                return ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: AppTextStyles.tiny.copyWith(
                    color: selected ? AppColors.primaryDark : AppColors.text,
                  ),
                  label: Text(
                    '${entry.key} · ${entry.value.toStringAsFixed(0)}g',
                  ),
                  selected: selected,
                  selectedColor: AppColors.primarySoft,
                  onSelected: (_) {
                    setState(() => draft.selectServing(entry.key, entry.value));
                    widget.onChanged();
                  },
                );
              }).toList(),
            ),
          ],
          if (draft.carbsPer100g != null ||
              draft.proteinPer100g != null ||
              draft.fatPer100g != null ||
              draft.giValue != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (draft.carbsPer100g != null)
                  _NutritionChip(
                    label: '碳水',
                    value: '${draft.totalCarbs.toStringAsFixed(1)}g',
                  ),
                if (draft.proteinPer100g != null)
                  _NutritionChip(
                    label: '蛋白',
                    value:
                        '${AnalysisService.calculateNutrientByGrams(draft.proteinPer100g, draft.grams).toStringAsFixed(1)}g',
                  ),
                if (draft.fatPer100g != null)
                  _NutritionChip(
                    label: '脂肪',
                    value:
                        '${AnalysisService.calculateNutrientByGrams(draft.fatPer100g, draft.grams).toStringAsFixed(1)}g',
                  ),
                if (draft.giValue != null)
                  _NutritionChip(
                    label: 'GI',
                    value: draft.giValue!.toStringAsFixed(0),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _compactDecoration(
    String label,
    IconData icon, {
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      prefixIcon: Icon(icon, color: AppColors.primaryDark, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 36),
      filled: true,
      fillColor: AppColors.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _FoodDraft {
  final TextEditingController rawNameCtrl;
  final TextEditingController confirmedNameCtrl;
  final TextEditingController rawCalCtrl;
  final TextEditingController gramsCtrl;
  final TextEditingController finalCalCtrl;
  final String? imageUrl;
  double? carbsPer100g;
  double? proteinPer100g;
  double? fatPer100g;
  double? giValue;
  bool isAiGenerated;
  bool isFromRecognition;
  String servingUnit;
  Map<String, double> servingOptions;
  List<FoodCalorieCatalogItem> catalogMatches;
  bool manualFinalCalories = false;

  _FoodDraft({
    required String rawName,
    required String confirmedName,
    required double rawCalories,
    this.carbsPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.giValue,
    this.isAiGenerated = false,
    this.isFromRecognition = false,
    required double grams,
    required this.servingUnit,
    required this.servingOptions,
    required this.catalogMatches,
    required this.imageUrl,
  }) : rawNameCtrl = TextEditingController(text: rawName),
       confirmedNameCtrl = TextEditingController(text: confirmedName),
       rawCalCtrl = TextEditingController(text: rawCalories.toStringAsFixed(0)),
       gramsCtrl = TextEditingController(text: grams.toStringAsFixed(0)),
       finalCalCtrl = TextEditingController(
         text: AnalysisService.calculateMealCaloriesByGrams(
           rawCalories,
           grams,
         ).toStringAsFixed(1),
       );

  factory _FoodDraft.empty({String? imageUrl}) {
    return _FoodDraft(
      rawName: '',
      confirmedName: '',
      rawCalories: 0,
      grams: 0,
      servingUnit: 'g',
      servingOptions: const {},
      catalogMatches: const [],
      imageUrl: imageUrl,
    );
  }

  factory _FoodDraft.fromRecognition(
    MealRecognitionItem item, {
    required String imageUrl,
  }) {
    return _FoodDraft(
      rawName: item.foodNameRaw,
      confirmedName: item.foodNameConfirmed ?? item.foodNameRaw,
      rawCalories: item.caloriesRaw,
      carbsPer100g: item.carbsPer100g,
      proteinPer100g: item.proteinPer100g,
      fatPer100g: item.fatPer100g,
      giValue: item.giValue,
      isAiGenerated: item.isAiGenerated,
      isFromRecognition: true,
      grams: item.servingOptions.isEmpty
          ? 100
          : item.servingOptions.values.first,
      servingUnit: item.servingOptions.isEmpty
          ? 'g'
          : item.servingOptions.keys.first,
      servingOptions: item.servingOptions,
      catalogMatches: const [],
      imageUrl: imageUrl,
    );
  }

  String get rawName => rawNameCtrl.text;
  String get confirmedName => confirmedNameCtrl.text;
  double get rawCalories => double.tryParse(rawCalCtrl.text) ?? 0;
  double get grams => double.tryParse(gramsCtrl.text) ?? 0;
  double get finalCalories =>
      double.tryParse(finalCalCtrl.text) ??
      AnalysisService.calculateMealCaloriesByGrams(rawCalories, grams);
  double get totalCarbs =>
      AnalysisService.calculateNutrientByGrams(carbsPer100g, grams);
  double? get caloriesUserOverride {
    if (!manualFinalCalories) return null;
    final value = double.tryParse(finalCalCtrl.text);
    if (value == null || value < 0) return null;
    return value;
  }

  void applyCatalogItem(FoodCalorieCatalogItem item) {
    if (confirmedNameCtrl.text.trim().isEmpty ||
        confirmedNameCtrl.text.trim() == rawNameCtrl.text.trim()) {
      confirmedNameCtrl.text = item.name;
    }
    rawCalCtrl.text = item.caloriesPer100g.toStringAsFixed(0);
    carbsPer100g = item.carbsPer100g;
    proteinPer100g = item.proteinPer100g;
    fatPer100g = item.fatPer100g;
    giValue = item.giValue;
    isAiGenerated = item.isAiGenerated;
    servingOptions = item.servingOptions;
    if (servingOptions.isNotEmpty && grams <= 0) {
      final first = servingOptions.entries.first;
      selectServing(first.key, first.value);
      return;
    }
    manualFinalCalories = false;
    syncFinalCalories();
  }

  void selectServing(String label, double grams) {
    servingUnit = label;
    gramsCtrl.text = grams.toStringAsFixed(0);
    manualFinalCalories = false;
    syncFinalCalories();
  }

  void syncFinalCalories() {
    if (manualFinalCalories) return;
    finalCalCtrl.text = AnalysisService.calculateMealCaloriesByGrams(
      rawCalories,
      grams,
    ).toStringAsFixed(1);
  }

  void dispose() {
    rawNameCtrl.dispose();
    confirmedNameCtrl.dispose();
    rawCalCtrl.dispose();
    gramsCtrl.dispose();
    finalCalCtrl.dispose();
  }
}

class _AiEstimateBadge extends StatelessWidget {
  const _AiEstimateBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.yellowSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.25)),
      ),
      child: const Text(
        'AI估算',
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          color: AppColors.yellow,
        ),
      ),
    );
  }
}

class _NutritionChip extends StatelessWidget {
  final String label;
  final String value;

  const _NutritionChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Text('$label $value', style: AppTextStyles.caption),
    );
  }
}
