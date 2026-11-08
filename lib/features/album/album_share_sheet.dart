import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/album_api.dart';
import '../../api/user_api.dart';
import '../../core/api_client.dart';
import '../../core/design/colors.dart';
import '../../core/design/radius.dart';
import '../../core/design/text_styles.dart';
import '../../models/album.dart';
import '../../models/album_share.dart';
import '../../models/app_user.dart';

/// 私人相册的分享面板：当前名单（可改权限/移除）+ 按昵称/ID 搜索添加。
Future<void> showAlbumShareSheet(BuildContext context, Album album) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => _AlbumShareSheet(album: album),
  );
}

class _AlbumShareSheet extends StatefulWidget {
  final Album album;

  const _AlbumShareSheet({required this.album});

  @override
  State<_AlbumShareSheet> createState() => _AlbumShareSheetState();
}

class _AlbumShareSheetState extends State<_AlbumShareSheet> {
  final _queryController = TextEditingController();
  List<AlbumShare> _shares = const [];
  List<AppUser> _results = const [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _busyId;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    try {
      final shares = await AlbumApi.shares(widget.album.id);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorText(e);
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final users = await UserApi.search(keyword);
        if (!mounted || _queryController.text.trim() != keyword) return;
        setState(() {
          _results = users
              .where((user) => !_shares.any((s) => s.userId == user.userId))
              .toList(growable: false);
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searching = false;
          _error = ApiClient.errorText(e);
        });
      }
    });
  }

  Future<String?> _pickRole({String current = 'viewer'}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('权限', style: AppText.titleMedium),
              ),
            ),
            for (final role in const ['viewer', 'editor', 'admin'])
              ListTile(
                title: Text(
                  AlbumShare.roleLabelOf(role),
                  style: AppText.body,
                ),
                trailing: role == current
                    ? Icon(Icons.check, size: 20, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, role),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _add(AppUser user) async {
    if (_busyId != null) return;
    final role = await _pickRole();
    if (role == null || !mounted) return;
    setState(() => _busyId = user.userId);
    try {
      final shares =
          await AlbumApi.share(widget.album.id, user.userId, role: role);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _results = _results
            .where((item) => item.userId != user.userId)
            .toList(growable: false);
        _busyId = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = ApiClient.errorText(e);
      });
    }
  }

  Future<void> _changeRole(AlbumShare share) async {
    if (_busyId != null) return;
    final role = await _pickRole(current: share.role);
    if (role == null || role == share.role || !mounted) return;
    setState(() => _busyId = share.userId);
    try {
      final shares = await AlbumApi.updateShareRole(
        widget.album.id,
        share.userId,
        role,
      );
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _busyId = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = ApiClient.errorText(e);
      });
    }
  }

  Future<void> _remove(AlbumShare share) async {
    if (_busyId != null) return;
    setState(() => _busyId = share.userId);
    try {
      final shares = await AlbumApi.unshare(widget.album.id, share.userId);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _busyId = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = ApiClient.errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('分享相册', style: AppText.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          widget.album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _queryController,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索昵称或用户 ID',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  _error!,
                  style: AppText.caption.copyWith(color: AppColors.danger),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (_searching)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        if (_results.isNotEmpty) ...[
                          const _SectionLabel('搜索结果'),
                          for (final user in _results)
                            _UserTile(
                              title: user.nickname.isEmpty
                                  ? user.userId
                                  : user.nickname,
                              subtitle: '@${user.userId}',
                              initial: user.initial,
                              trailing: _busyId == user.userId
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : TextButton(
                                      onPressed: () => _add(user),
                                      child: const Text('分享'),
                                    ),
                            ),
                        ] else if (_queryController.text.trim().isNotEmpty &&
                            !_searching)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                            child: Text('没有找到匹配的用户', style: AppText.caption),
                          ),
                        const _SectionLabel('已分享给'),
                        if (_shares.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                            child: Text('还没有分享给任何人', style: AppText.caption),
                          ),
                        for (final share in _shares)
                          _UserTile(
                            title: share.label,
                            subtitle: '@${share.userId}',
                            initial: share.initial,
                            trailing: _busyId == share.userId
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () => _changeRole(share),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          foregroundColor: AppColors.primary,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          AlbumShare.roleLabelOf(share.role),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _remove(share),
                                        icon: const Icon(Icons.close, size: 18),
                                        tooltip: '取消分享',
                                        color: AppColors.textTertiary,
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(text, style: AppText.sectionLabel),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String initial;
  final Widget trailing;

  const _UserTile({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.primary,
        child:
            Text(initial, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body,
      ),
      subtitle: Text(subtitle, style: AppText.caption),
      trailing: trailing,
    );
  }
}
