import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/video_orientation.dart';

/// 视频层：按「修正后的」比例做 contain 摆放。
///
/// 动态照片/视频画面被拉伸的根因是视频层自己没有框：`VideoPlayer` 内部的
/// `Texture` 永远铺满父级给的盒子，而父级的比例和视频比例常常不一致
/// （`AspectRatio` 一旦收到紧约束就放弃自己的比例，直接撑满 —— 看起来就是
/// 拉伸）。这里不再依赖隐式布局：先用 [correctedVideoAspectRatio] 拿到真正
/// 该显示的比例（video_player 自己会用 RotatedBox 把 90/270 度的纹理转回来，
/// 所以旋转过的源要用 `aspectRatio` 的倒数），再用
/// [containSizeForAspectRatio] 算出「不放大、不溢出」的尺寸，最后交给
/// [SizedBox] 给纹理一个精确的紧约束。
///
/// 效果：动态照片的静态图是 4:3、视频是带旋转的 9:16 时，视频层按 9:16 居中
/// 摆放，既不会被拉成 4:3，也不会为了填满而溢出容器。
class CorrectedVideoLayer extends StatelessWidget {
  const CorrectedVideoLayer({
    super.key,
    required this.value,
    required this.child,
  });

  /// 视频层实际占用的那块矩形（测试用来断言比例）。
  static const Key frameKey = Key('corrected-video-frame');

  /// 视频控制器的当前值：比例与旋转修正都从它来。
  final VideoPlayerValue value;

  /// 真正贴纹理的控件（正常就是 [VideoPlayer]）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = correctedVideoAspectRatio(value);
        final size = containSizeForAspectRatio(
          Size(constraints.maxWidth, constraints.maxHeight),
          ratio,
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
}
