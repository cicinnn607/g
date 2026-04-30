import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_style.dart';
import '../main.dart';
import '../provider/health_provider.dart';

class LoginPage extends StatefulWidget {
  final bool supabaseConfigured;

  const LoginPage({super.key, this.supabaseConfigured = true});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  bool _isRegister = false;
  bool _isAgreed = false;
  bool _isLoading = false;

  Future<void> _handleSubmit() async {
    if (!widget.supabaseConfigured) {
      _showSnack('请先用 --dart-define 配置 SUPABASE_URL 和 SUPABASE_ANON_KEY');
      return;
    }
    if (!_isAgreed) {
      _showSnack('先勾选用户协议和隐私政策');
      return;
    }
    final email = _emailCtrl.text.trim();
    final password = _pwdCtrl.text;
    if (email.isEmpty || password.length < 6) {
      _showSnack('邮箱要填好，密码至少 6 位');
      return;
    }

    setState(() => _isLoading = true);
    final provider = context.read<HealthProvider>();
    try {
      if (_isRegister) {
        final signedIn = await provider.repository.signUp(
          email: email,
          password: password,
          displayName: _nameCtrl.text.trim().isEmpty
              ? email.split('@').first
              : _nameCtrl.text.trim(),
        );
        if (!signedIn) {
          _showSnack('注册成功。若项目开启了邮箱确认，请先确认邮件再登录');
          return;
        }
      } else {
        await provider.repository.signIn(email: email, password: password);
      }
      await provider.loadDashboardData();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainTabScreen()),
      );
    } on AuthException catch (error) {
      _showSnack(_friendlyAuthError(error.message));
    } catch (error) {
      _showSnack('$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login')) return '邮箱或密码不太对';
    if (lower.contains('already registered')) return '这个邮箱已经注册过了';
    if (lower.contains('email')) return '邮箱格式或确认状态需要检查一下';
    return message;
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.primaryDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppShadows.soft,
                    ),
                    child: const Icon(
                      Icons.water_drop,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() => _isRegister = !_isRegister),
                    child: Text(_isRegister ? '去登录' : '新用户注册'),
                  ),
                ],
              ),
              const SizedBox(height: 44),
              const Text('稳啦', style: AppTextStyles.hero),
              const SizedBox(height: 12),
              Text(
                _isRegister
                    ? '先建个账号，后面饮食、运动和状态都会跟着你走。'
                    : '把餐后状态、血糖和日常活动放在一起看。',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 36),
              if (!widget.supabaseConfigured) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.yellowSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.yellow.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    '当前还没有 Supabase 配置。运行时请加入 --dart-define=SUPABASE_URL=... 和 --dart-define=SUPABASE_ANON_KEY=...',
                    style: AppTextStyles.body,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (_isRegister) ...[
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: '昵称',
                    icon: Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: '邮箱',
                  icon: Icons.alternate_email,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pwdCtrl,
                obscureText: true,
                onSubmitted: (_) => _handleSubmit(),
                decoration: _inputDecoration(
                  label: '密码',
                  icon: Icons.lock_outline,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _isAgreed,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (value) =>
                        setState(() => _isAgreed = value ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        '我已阅读并同意《用户协议》和《隐私政策》',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: AppButtonStyles.primary,
                  onPressed: _isLoading ? null : _handleSubmit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isRegister ? '注册并进入' : '进入稳啦'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primaryDark),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }
}
