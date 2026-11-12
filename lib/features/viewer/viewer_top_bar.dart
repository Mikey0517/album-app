import 'package:flutter/material.dart';

import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';

class ViewerTopBar extends StatelessWidget {
  final Media media;
  final VoidCallback onClose;
  final VoidCallback onDownload;
  final VoidCallback? onDetails;

  const ViewerTopBar({
    super.key,
    required this.media,
    required this.onClose,
    required this.onDownload,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                iconSize: 24,
                color: Colors.white,
                tooltip: '关闭',
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    formatTakenAt(media.takenAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: Colors.white),
                  ),
                ),
              ),
              if (onDetails != null)
                IconButton(
                  onPressed: onDetails,
                  iconSize: 22,
                  color: Colors.white,
                  tooltip: '详情',
                  icon: const Icon(Icons.info_outline),
                ),
              IconButton(
                onPressed: onDownload,
                iconSize: 22,
                color: Colors.white,
                tooltip: '保存到相册',
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
