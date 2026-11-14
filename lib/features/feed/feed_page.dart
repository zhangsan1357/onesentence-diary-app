// 时光流：天卡片（8 色光晕）+ 段首缩进条目 + 长文折叠 + 九宫格 + 评论懒加载。
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/dates.dart';
import '../../features/compose/compose_page.dart';
import '../../features/shell/home_shell.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/common.dart';
import 'comments_view.dart';

class FeedPage extends ConsumerStatefulWidget {
  final void Function(HomeTab t) switchTab;

  const FeedPage({super.key, required this.switchTab});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _scroll = ScrollController();


  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);
    final today = Dates.date(DateTime.now());

    final groups = groupByDay(state.entries);
    final hasToday =
        groups.any((g) => g.key == today && g.value.isNotEmpty);

    // 高亮：session.highlightDate 传入 → 对应卡片仅日期数字变组色
    final hl = state.highlightDate;
    final hlKey = hl == null ? null : Dates.date(hl);

    return RefreshIndicator(
      onRefresh: _refresh,
      // 浏览器调试：默认 ScrollBehavior 不响应鼠标拖拽，放开后下拉可用
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          },
        ),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 64, 18, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('时光',
                    style: TextStyle(
                        fontSize: 33,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                        color: Tokens.label(b))),
                if (state.lockEnabled)
                  GestureDetector(
                    onTap: () =>
                        ref.read(appSessionProvider.notifier).lock(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: Tokens.fill(b), shape: BoxShape.circle),
                      child: Icon(Icons.lock_outline,
                          size: 16, color: Tokens.label(b)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (state.syncError != null)
          SliverToBoxAdapter(
            child: _SyncErrorBanner(
                message: state.syncError!, onRetry: _refreshError),
          ),
        if (!hasToday)
          SliverToBoxAdapter(child: _todayEmpty(b)),
        SliverList.builder(
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final g = groups[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: GlowDayCard(
                glowIndex: i + 1,
                highlighted: g.key == hlKey,
                child: DayCardBody(
                  dateKey: g.key,
                  entries: g.value,
                  glowIndex: i + 1,
                  highlighted: g.key == hlKey,
                ),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      ),
    );
  }

  /// 下拉刷新：增量同步（缓存为空时自动转全量重建）。
  Future<void> _refresh() async {
    try {
      await ref.read(appSessionProvider.notifier).syncNow();
    } catch (_) {
      // 失败进 syncError 横幅；指示器自动收回
    }
  }

  /// 横幅「重试」：清错误态 → 重注册 + 重同步（内部吞错，失败重新亮横幅）。
  Future<void> _refreshError() async {
    await ref.read(appSessionProvider.notifier).retrySync();
  }

  Widget _todayEmpty(Brightness b) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Tokens.card(b),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text('今天还没写点什么',
          style: TextStyle(fontSize: 14, color: Tokens.label2(b))),
    );
  }
}

/// 同步失败横幅：动态口令过期（③）走专用文案 + 重试；其他同步错误显示原始消息。
class _SyncErrorBanner extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;

  const _SyncErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final isPass = message.contains('动态口令');
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Tokens.red(b).withValues(alpha: b == Brightness.light ? .07 : .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tokens.red(b).withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_problem_outlined,
                  size: 16, color: Tokens.red(b)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isPass ? '同步失败 · 口令过期' : '同步失败',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Tokens.red(b)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPass
                ? '请求被服务器拒绝：动态口令无效或已过期。请检查：'
                    '本机系统时间是否准确（误差需在 5 分钟内）；'
                    '是否使用了与注册时相同的密钥。修正后点击「重试」即可，无需重新注册。'
                : message,
            style: TextStyle(
                fontSize: 12, height: 1.5, color: Tokens.label2(b)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => ref
                    .read(appSessionProvider.notifier)
                    .dismissSyncError(),
                child: Text('忽略',
                    style:
                        TextStyle(fontSize: 13, color: Tokens.label2(b))),
              ),
              const SizedBox(width: 4),
              Material(
                color: Tokens.red(b),
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: onRetry,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Text('重试',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DayCardBody extends ConsumerWidget {
  final String dateKey;
  final List<DiaryEntry> entries;
  final int glowIndex;
  final bool highlighted;

  const DayCardBody({
    super.key,
    required this.dateKey,
    required this.entries,
    required this.glowIndex,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);
    final d = Dates.tryParseDate(dateKey)!;
    final hol = state.holidays?.of(d);
    final badge = hol == null
        ? null
        : (hol.type == 'off'
            ? _Badge(b, 'off')
            : (hol.type == 'ban' ? _Badge(b, 'ban') : null));

    // mockup：日期数字常态 label 色，仅高亮（日历跳转/新发布）按组变色
    final accent = highlighted
        ? Tokens.glowAnchors[(glowIndex - 1) % 8].$3
        : Tokens.label(b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: accent,
                    fontFeatures: const [],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${d.month}月',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Tokens.label2(b))),
                      if (badge != null) ...[
                        const SizedBox(width: 5),
                        badge,
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(dateKey,
                      style: TextStyle(
                          fontSize: 10,
                          color: Tokens.label3(b))),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                EntryView(
                  entry: entries[i],
                  isFirstOfDay: i == 0,
                  weekday: Dates.weekdayNames[d.weekday - 1],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final Brightness b;
  final String type;
  const _Badge(this.b, this.type);

  @override
  Widget build(BuildContext context) {
    final off = type == 'off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: off ? Tokens.badgeOffBg(b) : Tokens.badgeBanBg(b),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        off ? '休' : '班',
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: off ? Tokens.red(b) : Tokens.orange(b),
        ),
      ),
    );
  }
}

/// 条目：时间等宽字体行内前缀 + 正文 + 媒体 + 标签 + 脚注（心情/评论徽标）。
/// 星期几只放进当天第一条的首个标签位（继承原版设计）。
class EntryView extends ConsumerStatefulWidget {
  final DiaryEntry entry;
  final bool isFirstOfDay;
  final String weekday;

  const EntryView({
    super.key,
    required this.entry,
    required this.isFirstOfDay,
    required this.weekday,
  });

  @override
  ConsumerState<EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends ConsumerState<EntryView> {
  bool _expanded = false;
  bool _commentsOpen = false;

  static const _foldLines = 6; // mockup: max-height calc(1.68em*6)

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final e = widget.entry;
    final p = e.payload;

    final tags = <String>[
      if (widget.isFirstOfDay) widget.weekday,
      ...p.tags,
    ];

    return GestureDetector(
      // 长按条目 → 编辑（预填正文/心情/标签，保存=整条重新加密替换）
      onLongPress: () =>
          Navigator.of(context).push(ComposeRoute(editEntry: widget.entry)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 正文（时间前缀 + 折叠）
          _body(b, p),
          ImageGrid(images: p.media.where((m) => m.kind == 'image').toList()),
          if (p.media.any((m) => m.kind == 'audio'))
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: WavePill(
                seconds: p.media.firstWhere((m) => m.kind == 'audio').sec ?? 0,
              ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in tags) TagChip(t)],
              ),
            ),
          // 脚注：心情 + 评论徽标（0 条不显示数字）
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                MoodEmoji(moodKey: p.mood),
                const SizedBox(width: 8),
                Material(
                  color: Tokens.fill(b),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () =>
                        setState(() => _commentsOpen = !_commentsOpen),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      child: Row(
                        children: [
                          Icon(Icons.mode_comment_outlined,
                              size: 13, color: Tokens.label2(b)),
                          if (p.comments.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text('${p.comments.length}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Tokens.label(b))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 评论懒加载展开（数据在本地载荷内，点开即渲染）
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _commentsOpen
                ? CommentsView(entry: e)
                : const SizedBox(width: double.infinity),
          ),
        ],
        ),
      ),
    );
  }

  Widget _body(Brightness b, EntryPayload p) {
    final text = p.text;
    return LayoutBuilder(builder: (context, c) {
      // 折叠判定：行数 > 6 显示展开按钮（近似：按字符宽估算，交给 Text.maxLines）
      const style = TextStyle(fontSize: 15, height: 1.68);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: _foldLines,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: c.maxWidth - 12); // 减去时间前缀缩进
      final over = tp.didExceedMaxLines;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.time,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Tokens.label2(b),
              fontFeatures: const [FontFeature.tabularFigures()],
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.68,
                      color: Tokens.label(b)),
                  maxLines: _expanded ? null : _foldLines,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                if (over)
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        _expanded ? '收起' : '展开全文',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Tokens.blue(b)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}
