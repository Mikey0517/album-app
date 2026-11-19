import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'upload_status_overlay.dart';

/// 把整棵路由树的安全区「钉住」：系统栏隐藏/出现不再让主界面重排。
///
/// **问题（实测）**：全屏浏览页进来时把系统 UI 切成 immersiveSticky
/// （media_viewer_page.dart:82），退出时在 dispose 里切回 edgeToEdge
/// （同文件 89 行）。系统栏一藏一露，平台上报的 viewPadding/padding 就在
/// 「有安全区 ↔ 0」之间来回跳，主界面上凡是读 MediaQuery 的地方都跟着重排：
///
/// - 底部悬浮胶囊的底部间距是 `bottomGap + viewPaddingOf(context).bottom`
///   （app_bottom_tab_bar.dart:211-221）。390×844、底部安全区 48 的屏上量到
///   胶囊外框 top 从 736 跳到 784、再跳回 736 —— 一次 48px 的下落和回升，
///   就是「返回后主界面抖一下」；
/// - 吸顶条 / SafeArea 同样按 top 安全区上下挪。
///
/// 跳的时机还正好在最难看的点上：dispose（= edgeToEdge 恢复）要等返回动画
/// 结束那一帧才跑（实测：220ms 反向动画的第 15 帧，≈224ms），此时浏览页已经
/// 消失、主界面整屏可见，再跳 48px。所以「把恢复推迟到 pop 之后」并不够——
/// 恢复本来就发生在 pop 之后，跳是因为**布局依赖了会跳的那几个数**。
///
/// **做法**：这一层把 **viewPadding** 换成「窗口尺寸没变时见过的最大值」，
/// padding 仍按平台的算式算：padding = 钉住的 viewPadding − 当前 viewInsets。
///
/// - 系统栏藏起来只是变小 → 不采纳，布局一动不动；
/// - 系统栏回来时值与钉住的相等 → MediaQueryData 逐字段相等，依赖方一行都
///   不重建（不是「重建但结果一样」）；
/// - 窗口尺寸（旋转 / 分屏 / 折叠屏展开）变了 → 安全区是真的换了，重新取当前值；
/// - 键盘弹起（viewInsets 变大、viewPadding 不变）→ padding 跟着归零，编辑页
///   与底部弹窗的行为一个字都不变。
///
/// viewInsets 本身原样透传：键盘的插入距离必须实时跟着输入框走。
/// systemGestureInsets 同理不动。
///
/// 全域一层，位置在 [MaterialApp.builder]（见 [appChromeBuilder]）：放进某
/// 个页面里就只管那一页，push 进来的相册详情页照样会跳。
class StableViewInsets extends StatefulWidget {
  final Widget child;

  const StableViewInsets({super.key, required this.child});

  @override
  State<StableViewInsets> createState() => _StableViewInsetsState();
}

class _StableViewInsetsState extends State<StableViewInsets> {
  /// 上一次采纳安全区时的窗口尺寸：尺寸一变就说明不是「系统栏藏了」，
  /// 而是屏幕本身换了（旋转/分屏），安全区必须重新取。
  Size? _size;

  /// 钉住的 **viewPadding**（= 系统栏/刘海占掉的那块）。只钉这一个，不用
  /// padding：键盘弹起时平台只把 padding 压到 0，viewPadding 不变
  /// （FlutterView.padding 的定义就是 viewPadding 扣掉 viewInsets），
  /// 钉 viewPadding 就不会把键盘的插入距离一起钉死。
  EdgeInsets _viewPadding = EdgeInsets.zero;

  static EdgeInsets _hold(EdgeInsets held, EdgeInsets incoming) =>
      EdgeInsets.fromLTRB(
        math.max(held.left, incoming.left),
        math.max(held.top, incoming.top),
        math.max(held.right, incoming.right),
        math.max(held.bottom, incoming.bottom),
      );

  /// 与平台同一个算式：padding = viewPadding − viewInsets（逐边、不小于 0）。
  static EdgeInsets _paddingFrom(
    EdgeInsets viewPadding,
    EdgeInsets viewInsets,
  ) =>
      EdgeInsets.fromLTRB(
        math.max(0, viewPadding.left - viewInsets.left),
        math.max(0, viewPadding.top - viewInsets.top),
        math.max(0, viewPadding.right - viewInsets.right),
        math.max(0, viewPadding.bottom - viewInsets.bottom),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size != _size) {
      _size = media.size;
      _viewPadding = media.viewPadding;
    } else {
      _viewPadding = _hold(_viewPadding, media.viewPadding);
    }
    // 结构恒定（永远插这一层 MediaQuery），只在数值真变时才通知依赖方：
    // MediaQuery 的比较是 MediaQueryData 全字段相等，钉住的值一字不差，
    // 子树因此一次都不重建。
    return MediaQuery(
      data: media.copyWith(
        padding: _paddingFrom(_viewPadding, media.viewInsets),
        viewPadding: _viewPadding,
      ),
      child: widget.child,
    );
  }
}

/// [MaterialApp.builder] 那一层：稳定安全区 + 上传状态浮层。
///
/// main.dart 用它装 App，test/viewer_return_stability_test.dart 用同一个函数
/// 装被测的主界面——生产里加了一层、测试里忘了加的情况因此不会发生。
Widget Function(BuildContext, Widget?) appChromeBuilder(
  GlobalKey<NavigatorState> navigatorKey,
) {
  return (context, child) => StableViewInsets(
        child: UploadStatusOverlay(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
      );
}
