import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/video_orientation.dart';

/// 视频层：按「显示比例」contain 摆放，动态照片再收进静态图那块矩形里。
///
/// 真机上画面会「撑满 + 拉伸」，这里的三件事缺一件都还会撑满：
///
/// 1. `Texture`（`VideoPlayer` 内部就是它）没有自己的固有尺寸，只会铺满父级
///    给的盒子。盒子比例错了画面就被拉伸，所以必须自己算一个比例正确的盒子
///    （[containSizeForAspectRatio]）。
/// 2. 比例不能自己再「修正」一遍。`VideoPlayerValue.size` 来自
///    `video_player_android` 的 media3 `VideoSize`，**已经是旋转后的显示尺寸**
///    （插件 2.8.4 起删掉了自己那次宽高互换，因为 VideoSize 已经算过旋转），
///    90/270 度的旋转由 `VideoPlayer` 内部的 `RotatedBox` 完成。再按
///    `rotationCorrection` 取倒数，会把盒子转置 90 度：竖屏短片拿到横屏的框，
///    而 `RotatedBox` 又按翻转后的紧约束摆纹理，画面直接被拉宽铺满整个屏宽。
///    `video_player` 官方示例同样直接用 `value.aspectRatio`。
/// 3. 动态照片还要多一层框：[frameAspectRatio]（静态图自身的比例）。视频只能
///    在静态图铺出来的那块矩形里 contain，不能拿整屏当自己的框 —— 否则 9:16
///    的短片在 20:9 的手机上正好占满整个屏宽，播放时画面比静态图还大一圈，
///    看起来仍然是「播放就撑满全屏」。
class CorrectedVideoLayer extends StatelessWidget {
  const CorrectedVideoLayer({
    super.key,
    required this.value,
    required this.child,
    this.frameAspectRatio,
  });

  /// 视频层实际占用的那块矩形（测试用来断言比例）。
  static const Key frameKey = Key('corrected-video-frame');

  /// 视频控制器的当前值：显示尺寸从它来（见 [videoDisplayAspectRatio]）。
  final VideoPlayerValue value;

  /// 真正贴纹理的控件（正常就是 [VideoPlayer]）。
  final Widget child;

  /// 外层框的比例：动态照片传静态图的比例（`Media.width / height`），
  /// 视频就只在静态图那块矩形里做 contain。普通视频/拿不到图片尺寸时为 null，
  /// 直接用整屏当框。
  final double? frameAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final container = Size(constraints.maxWidth, constraints.maxHeight);
        final frame = _frame(container);
        final size = containSizeForAspectRatio(
          frame,
          videoDisplayAspectRatio(value),
        );
        return Center(
          child: SizedBox(
            key: frameKey,
            width: size.width,
            height: size.height,
            child: child,
          ),
        );
      },
    );
  }

  /// 静态图铺出来的那块矩形（和图片层的 `BoxFit.contain` 完全重合）。
  Size _frame(Size container) {
    var photoRatio = frameAspectRatio;
    if (photoRatio == null || !photoRatio.isFinite || photoRatio <= 0) {
      return container;
    }
    // 兜底：静态图的宽高由服务端 probe 出来，偶尔会拿到「旋转前」的存储尺寸。
    // 动态照片的短片和静态图拍的是同一个画面，两者比例绝不会差到接近 90 度；
    // 真差这么多只可能是那份宽高是横竖颠倒的，按屏幕上实际显示的方向翻回来。
    final videoRatio = videoDisplayAspectRatio(value);
    if (videoRatio > 0 &&
        (photoRatio / videoRatio > 2 || videoRatio / photoRatio > 2)) {
      photoRatio = 1 / photoRatio;
    }
    final frame = containSizeForAspectRatio(container, photoRatio);
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        !frame.width.isFinite ||
        !frame.height.isFinite) {
      return container;
    }
    return frame;
  }
}

/// 视频层该用的显示比例。
///
/// `VideoPlayerValue.size` 已经是旋转后的显示尺寸（见 [CorrectedVideoLayer]
/// 的注释），所以直接用它，**不要**再按 [VideoPlayerValue.rotationCorrection]
/// 取倒数：取倒数会让盒子横竖颠倒，画面被塞进一个转置的框里拉伸。
double videoDisplayAspectRatio(VideoPlayerValue value) {
  final ratio = value.aspectRatio;
  return ratio.isFinite && ratio > 0 ? ratio : 1;
}
