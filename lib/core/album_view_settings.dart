import 'package:flutter/material.dart';

import '../models/media.dart';
import 'design/colors.dart';
import 'design/radius.dart';
import 'design/text_styles.dart';
import 'formatters.dart';

enum AlbumSort { takenAt, addedAt }

enum AlbumGroup { year, month, day, flat }

class AlbumViewSettings {
  static final ValueNotifier<AlbumSort> sort =
      ValueNotifier<AlbumSort>(AlbumSort.takenAt);
  static final ValueNotifier<AlbumGroup> group =
      ValueNotifier<AlbumGroup>(AlbumGroup.day);

  static String sortLabel(AlbumSort value) {
    return switch (value) {
      AlbumSort.takenAt => '按拍摄时间排序',
      AlbumSort.addedAt => '按添加时间排序',
    };
  }

  static String groupLabel(AlbumGroup value) {
    return switch (value) {
      AlbumGroup.year => '按年份分开',
      AlbumGroup.month => '按月份分开',
      AlbumGroup.day => '按日期分开',
      AlbumGroup.flat => '连续平铺',
    };
  }
}

class AlbumSection {
  final String? header;
  final List<Media> items;

  const AlbumSection({required this.header, required this.items});
}

DateTime albumSortDate(Media media, AlbumSort sort) {
  return sort == AlbumSort.takenAt ? media.takenAt : media.createdAt;
}

List<Media> sortAlbumMedia(List<Media> source, AlbumSort sort) {
  final items = List<Media>.of(source);
  items.sort((a, b) {
    final byDate = albumSortDate(b, sort).compareTo(albumSortDate(a, sort));
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  });
  return items;
}

List<AlbumSection> albumSections(
  List<Media> source,
  AlbumSort sort,
  AlbumGroup group,
) {
  final items = sortAlbumMedia(source, sort);
  if (group == AlbumGroup.flat) {
    return [AlbumSection(header: null, items: items)];
  }

  final grouped = <String, List<Media>>{};
  final headers = <String, String>{};
  for (final media in items) {
    final date = albumSortDate(media, sort).toLocal();
    final key = switch (group) {
      AlbumGroup.year => '${date.year}',
      AlbumGroup.month =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}',
      AlbumGroup.day => dayKey(date),
      AlbumGroup.flat => '',
    };
    headers.putIfAbsent(key, () {
      return switch (group) {
        AlbumGroup.year => '${date.year}年',
        AlbumGroup.month => '${date.year}年${date.month}月',
        AlbumGroup.day => formatDayHeader(date),
        AlbumGroup.flat => '',
      };
    });
    grouped.putIfAbsent(key, () => []).add(media);
  }
  return [
    for (final entry in grouped.entries)
      AlbumSection(header: headers[entry.key], items: entry.value),
  ];
}

Future<void> showAlbumViewMenu(BuildContext context) async {
  final selected = await showModalBottomSheet<String>(
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
              const _MenuHandle(),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: Text('排序与视图', style: AppText.titleMedium),
              ),
              _choiceTile(
                context,
                label: AlbumViewSettings.sortLabel(AlbumSort.takenAt),
                selected: AlbumViewSettings.sort.value == AlbumSort.takenAt,
                action: 'taken',
              ),
              _choiceTile(
                context,
                label: AlbumViewSettings.sortLabel(AlbumSort.addedAt),
                selected: AlbumViewSettings.sort.value == AlbumSort.addedAt,
                action: 'added',
              ),
              const Divider(height: 20),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: const Text('视图', style: AppText.body),
                subtitle: Text(
                  AlbumViewSettings.groupLabel(AlbumViewSettings.group.value),
                  style: AppText.caption,
                ),
                trailing: Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textTertiary),
                onTap: () => Navigator.pop(context, 'view'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (selected == 'taken') {
    AlbumViewSettings.sort.value = AlbumSort.takenAt;
  } else if (selected == 'added') {
    AlbumViewSettings.sort.value = AlbumSort.addedAt;
  } else if (selected == 'view' && context.mounted) {
    final group = await showModalBottomSheet<AlbumGroup>(
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
                const _MenuHandle(),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Text('视图', style: AppText.titleMedium),
                ),
                for (final group in AlbumGroup.values)
                  _choiceTile(
                    context,
                    label: AlbumViewSettings.groupLabel(group),
                    selected: AlbumViewSettings.group.value == group,
                    action: group,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (group != null) AlbumViewSettings.group.value = group;
  }
}

Widget _choiceTile(
  BuildContext context, {
  required String label,
  required bool selected,
  required Object action,
}) {
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    title: Text(label, style: AppText.body),
    trailing: selected
        ? Icon(Icons.check, size: 20, color: AppColors.primary)
        : const SizedBox(width: 20),
    onTap: () => Navigator.pop(context, action),
  );
}

class _MenuHandle extends StatelessWidget {
  const _MenuHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppColors.borderLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
