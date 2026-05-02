import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_messages.dart';
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

class _ProfileSettingsPageState extends State<ProfileSettingsPage>
    with WidgetsBindingObserver {
  final _nameCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _gender = '男';
  DateTime _birthDate = DateTime(DateTime.now().year - 23, 1, 1);
  bool _loaded = false;
  bool _savingProfile = false;
  NotificationPermissionStatus _notificationStatus =
      NotificationPermissionStatus.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotificationStatus();
    });
  }

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
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    final provider = context.read<HealthProvider>();
    final repo = provider.repository;
    final height = double.tryParse(_heightCtrl.text) ?? provider.height;
    final weight = double.tryParse(_weightCtrl.text) ?? provider.weight;
    try {
      await repo.saveProfile(
        displayName: _nameCtrl.text,
        gender: _gender,
        height: height,
        birthDate: _formatDate(_birthDate),
      );
      if ((weight - provider.weight).abs() >= 0.1) {
        await repo.addBodyMetric(weight: weight, recordTime: DateTime.now());
      }
      await provider.refreshProfileData();
      if (!mounted) return;
      _showSnack('个人信息已保存');
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '保存个人信息'));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
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
    try {
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
      await _refreshNotificationStatus();
      if (!mounted) return;
      _showSnack('提醒已添加');
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '添加提醒'));
    }
  }

  Future<void> _toggleReminder(String id, bool enabled) async {
    final provider = context.read<HealthProvider>();
    try {
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
      await _refreshNotificationStatus();
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '更新提醒'));
    }
  }

  Future<void> _deleteReminder(String id) async {
    final provider = context.read<HealthProvider>();
    try {
      await ReminderService.instance.cancelReminder(id);
      await provider.repository.deleteReminder(id);
      await provider.loadDashboardData();
      if (!mounted) return;
      _showSnack('提醒已删除');
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyActionError(error, action: '删除提醒'));
    }
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

  Future<void> _refreshNotificationStatus() async {
    final status = await ReminderService.instance.checkPermissionStatus();
    if (!mounted) return;
    setState(() => _notificationStatus = status);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await ReminderService.instance.requestPermissions();
    if (!mounted) return;
    setState(() => _notificationStatus = status);
    _showSnack(_notificationSnackText(status));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationStatus();
    }
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
                    onPressed: _savingProfile ? null : _saveProfile,
                    child: Text(_savingProfile ? '保存中' : '保存'),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _notificationStatus == NotificationPermissionStatus.allowed
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: _notificationStatus ==
                                NotificationPermissionStatus.allowed
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '系统通知：${_notificationStatusLabel()}',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    _notificationStatus == NotificationPermissionStatus.denied
                        ? '开启通知权限'
                        : '检查通知权限',
                  ),
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

  String _notificationStatusLabel() {
    switch (_notificationStatus) {
      case NotificationPermissionStatus.allowed:
        return '已开启';
      case NotificationPermissionStatus.denied:
        return '已关闭';
      case NotificationPermissionStatus.unknown:
        return '未知';
    }
  }

  String _notificationSnackText(NotificationPermissionStatus status) {
    switch (status) {
      case NotificationPermissionStatus.allowed:
        return '系统通知已开启';
      case NotificationPermissionStatus.denied:
        return '系统通知未开启，请在系统设置中允许通知';
      case NotificationPermissionStatus.unknown:
        return '已检查通知权限，当前平台无法读取精确状态';
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.primaryDark),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final timeLabel = _formatReminderTime(context, reminder['time_of_day']);
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
                  timeLabel,
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

  String _formatReminderTime(BuildContext context, Object? value) {
    final parts = '$value'.split(':');
    if (parts.length < 2) return '$value';
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return '$value';
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }
}
