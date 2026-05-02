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
      final drafts = result.items.isEmpty
          ? [_FoodDraft.empty(imageUrl: result.storagePath)]
          : await Future.wait(
              result.items.map((item) async {
                final draft = _FoodDraft.fromRecognition(
                  item,
                  imageUrl: result.storagePath,
                );
                final matches = await repository.searchFoodCalorieCatalog(
                  item.foodNameRaw,
                );
                draft.catalogMatches = matches;
                if (matches.isNotEmpty) {
                  draft.applyCatalogItem(matches.first);
                }
                return draft;
              }),
            );
      _replaceDrafts(drafts);
      if (result.items.isEmpty) {
        _showSnack('没识别清楚，可以手动填一下');
      }
    } catch (error) {
      _replaceDrafts([_FoodDraft.empty()]);
      _showSnack('识别没跑通，先手动记录也可以：$error');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
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
            trailing: TextButton.icon(
              style: AppButtonStyles.quiet,
              onPressed: () => setState(() {
                _drafts.add(_FoodDraft.empty());
              }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('手动加'),
            ),
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
          for (var i = 0; i < _drafts.length; i++) ...[
            Builder(builder: (context) {
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
                onRemove: () {
                  final removed = _drafts.removeAt(index);
                  removed.dispose();
                  setState(() {});
                },
              );
            }),
            const SizedBox(height: 14),
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
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${meal['meal_type']} · ${AppFormat.compactDateTime(meal['meal_time'])}',
                          ),
                          trailing: Text(
                            '${(double.tryParse('${meal['calories_final']}') ?? 0).toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryDark,
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
    return SoftCard(
      title: '食物 ${widget.index + 1}',
      trailing: widget.canRemove
          ? IconButton(
              tooltip: '删除',
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close, color: AppColors.muted),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: draft.rawNameCtrl,
            decoration: _fieldDecoration('识别名称', Icons.image_search),
            onChanged: (_) => widget.onChanged(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: draft.confirmedNameCtrl,
            decoration: _fieldDecoration('确认后的食物名', Icons.edit_outlined),
            onChanged: _searchCatalog,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: draft.rawCalCtrl,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(
              '每100g热量 kcal',
              Icons.local_fire_department_outlined,
            ),
            onChanged: (_) {
              draft.manualFinalCalories = false;
              draft.syncFinalCalories();
              widget.onChanged();
            },
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: draft.catalogMatches.take(4).map((item) {
                return ActionChip(
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
            const SizedBox(height: 14),
            const Text('常见份量', style: AppTextStyles.section),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: draft.servingOptions.entries.map((entry) {
                final selected = draft.servingUnit == entry.key;
                return ChoiceChip(
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
          const SizedBox(height: 12),
          TextField(
            controller: draft.gramsCtrl,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration('克重 g', Icons.scale_outlined),
            onChanged: (_) {
              draft.servingUnit = 'g';
              draft.manualFinalCalories = false;
              draft.syncFinalCalories();
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: draft.finalCalCtrl,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(
              '最终热量 kcal（可手动覆盖）',
              Icons.calculate_outlined,
            ),
            onChanged: (_) {
              draft.manualFinalCalories = true;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primaryDark),
      filled: true,
      fillColor: AppColors.background,
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
  String servingUnit;
  Map<String, double> servingOptions;
  List<FoodCalorieCatalogItem> catalogMatches;
  bool manualFinalCalories = false;

  _FoodDraft({
    required String rawName,
    required String confirmedName,
    required double rawCalories,
    required double grams,
    required this.servingUnit,
    required this.servingOptions,
    required this.catalogMatches,
    required this.imageUrl,
  })  : rawNameCtrl = TextEditingController(text: rawName),
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
      confirmedName: item.foodNameRaw,
      rawCalories: item.caloriesRaw,
      grams: 100,
      servingUnit: 'g',
      servingOptions: const {},
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
