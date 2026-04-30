import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_style.dart';
import '../pages/login_page.dart';
import '../provider/health_provider.dart';
import '../services/reminder_service.dart';
import '../widgets/soft_card.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _nameCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _gender = '男';
  DateTime _birthDate = DateTime(DateTime.now().year - 23, 1, 1);
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final provider = context.read<HealthProvider>();
    _nameCtrl.text = provider.displayName;
    _heightCtrl.text = provider.height.toStringAsFixed(0);
    _weightCtrl.text = provider.weight.toStringAsFixed(1);
    _gender = provider.gender;
    _birthDate = DateTime.tryParse(provider.birthDate) ?? _birthDate;
    _loaded = true;
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _birthDate = picked);
  }

  Future<void> _saveProfile() async {
    final provider = context.read<HealthProvider>();
    final repo = provider.repository;
    final height = double.tryParse(_heightCtrl.text) ?? provider.height;
    final weight = double.tryParse(_weightCtrl.text) ?? provider.weight;
    await repo.saveProfile(
      displayName: _nameCtrl.text,
      gender: _gender,
      height: height,
      birthDate: _formatDate(_birthDate),
    );
    if ((weight - provider.weight).abs() >= 0.1) {
      await repo.addBodyMetric(weight: weight, recordTime: DateTime.now());
    }
    await provider.loadDashboardData();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('个人信息已保存')));
  }

  Future<void> _addReminder() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 20, minute: 30),
    );
    if (time == null) return;
    if (!mounted) return;
    final provider = context.read<HealthProvider>();
    final label = _labelFor(time);
    final row = await provider.repository.addReminder(
      timeOfDay: _formatTime(time),
      label: label,
    );
    await ReminderService.instance.scheduleDailyReminder(
      id: '${row['id']}',
      timeOfDay: '${row['time_of_day']}',
      label: '${row['label']}',
    );
    await provider.loadDashboardData();
  }

  Future<void> _toggleReminder(String id, bool enabled) async {
    final provider = context.read<HealthProvider>();
    await provider.repository.setReminderEnabled(id, enabled);
    if (enabled) {
      final reminder = provider.reminders.firstWhere(
        (item) => '${item['id']}' == id,
      );
      await ReminderService.instance.scheduleDailyReminder(
        id: id,
        timeOfDay: '${reminder['time_of_day']}',
        label: '${reminder['label']}',
      );
    } else {
      await ReminderService.instance.cancelReminder(id);
    }
    await provider.loadDashboardData();
  }

  Future<void> _deleteReminder(String id) async {
    final provider = context.read<HealthProvider>();
    await ReminderService.instance.cancelReminder(id);
    await provider.repository.deleteReminder(id);
    await provider.loadDashboardData();
  }

  Future<void> _signOut() async {
    final provider = context.read<HealthProvider>();
    await provider.repository.signOut();
    provider.resetForSignedOutUser();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HealthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('个人设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            title: '基础信息',
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: _fieldDecoration('显示名称', Icons.badge_outlined),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: _fieldDecoration('性别', Icons.wc_outlined),
                  items: const [
                    DropdownMenuItem(value: '男', child: Text('男')),
                    DropdownMenuItem(value: '女', child: Text('女')),
                    DropdownMenuItem(value: '其他', child: Text('其他')),
                  ],
                  onChanged: (value) =>
                      setState(() => _gender = value ?? _gender),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _heightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('身高 cm', Icons.height),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration(
                    '当前体重 kg',
                    Icons.monitor_weight_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _pickBirthDate,
                  icon: const Icon(Icons.cake_outlined),
                  label: Text('出生日期：${_formatDate(_birthDate)}'),
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
                    onPressed: _saveProfile,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            title: '记录提醒',
            trailing: IconButton(
              tooltip: '添加提醒',
              onPressed: _addReminder,
              icon: const Icon(Icons.add_alarm, color: AppColors.primary),
            ),
            child: Column(
              children: [
                if (provider.reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('还没有提醒时间', style: AppTextStyles.caption),
                  ),
                for (final reminder in provider.reminders)
                  _ReminderRow(
                    reminder: reminder,
                    onChanged: (enabled) =>
                        _toggleReminder('${reminder['id']}', enabled),
                    onDelete: () => _deleteReminder('${reminder['id']}'),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: ReminderService.instance.requestPermissions,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('重新允许系统提醒'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: AppButtonStyles.outline,
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }

  String _labelFor(TimeOfDay time) {
    if (time.hour < 11) return '早餐后记录';
    if (time.hour < 16) return '午餐后记录';
    if (time.hour < 21) return '晚间回看';
    return '睡前记录';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }
}

class _ReminderRow extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  const _ReminderRow({
    required this.reminder,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final enabled =
        reminder['enabled'] == true ||
        '${reminder['enabled']}' == '1' ||
        '${reminder['enabled']}' == 'true';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.alarm, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reminder['time_of_day']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  '${reminder['label'] ?? '记录提醒'}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
