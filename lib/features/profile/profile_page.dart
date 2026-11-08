import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/auth_api.dart';
import '../../api/storage_api.dart';
import '../../core/api_client.dart';
import '../../core/app_theme_controller.dart';
import '../../core/auth_storage.dart';
import '../../core/cache_service.dart';
import '../../core/current_user.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../core/server_config.dart';
import '../../core/server_settings_dialog.dart';
import '../../models/app_user.dart';
import '../../models/storage_info.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../update/force_update_dialog.dart';
import '../update/ios_update_service.dart';
import '../update/update_service.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onLogout;

  const ProfilePage({super.key, required this.onLogout});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  AppUser? _user;
  bool _loading = true;
  bool _loggingOut = false;
  bool _checkingUpdate = false;
  CacheUsage? _cache;
  bool _cacheLoading = true;
  bool _cacheClearing = false;
  String _version = '';
  String _server = ServerConfig.current;
  String _serverMode = '';
  String? _error;
  StorageInfo? _storage;
  bool _storageLoading = true;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _server = ServerConfig.current;
    _serverMode = ServerConfig.notifier.value;
    ServerConfig.notifier.addListener(_onServerChanged);
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadVersion();
    _loadStorage();
    _loadCache();
  }

  @override
  void dispose() {
    ServerConfig.notifier.removeListener(_onServerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台重新统计，避免显示的是浏览图片之前的旧数字。
    if (state == AppLifecycleState.resumed) unawaited(_loadCache());
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCache() async {
    final usage = await CacheService.measure();
    if (!mounted) return;
    setState(() {
      _cache = usage;
      _cacheLoading = false;
    });
  }

  Widget _cacheRow(String label, int bytes, {bool emphasized = false}) {
    final style = emphasized
        ? AppText.body.copyWith(fontWeight: FontWeight.w600)
        : AppText.bodySmall;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(
          formatBytes(bytes),
          style: emphasized ? style : AppText.bodySmall,
        ),
      ],
    );
  }

  Future<void> _clearCache() async {
    if (_cacheClearing) return;
    // 先统计一次，弹窗里的数字才是最新的。
    await _loadCache();
    if (!mounted) return;
    final usage = _cache;
    if (usage == null || usage.isEmpty) {
      _snack('没有可清理的缓存');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存？', style: AppText.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cacheRow('图片缓存', usage.imageBytes),
            const SizedBox(height: 10),
            _cacheRow('临时文件', usage.tempBytes),
            const Divider(height: 22),
            _cacheRow('合计可清理', usage.clearableBytes, emphasized: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cacheClearing = true);
    final result = await CacheService.clear();
    if (!mounted) return;
    setState(() => _cacheClearing = false);
    await _loadCache();
    if (!mounted) return;
    _snack('已清理 ${formatBytes(result.freedBytes)}');
  }

  void _onServerChanged() {
    if (!mounted) return;
    setState(() {
      _server = ServerConfig.current;
      _serverMode = ServerConfig.notifier.value;
    });
    unawaited(_loadStorage(silent: _storage != null));
  }

  Future<void> _openServerSettings() async {
    await showServerSettings(context);
    if (!mounted) return;
    _onServerChanged();
  }

  Future<void> _openThemePicker() async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Text('主题', style: AppText.titleMedium),
                ),
                for (final mode in AppThemeMode.values)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(AppThemeController.label(mode),
                        style: AppText.body),
                    trailing: AppThemeController.mode.value == mode
                        ? Icon(Icons.check, size: 20, color: AppColors.primary)
                        : const SizedBox(width: 20),
                    onTap: () => Navigator.pop(context, mode),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await AppThemeController.setMode(selected);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // 拿不到版本号只影响展示，不影响页面使用。
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = CurrentUser.notifier.value ?? await AuthApi.me();
      if (!mounted) return;
      CurrentUser.notifier.value = user;
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorText(e);
      });
    }
  }

  Future<void> _loadStorage({bool silent = false}) async {
    final hasData = _storage != null;
    if (mounted) {
      setState(() {
        if (!silent || !hasData) _storageLoading = true;
        _storageError = null;
      });
    }
    try {
      final storage = await StorageApi.fetch();
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _storageLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storageLoading = false;
        if (!hasData) _storageError = ApiClient.errorText(e);
      });
    }
  }

  Future<void> _editNickname() async {
    final user = _user;
    if (user == null) return;
    final controller = TextEditingController(text: user.nickname);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty || value.length > 20) {
              setState(() => error = '昵称不能为空且不超过 20 个字符');
              return;
            }
            Navigator.of(context).pop(value);
          }

          return AlertDialog(
            title: const Text('修改昵称', style: AppText.titleMedium),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: '家人怎么称呼你',
                errorText: error,
                counterText: '',
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('取消'),
              ),
              TextButton(onPressed: submit, child: const Text('保存')),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
    if (result == null || !mounted || result == user.nickname) return;
    try {
      final updated = await AuthApi.updateNickname(result);
      await AuthStorage.saveUser(updated);
      CurrentUser.notifier.value = updated;
      if (!mounted) return;
      setState(() => _user = updated);
      _snack('昵称已更新');
    } catch (e) {
      if (!mounted) return;
      _snack(ApiClient.errorText(e));
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      if (Platform.isIOS) {
        final iosRelease = await IosUpdateService.check();
        if (!mounted) return;
        if (iosRelease != null) {
          await _showIosUpdateDialog(iosRelease);
        } else {
          _snack('已是最新版本');
        }
        return;
      }
      final release = await UpdateService.check();
      if (!mounted) return;
      if (release != null) {
        await showForceUpdateDialog(context, release);
      } else {
        // UpdateService.check 会吞掉网络错误；再用 ping 区分"最新"与"网络异常"。
        final baseUrl = ServerConfig.current;
        final pingError = await ApiClient.ping(baseUrl);
        if (!mounted) return;
        if (pingError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('网络异常：$pingError')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已是最新版本'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：${ApiClient.errorText(e)}')),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// iPad 上不能自装 IPA：发现新版本后跳浏览器（TestFlight / 下载页）。
  Future<void> _showIosUpdateDialog(IosReleaseInfo release) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          release.versionName.isEmpty
              ? '发现新版本'
              : '发现新版本 ${release.versionName}',
          style: AppText.titleMedium,
        ),
        content: const Text(
          'iPad 上需要通过 App Store / TestFlight 更新，点「去更新」会用浏览器打开下载页。',
          style: AppText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去更新'),
          ),
        ],
      ),
    );
    if (open != true) return;
    final uri = Uri.tryParse(release.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthApi.logout();
    } catch (_) {
      // 网络失败也要清掉本地登录态。
    }
    await AuthStorage.clear();
    CurrentUser.notifier.value = null;
    if (!mounted) return;
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: _buildBody(),
    );
  }

  Widget _buildStorageCard() {
    final storage = _storage;
    if (_storageLoading) {
      return AppCard(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Icon(Icons.storage_outlined,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('正在读取服务器存储…', style: AppText.bodySmall),
            ),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }
    if (storage == null) {
      return AppCard(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        onTap: () => _loadStorage(silent: _storage != null),
        child: Row(
          children: [
            Icon(Icons.storage_outlined,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _storageError == null
                    ? '服务器存储读取失败'
                    : '服务器存储读取失败：$_storageError',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall,
              ),
            ),
            Text('重试',
                style: AppText.caption.copyWith(color: AppColors.primary)),
          ],
        ),
      );
    }
    final ratio = storage.usedRatio.clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final color = ratio >= 0.9 ? AppColors.danger : AppColors.primary;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      onTap: () => _loadStorage(silent: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage_outlined,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('服务器存储', style: AppText.body),
              ),
              Text(
                '已用 ${formatBytes(storage.usedBytes)} · $percent%',
                style: AppText.caption.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.borderLight,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '剩余 ${formatBytes(storage.freeBytes)}',
                style: AppText.bodySmall,
              ),
              const Spacer(),
              Text(
                '总容量 ${formatBytes(storage.totalBytes)}',
                style: AppText.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingView(message: '正在读取账号信息');
    }
    if (_error != null || _user == null) {
      return EmptyState(
        icon: Icons.person_off_outlined,
        title: '账号信息加载失败',
        subtitle: _error ?? '请重新登录',
        action: FilledButton(
          onPressed: _load,
          child: const Text('重试'),
        ),
      );
    }
    final user = _user!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _editNickname,
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      user.initial,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('@${user.userId}', style: AppText.caption),
                      ],
                    ),
                  ),
                  Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          _buildStorageCard(),
          AppCard(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  onTap: _openServerSettings,
                  leading: Icon(
                    Icons.dns_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                  title: const Text('服务器状态', style: AppText.body),
                  subtitle: Text(
                    '${_serverMode.isEmpty ? '未连接' : _serverMode} · $_server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ),
                Divider(color: AppColors.divider, height: 1),
                ValueListenableBuilder<AppThemeMode>(
                  valueListenable: AppThemeController.mode,
                  builder: (context, mode, child) {
                    return ListTile(
                      onTap: _openThemePicker,
                      leading: Icon(
                        Icons.brightness_6_outlined,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      title: const Text('主题', style: AppText.body),
                      subtitle: Text(
                        AppThemeController.label(mode),
                        style: AppText.caption,
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                    );
                  },
                ),
                Divider(color: AppColors.divider, height: 1),
                ListTile(
                  onTap: _cacheClearing ? null : _clearCache,
                  leading: Icon(
                    Icons.cleaning_services_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                  title: const Text('缓存', style: AppText.body),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_cacheClearing)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        Text(
                          _cacheLoading
                              ? ''
                              : formatBytes(_cache?.clearableBytes ?? 0),
                          style: AppText.caption,
                        ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                Divider(color: AppColors.divider, height: 1),
                ListTile(
                  onTap: _checkUpdate,
                  leading: Icon(
                    Icons.system_update_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                  title: const Text('检查更新', style: AppText.body),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'v${_version.isEmpty ? '—' : _version}',
                        style: AppText.caption,
                      ),
                      const SizedBox(width: 2),
                      if (_checkingUpdate)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        Icon(
                          Icons.chevron_right,
                          color: AppColors.textTertiary,
                          size: 18,
                        ),
                    ],
                  ),
                ),
                Divider(color: AppColors.divider, height: 1),
                ListTile(
                  onTap: _loggingOut ? null : _logout,
                  leading: Icon(
                    Icons.logout_outlined,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    '退出登录',
                    style: AppText.body.copyWith(color: AppColors.danger),
                  ),
                  trailing: _loggingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
