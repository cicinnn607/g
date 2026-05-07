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
    final provider = context.read<HealthProvider>();
    final repository = provider.repository;
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
          final sourceItem = selected.sourceItem;
          if (sourceItem != null) {
            await provider.sinkRecognizedFoods([sourceItem]);
          }
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
        return _FoodRecognitionBottomSheet(
          items: items,
          imageUrl: imageUrl,
          provider: context.read<HealthProvider>(),
        );
      },
    );
  }

  Future<void> _addManualDraft() async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _FoodSearchBottomSheet(provider: context.read<HealthProvider>());
      },
    );
    if (!mounted) return;

    final selected = switch (result) {
      _FoodDraft draft => draft,
      _CreateFoodRequest request => await _showCreateFoodDialog(
        request.initialName,
      ),
      _EstimateFoodRequest request => await _showEstimateFoodDialog(
        request.foodName,
      ),
      _ => null,
    };
    if (selected == null || !mounted) return;
    setState(() {
      _drafts.add(selected);
    });
  }

  Future<_FoodDraft?> _showCreateFoodDialog(String initialName) async {
    final provider = context.read<HealthProvider>();
    return showDialog<_FoodDraft>(
      context: context,
      builder: (context) {
        return _CreateCustomFoodDialog(
          initialName: initialName,
          onCreate: (name, calories) {
            return provider.createCustomFood(
              name: name,
              caloriesPer100g: calories,
              servingOptions: const {'100克': 100},
            );
          },
        );
      },
    );
  }

  Future<_FoodDraft?> _showEstimateFoodDialog(String foodName) async {
    final provider = context.read<HealthProvider>();
    return showDialog<_FoodDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _EstimateFoodDialog(foodName: foodName, provider: provider);
      },
    );
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
    try {
      await provider.deleteMealRecord(mealId);
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '删除饮食'));
    }
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
                final draft = _drafts[index];
                if (draft.isEmpty) {
                  return _AddFoodPlaceholder(onTap: _addManualDraft);
                }
                return _FoodDraftCard(
                  draft: draft,
                  canRemove: _drafts.length > 1,
                  onChanged: () => setState(() {}),
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

class _CreateFoodRequest {
  final String initialName;

  const _CreateFoodRequest(this.initialName);
}

class _EstimateFoodRequest {
  final String foodName;

  const _EstimateFoodRequest(this.foodName);
}

class _FoodSearchBottomSheet extends StatefulWidget {
  final HealthProvider provider;

  const _FoodSearchBottomSheet({required this.provider});

  @override
  State<_FoodSearchBottomSheet> createState() => _FoodSearchBottomSheetState();
}

class _FoodSearchBottomSheetState extends State<_FoodSearchBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late Future<List<FoodCalorieCatalogItem>> _recentFuture;
  List<FoodCalorieCatalogItem> _results = const [];
  int _searchToken = 0;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _recentFuture = widget.provider.getRecentFoods(limit: 12);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    final token = ++_searchToken;
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _results = const [];
      });
      return;
    }

    setState(() => _searching = true);
    final results = await widget.provider.searchFoodCalorieCatalog(
      query,
      limit: 12,
    );
    if (!mounted || token != _searchToken) return;
    setState(() {
      _searching = false;
      _results = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
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
        child: Column(
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
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索食物名称...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 14),
            if (query.isEmpty)
              _buildRecentFoods()
            else
              _buildSearchResults(query),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentFoods() {
    return Flexible(
      child: FutureBuilder<List<FoodCalorieCatalogItem>>(
        future: _recentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 140,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            );
          }

          final foods = snapshot.data ?? const [];
          if (foods.isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(
                child: Text('还没有最近常吃，先搜索或创建一个食物', style: AppTextStyles.caption),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('最近常吃', style: AppTextStyles.section),
              const SizedBox(height: 8),
              Flexible(child: _FoodChoiceList(items: foods)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(String query) {
    if (_searching) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return SizedBox(
        height: 210,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: AppButtonStyles.outline,
                onPressed: () {
                  Navigator.of(context).pop(_EstimateFoodRequest(query));
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('搜索该食物热量'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                style: AppButtonStyles.quiet,
                onPressed: () {
                  Navigator.of(context).pop(_CreateFoodRequest(query));
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('手动创建新食物'),
              ),
            ],
          ),
        ),
      );
    }

    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('搜索结果', style: AppTextStyles.section),
          const SizedBox(height: 8),
          Flexible(child: _FoodChoiceList(items: _results)),
        ],
      ),
    );
  }
}

class _FoodChoiceList extends StatelessWidget {
  final List<FoodCalorieCatalogItem> items;

  const _FoodChoiceList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: item.source == 'custom'
                ? AppColors.lavenderSoft
                : AppColors.greenSoft,
            child: Icon(
              item.source == 'custom'
                  ? Icons.person_outline
                  : Icons.restaurant_menu,
              color: item.source == 'custom'
                  ? AppColors.lavender
                  : AppColors.green,
            ),
          ),
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.listTitle,
          ),
          subtitle: Text(
            '${item.caloriesPer100g.toStringAsFixed(0)} kcal/100g',
            style: AppTextStyles.listSubtitle,
          ),
          trailing: TextButton(
            style: AppButtonStyles.quiet,
            onPressed: () {
              Navigator.of(context).pop(_FoodDraft.fromCatalogItem(item));
            },
            child: const Text('添加'),
          ),
          onTap: () {
            Navigator.of(context).pop(_FoodDraft.fromCatalogItem(item));
          },
        );
      },
    );
  }
}

class _AddFoodPlaceholder extends StatelessWidget {
  final VoidCallback onTap;

  const _AddFoodPlaceholder({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline, color: AppColors.faint),
            const SizedBox(width: 10),
            Text(
              '添加食物',
              style: AppTextStyles.bodyMuted.copyWith(
                color: AppColors.faint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimateFoodDialog extends StatefulWidget {
  final String foodName;
  final HealthProvider provider;

  const _EstimateFoodDialog({required this.foodName, required this.provider});

  @override
  State<_EstimateFoodDialog> createState() => _EstimateFoodDialogState();
}

class _EstimateFoodDialogState extends State<_EstimateFoodDialog> {
  final TextEditingController _gramsCtrl = TextEditingController(text: '100');
  final TextEditingController _manualCaloriesCtrl = TextEditingController();
  FoodCalorieCatalogItem? _estimated;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEstimate();
  }

  @override
  void dispose() {
    _gramsCtrl.dispose();
    _manualCaloriesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEstimate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await widget.provider.estimateFood(widget.foodName);
      if (!mounted) return;
      setState(() {
        _estimated = item;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyActionError(error, action: 'AI 查询食物热量');
      });
    }
  }

  Future<void> _confirm() async {
    final item = _estimated;
    if (item == null) return;
    final grams = double.tryParse(_gramsCtrl.text) ?? 100;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.provider.createCustomFood(
        name: item.name,
        caloriesPer100g: item.caloriesPer100g,
        carbsPer100g: item.carbsPer100g,
        proteinPer100g: item.proteinPer100g,
        fatPer100g: item.fatPer100g,
        giValue: item.giValue,
        servingOptions: item.servingOptions,
        source: item.source ?? 'zhipu',
        isAiGenerated: true,
        confidence: item.confidence,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _FoodDraft.fromCatalogItem(
          saved.copyNutritionFrom(item),
          grams: grams <= 0 ? 100 : grams,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyActionError(error, action: '保存 AI 食物');
      });
    }
  }

  Future<void> _createManually() async {
    final calories = double.tryParse(_manualCaloriesCtrl.text);
    if (calories == null || calories <= 0) {
      setState(() => _error = 'AI 暂时不可用，请先填写每100g热量');
      return;
    }
    final grams = double.tryParse(_gramsCtrl.text) ?? 100;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.provider.createCustomFood(
        name: widget.foodName,
        caloriesPer100g: calories,
        servingOptions: const {'100克': 100},
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(_FoodDraft.fromCatalogItem(saved, grams: grams <= 0 ? 100 : grams));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyActionError(error, action: '创建自定义食物');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _estimated;
    return AlertDialog(
      title: const Text('AI 查询食物热量'),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          : item == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error ?? '没有查到这个食物',
                  style: AppTextStyles.caption.copyWith(
                    color: _error == null ? AppColors.muted : AppColors.red,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: AppButtonStyles.outline,
                    onPressed: _saving ? null : _loadEstimate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试 AI 查询'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _manualCaloriesCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '每100g热量',
                    suffixText: 'kcal',
                  ),
                ),
                TextField(
                  controller: _gramsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '当前克重',
                    suffixText: 'g',
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.section),
                const SizedBox(height: 6),
                Text(
                  '🔥 ${item.caloriesPer100g.toStringAsFixed(0)} kcal / 100g',
                  style: AppTextStyles.listSubtitle,
                ),
                if (item.servingOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.servingOptions.entries.take(5).map((entry) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${entry.key} · ${entry.value.toStringAsFixed(0)}g',
                        ),
                        onPressed: () {
                          _gramsCtrl.text = entry.value.toStringAsFixed(0);
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _gramsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '当前克重',
                    suffixText: 'g',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTextStyles.caption.copyWith(color: AppColors.red),
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (!_loading && item != null)
          ElevatedButton(
            style: AppButtonStyles.primary,
            onPressed: _saving ? null : _confirm,
            child: Text(_saving ? '保存中' : '确认添加'),
          ),
        if (!_loading && item == null)
          ElevatedButton(
            style: AppButtonStyles.primary,
            onPressed: _saving ? null : _createManually,
            child: Text(_saving ? '保存中' : '手动添加'),
          ),
      ],
    );
  }
}

class _CreateCustomFoodDialog extends StatefulWidget {
  final String initialName;
  final Future<FoodCalorieCatalogItem> Function(String name, double calories)
  onCreate;

  const _CreateCustomFoodDialog({
    required this.initialName,
    required this.onCreate,
  });

  @override
  State<_CreateCustomFoodDialog> createState() =>
      _CreateCustomFoodDialogState();
}

class _CreateCustomFoodDialogState extends State<_CreateCustomFoodDialog> {
  late final TextEditingController _nameCtrl;
  final TextEditingController _caloriesCtrl = TextEditingController();
  final TextEditingController _gramsCtrl = TextEditingController(text: '100');
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _caloriesCtrl.dispose();
    _gramsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final calories = double.tryParse(_caloriesCtrl.text);
    if (name.isEmpty || calories == null || calories <= 0) {
      setState(() => _error = '请填写食物名称和有效热量');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = await widget.onCreate(name, calories);
      final grams = double.tryParse(_gramsCtrl.text) ?? 100;
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(_FoodDraft.fromCatalogItem(item, grams: grams <= 0 ? 100 : grams));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyActionError(error, action: '创建自定义食物');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建自定义食物'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '食物名称'),
          ),
          TextField(
            controller: _caloriesCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '每100g热量',
              suffixText: 'kcal',
            ),
          ),
          TextField(
            controller: _gramsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '当前克重',
              suffixText: 'g',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: AppColors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: AppButtonStyles.primary,
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '创建中' : '确认'),
        ),
      ],
    );
  }
}

class _FoodRecognitionBottomSheet extends StatefulWidget {
  final List<MealRecognitionItem> items;
  final String imageUrl;
  final HealthProvider provider;

  const _FoodRecognitionBottomSheet({
    required this.items,
    required this.imageUrl,
    required this.provider,
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
  bool _estimating = false;
  String? _estimateError;

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
                  '${item.confidence > 0 ? ' · 匹配 ${(item.confidence * 100).toStringAsFixed(0)}%' : ''}'
                  '${_isLowConfidence(item) ? ' · 可能不准' : ''}',
                  style: AppTextStyles.listSubtitle.copyWith(
                    color: _isLowConfidence(item)
                        ? AppColors.yellow
                        : AppColors.muted,
                  ),
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
    final shouldOfferEstimate =
        _selected.catalogId == null || _isLowConfidence(_selected);

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
        if (shouldOfferEstimate) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: AppButtonStyles.outline,
            onPressed: _estimating ? null : _estimateSelectedFood,
            icon: _estimating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _estimating
                  ? '正在估算'
                  : _estimateError == null
                  ? 'AI 估算热量/份量'
                  : '重试 AI 估算',
            ),
          ),
          if (_estimateError != null) ...[
            const SizedBox(height: 6),
            Text(
              _estimateError!,
              style: AppTextStyles.caption.copyWith(color: AppColors.red),
            ),
          ],
        ],
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

  bool _isLowConfidence(MealRecognitionItem item) {
    return item.confidence > 0 && item.confidence < 0.72;
  }

  Future<void> _estimateSelectedFood() async {
    final name = (_selected.foodNameConfirmed ?? _selected.foodNameRaw).trim();
    if (name.isEmpty) return;
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final estimated = await widget.provider.estimateFood(name);
      if (!mounted) return;
      final next = _selected.copyFromEstimate(estimated);
      setState(() {
        _selected = next;
        _selectedWeight = _initialWeight(next);
        _selectedServing = _initialServing(next);
        _estimating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _estimating = false;
        _estimateError = friendlyActionError(error, action: 'AI 估算食物');
      });
    }
  }
}

class _FoodDraftCard extends StatefulWidget {
  final _FoodDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _FoodDraftCard({
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_FoodDraftCard> createState() => _FoodDraftCardState();
}

class _FoodDraftCardState extends State<_FoodDraftCard> {
  late final FocusNode _gramsFocusNode;

  _FoodDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _gramsFocusNode = FocusNode();
    _gramsFocusNode.addListener(_selectAllGramsOnFocus);
  }

  @override
  void dispose() {
    _gramsFocusNode
      ..removeListener(_selectAllGramsOnFocus)
      ..dispose();
    super.dispose();
  }

  void _selectAllGramsOnFocus() {
    if (!_gramsFocusNode.hasFocus) return;
    draft.gramsCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: draft.gramsCtrl.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = draft.confirmedName.trim().isEmpty
        ? '未命名食物'
        : draft.confirmedName.trim();
    final caloriesText = draft.rawCalories.toStringAsFixed(0);
    final finalCalories = draft.finalCalories.toStringAsFixed(0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.listTitle.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (draft.isAiGenerated) ...[
                          const SizedBox(width: 6),
                          const _AiEstimateBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🔥 $caloriesText kcal / 100g',
                      style: AppTextStyles.listSubtitle,
                    ),
                    if (draft.isFromRecognition &&
                        draft.rawName.trim().isNotEmpty &&
                        draft.rawName.trim() != name) ...[
                      const SizedBox(height: 3),
                      Text('识别：${draft.rawName}', style: AppTextStyles.tiny),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 86,
                child: TextField(
                  controller: draft.gramsCtrl,
                  focusNode: _gramsFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  decoration: _gramsDecoration(),
                  onChanged: (_) {
                    draft.servingUnit = 'g';
                    draft.manualFinalCalories = false;
                    draft.syncFinalCalories();
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  '= $finalCalories kcal',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.listMeta,
                ),
              ),
              const SizedBox(width: 4),
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

  InputDecoration _gramsDecoration() {
    return InputDecoration(
      suffixText: 'g',
      filled: true,
      fillColor: AppColors.background,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary, width: 1),
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
  MealRecognitionItem? sourceItem;
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
    this.sourceItem,
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
      sourceItem: item,
    );
  }

  factory _FoodDraft.fromCatalogItem(
    FoodCalorieCatalogItem item, {
    double grams = 100,
  }) {
    final servingOptions = item.servingOptions.isEmpty
        ? const {'100克': 100.0}
        : item.servingOptions;
    return _FoodDraft(
      rawName: item.name,
      confirmedName: item.name,
      rawCalories: item.caloriesPer100g,
      carbsPer100g: item.carbsPer100g,
      proteinPer100g: item.proteinPer100g,
      fatPer100g: item.fatPer100g,
      giValue: item.giValue,
      isAiGenerated: item.isAiGenerated,
      grams: grams,
      servingUnit: 'g',
      servingOptions: servingOptions,
      catalogMatches: const [],
      imageUrl: null,
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
  bool get isEmpty =>
      confirmedName.trim().isEmpty && rawCalories <= 0 && grams <= 0;
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
