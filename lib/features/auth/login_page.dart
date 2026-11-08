import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth_api.dart';
import '../../core/account_store.dart';
import '../../core/api_client.dart';
import '../../core/auth_storage.dart';
import '../../core/current_user.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../core/server_config.dart';
import '../../core/server_settings_dialog.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/brand_mark.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoggedIn;

  const LoginPage({super.key, required this.onLoggedIn});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _rememberPassword = true;
  String? _error;
  String _server = ServerConfig.current;
  String _mode = '未连接';
  List<SavedAccount> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _refreshServer();
    _loadAccounts();
  }

  Future<void> _refreshServer() async {
    if (!mounted) return;
    setState(() {
      _server = ServerConfig.current;
      _mode = ServerConfig.notifier.value.isEmpty
          ? '未连接'
          : ServerConfig.notifier.value;
    });
  }

  /// 读取上次登录过的账号，默认填最近一个（含记住的密码）。
  Future<void> _loadAccounts() async {
    final accounts = await AccountStore.load();
    if (!mounted) return;
    setState(() => _accounts = accounts);
    if (_userIdController.text.isEmpty && accounts.isNotEmpty) {
      _applyAccount(accounts.first);
    }
  }

  void _applyAccount(SavedAccount account) {
    _userIdController.text = account.userId;
    _passwordController.text = account.password ?? '';
    setState(() {
      if (account.hasPassword) _rememberPassword = true;
      _error = null;
    });
  }

  Future<void> _openAccountPicker() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<SavedAccount>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.bgSurface,
      builder: (context) => _AccountPickerSheet(accounts: _accounts),
    );
    if (!mounted) return;
    // 面板里可能删掉了账号，关闭后重新读一次。
    final accounts = await AccountStore.load();
    if (!mounted) return;
    setState(() => _accounts = accounts);
    if (selected != null) _applyAccount(selected);
  }

  void _onUserIdChanged(String value) {
    final typed = value.trim();
    if (_passwordController.text.isNotEmpty) return;
    for (final account in _accounts) {
      if (account.userId == typed && account.hasPassword) {
        _passwordController.text = account.password!;
        return;
      }
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await showServerSettings(context);
    await _refreshServer();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final userId = _userIdController.text.trim();
    final password = _passwordController.text;
    if (userId.isEmpty) {
      setState(() => _error = '请输入用户 ID');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthApi.login(userId, password);
      await AuthStorage.save(result.token, result.user);
      // 记住这次登录过的账号；没勾「记住密码」时顺带清掉旧密码。
      await AccountStore.remember(
        result.user,
        password,
        savePassword: _rememberPassword,
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

  void _goRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RegisterPage(onLoggedIn: widget.onLoggedIn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgPage,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _openSettings,
            tooltip: '服务器状态',
            icon: const Icon(Icons.dns_outlined),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: const Alignment(0, 0.55),
            colors: [
              AppColors.primaryLight.withOpacity(0.55),
              AppColors.bgPage,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(size: 74),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '家庭相册',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.6,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('记录生活里的每个瞬间', style: AppText.bodySmall),
                      const SizedBox(height: 36),
                      AppTextField(
                        controller: _userIdController,
                        label: '用户 ID',
                        hint: '例如 mikey',
                        prefixIcon: Icon(Icons.person_outline,
                            size: 20, color: AppColors.textTertiary),
                        suffixIcon: _accounts.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _loading ? null : _openAccountPicker,
                                tooltip: '选择已登录过的账号',
                                icon: Icon(Icons.expand_more,
                                    size: 22, color: AppColors.textTertiary),
                              ),
                        textInputAction: TextInputAction.next,
                        onChanged: _onUserIdChanged,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(20),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9_]'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _passwordController,
                        label: '密码',
                        hint: '输入密码',
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
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _loading ? null : _login(),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberPassword,
                              onChanged: _loading
                                  ? null
                                  : (value) => setState(
                                      () => _rememberPassword = value == true),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _loading
                                ? null
                                : () => setState(() =>
                                    _rememberPassword = !_rememberPassword),
                            child: Text(
                              '记住密码',
                              style: AppText.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_accounts.isNotEmpty)
                            GestureDetector(
                              onTap: _loading ? null : _openAccountPicker,
                              child: Text(
                                '已记录 ${_accounts.length} 个账号',
                                style: AppText.caption.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline,
                                        size: 15, color: AppColors.danger),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: AppText.caption
                                            .copyWith(color: AppColors.danger),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading ? null : _goRegister,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          textStyle: const TextStyle(fontSize: 14),
                        ),
                        child: const Text('没有账号？去注册'),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: InkWell(
                  onTap: _openSettings,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dns_outlined,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$_mode · ${_server.replaceFirst(RegExp(r'^https?://'), '')}',
                            style: AppText.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已登录过的账号列表（QQ 风格的账号下拉）。
class _AccountPickerSheet extends StatefulWidget {
  final List<SavedAccount> accounts;

  const _AccountPickerSheet({required this.accounts});

  @override
  State<_AccountPickerSheet> createState() => _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<_AccountPickerSheet> {
  late final List<SavedAccount> _accounts = List.of(widget.accounts);

  Future<void> _remove(SavedAccount account) async {
    await AccountStore.remove(account.userId);
    if (!mounted) return;
    setState(
        () => _accounts.removeWhere((item) => item.userId == account.userId));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('选择账号', style: AppText.titleMedium),
                ),
                Text('登录过的账号', style: AppText.caption),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                final account = _accounts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.primary,
                    child: Text(
                      account.initial,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  title: Text(
                    account.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    account.hasPassword
                        ? '@${account.userId} · 已记住密码'
                        : '@${account.userId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                  trailing: IconButton(
                    onPressed: () => _remove(account),
                    tooltip: '删除账号记录',
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textTertiary,
                  ),
                  onTap: () => Navigator.of(context).pop(account),
                );
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.edit_outlined,
                size: 20, color: AppColors.textSecondary),
            title: Text(
              '使用其他账号',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
