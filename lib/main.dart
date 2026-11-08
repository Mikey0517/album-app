import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api/auth_api.dart';
import 'core/api_client.dart';
import 'core/app_theme_controller.dart';
import 'core/cache_service.dart';
import 'core/auth_storage.dart';
import 'core/current_user.dart';
import 'core/design/colors.dart';
import 'core/design/text_styles.dart';
import 'core/design/theme.dart';
import 'core/network_monitor.dart';
import 'core/server_config.dart';
import 'core/upload_manager.dart';
import 'core/video_orientation.dart';
import 'widgets/brand_mark.dart';
import 'widgets/upload_status_overlay.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'features/update/changelog_dialog.dart';
import 'features/update/force_update_dialog.dart';
import 'features/update/update_service.dart';
import 'features/update/version_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // 不使用 Android Photo Picker：它会为携带位置信息的照片生成脱敏副本，
  // 可能把小米 Motion Photo 的内嵌视频一并丢掉。传统系统选择器返回原始文件。
  await lockAppPortrait();
  await ServerConfig.init();
  await AppThemeController.init();
  ApiClient.install();
  // 读回上次没传完的队列：登录态确认后自动续传。
  await UploadManager.instance.restore();
  runApp(const AlbumApp());
}

class AlbumApp extends StatefulWidget {
  const AlbumApp({super.key});

  @override
  State<AlbumApp> createState() => _AlbumAppState();
}

class _AlbumAppState extends State<AlbumApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool? _loggedIn;
  bool _readyForResumeCheck = false;
  Future<bool>? _updateCheckFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppThemeController.mode.addListener(_onThemeChanged);
    ApiClient.onUnauthorized = _handleUnauthorized;
    // 更新/更新日志对话框需要 Navigator 已经挂载，因此等第一帧结束后再启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppThemeController.mode.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted && AppThemeController.mode.value == AppThemeMode.system) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uploads = UploadManager.instance;
    if (state == AppLifecycleState.resumed) {
      // 锁屏/切后台期间被系统掐断的上传，回到前台后继续，而不是报失败。
      uploads.setAppActive(true);
      uploads.onAppResumed();
      // 首次启动由 _bootstrap 负责；后台返回时再自动检查一次。
      if (!_readyForResumeCheck || !mounted) return;
      unawaited(_onResumed());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      uploads.setAppActive(false);
    }
  }

  Future<void> _onResumed() async {
    await NetworkMonitor.refresh();
    await _runUpdateCheck();
  }

  /// 启动和后台恢复共用同一次检查，避免重复弹窗。
  Future<bool> _runUpdateCheck() {
    final existing = _updateCheckFuture;
    if (existing != null) return existing;
    final future = _doUpdateCheck();
    _updateCheckFuture = future;
    future.whenComplete(() {
      if (identical(_updateCheckFuture, future)) {
        _updateCheckFuture = null;
      }
    });
    return future;
  }

  Future<bool> _doUpdateCheck() async {
    try {
      final release = await UpdateService.check();
      if (release == null || !mounted) return false;
      final context = _navigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      // 对话框不可关闭，正常情况下会一直停留到用户安装新版本。
      await showForceUpdateDialog(context, release);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    // 后台整理磁盘：按预算裁剪图片缓存、清掉过期临时文件。
    unawaited(CacheService.trimIfNeeded());

    // 每次冷启动重新探测：用户可能在家里/外面切换了网络。
    await ServerConfig.init();
    await ServerConfig.detectActive();
    await NetworkMonitor.start();
    // 网络恢复后自动补传失败的网络类任务。
    NetworkMonitor.onAvailable = UploadManager.instance.onNetworkRestored;
    if (!mounted) return;
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      await _checkLogin();
      _readyForResumeCheck = true;
      return;
    }

    // 1. 强制更新。检测失败（断网/404/超时）UpdateService 内部已静默返回 null。
    if (await _runUpdateCheck()) {
      return;
    }

    // 2. 新版本首次运行的更新日志。必须在对话框关闭后才 mark。
    try {
      if (await VersionTracker.isFirstRunOfCurrentVersion()) {
        final info = await PackageInfo.fromPlatform();
        if (mounted && navigatorContext.mounted) {
          await showChangelogDialog(navigatorContext, info.version);
        }
        await VersionTracker.markCurrentVersionRun();
      }
    } catch (_) {
      // 更新日志失败同样不阻塞启动。
    }

    // 3. 登录态恢复。
    await _checkLogin();
    _readyForResumeCheck = true;
  }

  Future<void> _checkLogin() async {
    final token = await AuthStorage.getToken();
    if (token == null) {
      if (mounted) setState(() => _loggedIn = false);
      return;
    }
    try {
      final user = await AuthApi.me();
      await AuthStorage.saveUser(user);
      CurrentUser.notifier.value = user;
      // 登录态有效，继续上次没传完的上传。
      UploadManager.instance.resumeRestored();
      if (mounted) setState(() => _loggedIn = true);
    } catch (_) {
      await AuthStorage.clear();
      CurrentUser.notifier.value = null;
      if (mounted) setState(() => _loggedIn = false);
    }
  }

  Future<void> _handleUnauthorized() async {
    if (!mounted) return;
    CurrentUser.notifier.value = null;
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (mounted) setState(() => _loggedIn = false);
  }

  void _handleLoggedIn() {
    if (!mounted) return;
    setState(() => _loggedIn = true);
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    UploadManager.instance.resumeRestored();
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clear();
    CurrentUser.notifier.value = null;
    if (!mounted) return;
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppThemeController.isDark();
    AppColors.setDark(dark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '家庭相册',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(dark: dark),
      builder: (context, child) => UploadStatusOverlay(
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _loggedIn == null
            ? const _BootView(key: ValueKey('boot'))
            : _loggedIn!
                ? HomePage(
                    key: const ValueKey('home'),
                    onLogout: _handleLogout,
                  )
                : LoginPage(
                    key: const ValueKey('login'),
                    onLoggedIn: _handleLoggedIn,
                  ),
      ),
    );
  }
}

class _BootView extends StatelessWidget {
  const _BootView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BootBackdrop(),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: Transform.scale(
                      scale: 0.94 + 0.06 * value,
                      child: child,
                    ),
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 88),
                  const SizedBox(height: 24),
                  Text(
                    '家庭相册',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('记录生活里的每个瞬间', style: AppText.bodySmall),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '正在准备…',
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BootBackdrop extends StatelessWidget {
  const _BootBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -140,
            right: -110,
            child: _SoftOrb(
              size: 360,
              color: const Color(0xFFDDE4FF).withOpacity(0.9),
            ),
          ),
          Positioned(
            bottom: -170,
            left: -130,
            child: _SoftOrb(
              size: 380,
              color: const Color(0xFFFFE8DE).withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
          stops: const [0.2, 1],
        ),
      ),
    );
  }
}
