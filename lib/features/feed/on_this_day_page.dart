import 'package:flutter/material.dart';

import '../../api/post_api.dart';
import '../../core/api_client.dart';
import '../../core/design/colors.dart';
import '../../core/design/spacing.dart';
import '../../core/design/text_styles.dart';
import '../../core/formatters.dart';
import '../../models/media.dart';
import '../../models/post.dart';
import '../../widgets/date_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_view.dart';
import '../viewer/media_viewer_page.dart';
import 'post_card.dart';

class OnThisDayPage extends StatefulWidget {
  const OnThisDayPage({super.key});

  @override
  State<OnThisDayPage> createState() => _OnThisDayPageState();
}

class _OnThisDayPageState extends State<OnThisDayPage> {
  final List<Post> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await PostApi.onThisDay();
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
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

  void _openMedia(List<Media> medias, int index) {
    Navigator.of(context).push(
      MediaViewerPage.route(
        items: medias,
        initialIndex: index,
        heroPrefix: 'on_this_day_',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.month}月${now.day}日';
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('那年今日'),
            Text(date, style: AppText.caption),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingView(message: '正在翻找那年今天');
    }
    if (_error != null && _posts.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        action: FilledButton(
          onPressed: _load,
          child: const Text('重新加载'),
        ),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.62,
              child: const EmptyState(
                icon: Icons.history_rounded,
                title: '那年今天没有动态',
                subtitle: '等明年再回来看看',
              ),
            ),
          ],
        ),
      );
    }

    final children = <Widget>[];
    String? lastDate;
    for (final post in _posts) {
      final date = formatDayHeader(post.postedAt);
      if (date != lastDate) {
        lastDate = date;
        children.add(
          DateHeader(
            text: date,
            height: null,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          ),
        );
      }
      children.add(
        PostCard(
          key: ValueKey('on_this_day_${post.id}'),
          post: post,
          onOpenMedia: _openMedia,
          onDeleted: () {
            setState(() => _posts.removeWhere((e) => e.id == post.id));
          },
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: children,
      ),
    );
  }
}
