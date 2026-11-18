import 'package:flutter/material.dart';

import '../core/formatters.dart';
import 'app_chrome_glass_bar.dart';
import 'app_glass_tone.dart';

/// 吸顶日期条（满宽条带）的玻璃圆角：**0**。
///
/// 圆角按各自形态取：只有 footer 是胶囊（高度/2），日期条是一条横贯整屏的
/// **直边条**，四角不留圆弧——留了的话吸顶条两端会露出后面的照片、留下侧边
/// 空隙，条带看上去像一枚飘着的胶囊。数取自 [kAppChromePinnedRadius]（三处
/// 吸顶条同一档），其余参数与 footer 一字不差（见 [AppChromeGlassBar]）。
const double kPinnedDateHeaderRadius = kAppChromePinnedRadius;

/// 日期分组头：固定高度 + 左右内边距 + **自动墨色的文字**。
///
/// 相册详情页与朋友圈相册都用 38 高（几何见
/// `features/album/album_timeline_layout.dart`，两页同一份）；朋友圈动态流
/// 的日期头高 36，也套这一层。
///
/// **两种形态，一套文字**：
/// - [pinned] 为真（吸顶的那一份）：底衬是**与底部 footer 完全相同的玻璃**
///   （[AppChromeGlassBar]，折射可见度 45% 的 scrim + 最低档模糊），照片从它
///   下面滚过去时条带自己就是一块玻璃。之前这里是「主题色浅渐变 + 一层兜底
///   模糊」，用户要求统一成 footer 的材质；
/// - [pinned] 为假（内容流里的普通日期头）：**完全透明**——没有渐变、没有
///   模糊、没有玻璃。底衬就是它背后的页面背景（渐变或用户挑的背景图），
///   日期文字直接压在上面。
///
/// **文字为什么用自动墨色**：非吸顶那一份背后是任意背景（可以是纯白照片，
/// 也可以是深色背景图），固定一种颜色在两端总有一头读不出来。这里与 footer
/// 用同一个机制：`appGlassToneBuilder` 按 [AppBackdropSample] 采样到的背景
/// 亮度挑墨色（[appGlassToneInk]），采样不可用时按主题回退。文字的字号/行高/
/// 字重与 footer 标签同源（[appChromeLabelStyle]），三处条带与 footer 是同一档
/// 小字。对比度实测（四种极端背景 × 明暗 ≥ 4.5:1）见
/// test/pinned_chrome_bar_test.dart 与 test/glass_tone_test.dart。
class DateHeader extends StatelessWidget {
  final String text;
  final double? height;
  final EdgeInsetsGeometry padding;

  /// 右侧附加控件（比如多选态的「全选」按钮）。
  final Widget? trailing;

  /// 右侧数量（相册分组里那一组的张数）；与 [text] 同一套文字。
  final int? count;

  /// 是不是吸顶的那一份：true = footer 同款玻璃，false = 纯透明。
  final bool pinned;

  /// 玻璃圆角（只在 [pinned] 时有效）。
  final double radius;

  const DateHeader({
    super.key,
    required this.text,
    this.height = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
    this.count,
    this.pinned = false,
    this.radius = kPinnedDateHeaderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // 吸顶那一份：墨色由玻璃条按背景采样挑好传进来（与 footer 同一个机制）。
    if (pinned) {
      // 直边条 + 不要描边/内高光 + 固定底衬（[AppChromeGlassBar.pinned]）：
      // 吸顶条贴在页面左右边缘，只留玻璃本体，且合成色不随背后滚过的照片漂。
      // footer 的装饰与材质仍走默认构造，两处互不影响。
      return AppChromeGlassBar.pinned(
        radius: radius,
        builder: (_, ink) => _content(ink),
      );
    }
    // 非吸顶那一份：没有玻璃、没有渐变、没有 scrim，文字直接压在最外层背景
    // 上，所以墨色按**背景本身**的亮度挑（[appGlassToneInkBare]）。
    return appGlassBareToneBuilder((context, ink) => _content(ink));
  }

  Widget _content(Color ink) {
    // 文字/数量：footer 未激活那一套（字号 10.5 / w500 / 行高 1.1），
    // 颜色是按背景亮度挑好的墨色，外加同色极轻描边——和 footer 标签一样。
    final style = appChromeLabelStyle(ink, shadows: appChromeHalo(ink));
    return SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(formatCount(count!), style: style),
            ],
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
