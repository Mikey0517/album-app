import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth_api.dart';
import '../../core/account_store.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/current_user.dart';
import '../../core/design/colors.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback onLoggedIn;

  const RegisterPage({super.key, required this.onLoggedIn});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _userIdController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _userIdController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final userId = _userIdController.text.trim();
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    final userIdPattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
    if (!userIdPattern.hasMatch(userId)) {
      setState(() => _error = '用户 ID 需为 3~20 位字母、数字或下划线');
      return;
    }
    if (nickname.isEmpty || nickname.length > 20) {
      setState(() => _error = '昵称不能为空且不超过 20 个字符');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = '密码至少 4 位');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthApi.register(userId, nickname, password);
      await AuthStorage.save(result.token, result.user);
      // 注册后把账号记进登录页的下拉列表，密码留到用户自己勾选记住。
      await AccountStore.remember(
        result.user,
        password,
        savePassword: false,
      );
      CurrentUser.notifier.value = result.user;
      if (!mounted) return;
      widget.onLoggedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建账号')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '加入这个家',
                style: AppText.titleLarge.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text('取一个家人都认得的名字', style: AppText.bodySmall),
              const SizedBox(height: 28),
              AppTextField(
                controller: _userIdController,
                label: '用户 ID',
                hint: '3~20 位字母、数字或下划线',
                prefixIcon: Icon(Icons.alternate_email,
                    size: 20, color: AppColors.textTertiary),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(20),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _nicknameController,
                label: '昵称',
                hint: '家人看到的名字',
                prefixIcon: Icon(Icons.face_outlined,
                    size: 20, color: AppColors.textTertiary),
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(20)],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _passwordController,
                label: '密码',
                hint: '至少 4 位',
                helper: '密码至少 4 位，请和家人共享服务器时妥善保管',
                obscureText: _obscure,
                prefixIcon: Icon(Icons.lock_outline,
                    size: 20, color: AppColors.textTertiary),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _confirmController,
                label: '确认密码',
                hint: '再输入一次',
                prefixIcon: Icon(Icons.lock_reset_outlined,
                    size: 20, color: AppColors.textTertiary),
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loading ? null : _register(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: 15, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style:
                            AppText.caption.copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              AppButton(
                label: '注册并登录',
                loading: _loading,
                onPressed: _register,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
