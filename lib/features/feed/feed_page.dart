// 时光流：天卡片（8 色光晕）+ 段首缩进条目 + 长文折叠 + 九宫格 + 评论懒加载。
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart'
    show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/dates.dart';
import '../../features/compose/compose_page.dart';
import '../../features/shell/home_shell.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/net_avatar.dart';
import 'comments_view.dart';

/// 平滑加权轮询（SWRR，nginx 同款）：每轮取当前权重最大者，选中者扣减总权重、
/// 全员叠加自身权重——等权时输出为平滑轮询序列（每项都轮到，不饿死）。
/// 卡片颜色分配：调用方先洗牌颜色池（每次刷新顺序都不同），SWRR 保证全覆盖轮转。
/// [rounds] 默认 pool.length；加权验证时传总权重可观察到完整周期。
List<T> swrrOrder<T>(List<T> pool, {List<int>? weights, int? rounds}) {
  final w = weights ?? List<int>.filled(pool.length, 1);
  assert(w.length == pool.length);
  final cw = List<int>.filled(pool.length, 0);
  final total = w.fold(0, (a, b) => a + b);
  final out = <T>[];
  for (var round = 0; round < (rounds ?? pool.length); round++) {
    var best = 0;
    for (var i = 1; i < pool.length; i++) {
      if (cw[i] > cw[best]) best = i;
    }
    out.add(pool[best]);
    cw[best] -= total;
    for (var i = 0; i < pool.length; i++) {
      cw[i] += w[i];
    }
  }
  return out;
}

/// 天卡头像预取清单（晨 15 方案 D）：每个天卡显示首条目的头像 → 收集去重。
List<String> dayAvatarUrls(List<MapEntry<String, List<DiaryEntry>>> groups) {
  final out = <String>[];
  for (final g in groups) {
    final u = g.value.first.avatarUrl;
    if (u != null && u.isNotEmpty && !out.contains(u)) out.add(u);
  }
  return out;
}

class FeedPage extends ConsumerStatefulWidget {
  final void Function(HomeTab t) switchTab;

  const FeedPage({super.key, required this.switchTab});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  String _kw = '';
  final _precached = <String>{}; // 已预取的头像 URL（每次同步 URL 换新，按此去重）

  // 卡片颜色序列 + 评论头像盐（2026-11-16 用户拍板）：启动/每次刷新重掷——
  // 最新卡片不再恒定同色；SWRR 保证每 8 张覆盖全部 8 色（不饿死），洗牌保证
  // 每次序列不同；评论动物头像随盐整体换新。
  final _rng = math.Random();
  late List<int> _glowSeq = _reshuffleGlow();

  List<int> _reshuffleGlow() {
    final pool = List<int>.generate(Tokens.glowAnchors.length, (i) => i)
      ..shuffle(_rng);
    return swrrOrder(pool);
  }

  void _rerandomize() {
    setState(() => _glowSeq = _reshuffleGlow());
    ref.read(avatarSaltProvider.notifier).state = _rng.nextInt(1 << 31);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _kw = '';
        _searchCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);
    final today = Dates.date(DateTime.now());

    // 关键词搜索（01 §7：明文索引端上做）：正文/标签包含即命中（大小写不敏感）
    final kw = _kw.trim().toLowerCase();
    final searching = kw.isNotEmpty;
    final visible = searching
        ? state.entries.where((e) {
            final p = e.payload;
            if (p.text.toLowerCase().contains(kw)) return true;
            for (final t in p.tags) {
              if (t.toLowerCase().contains(kw)) return true;
            }
            return false;
          }).toList()
        : state.entries;

    final groups = groupByDay(visible);
    final hasToday =
        groups.any((g) => g.key == today && g.value.isNotEmpty);

    // 头像预取（晨 15 方案 D，真机反馈头像刷新慢）：同步落库后新 URL 进入本帧——
    // 立即并行预热全部天卡头像（只预热未取过的）。NetAvatar 构建时命中内存缓存
    // → 头像与卡片同帧出现；屏外卡片也不再滚动到才拉取。onError 必传：失败走
    // NetAvatar 占位兜底，不走 FlutterError.reportError（测试环境会判失败）。
    for (final u in dayAvatarUrls(groups)) {
      if (_precached.add(u)) {
        unawaited(precacheImage(NetworkImage(NetAvatar.sized(u, 56)), context,
            onError: (_, _) {}));
      }
    }

    // 高亮：session.highlightDate 传入 → 对应卡片仅日期数字变组色
    final hl = state.highlightDate;
    final hlKey = hl == null ? null : Dates.date(hl);

    return // 浏览器调试：默认 ScrollBehavior 不响应鼠标拖拽，放开后下拉可用
        ScrollConfiguration(
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
        // 弹性物理：顶部过拉露出刷新头（真机 iOS 默认弹性；web/桌面强制开启）
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // 自定义下拉刷新头：拉距控箭头旋转 → 松手转圈「正在刷新…」→「已同步 ✓」
          CupertinoSliverRefreshControl(
            refreshTriggerPullDistance: 90,
            refreshIndicatorExtent: 60,
            onRefresh: _refresh,
            builder: _refreshHeader,
          ),
          SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, headerTopPad(context), 18, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('时光',
                    style: TextStyle(
                        fontSize: 33,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                        color: Tokens.label(b))),
                Row(children: [
                  // 离线队列徽标：云端不可达时本地暂存的条数（手动刷新冲正）
                  if (state.pendingCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Tokens.orange(b).withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${state.pendingCount} 条待同步',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Tokens.orange(b))),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _iconBtn(b, Icons.search_outlined, _toggleSearch),
                  if (state.lockEnabled) ...[
                    const SizedBox(width: 10),
                    _iconBtn(b, Icons.lock_outline,
                        () => ref.read(appSessionProvider.notifier).lock()),
                  ],
                ]),
              ],
            ),
          ),
        ),
        if (_searchOpen)
          SliverToBoxAdapter(child: _searchBar(b)),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (state.syncError != null)
          SliverToBoxAdapter(
            child: _SyncErrorBanner(
                message: state.syncError!, onRetry: _refreshError),
          ),
        if (searching && groups.isEmpty)
          SliverToBoxAdapter(child: _noResult(b)),
        if (!searching && !hasToday)
          SliverToBoxAdapter(child: _todayEmpty(b)),
        SliverList.builder(
          itemCount: groups.length,
          itemBuilder: (context, i) {
            final g = groups[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: GlowDayCard(
                glowIndex: _glowSeq[i % _glowSeq.length] + 1,
                highlighted: g.key == hlKey,
                child: DayCardBody(
                  dateKey: g.key,
                  entries: g.value,
                  glowIndex: _glowSeq[i % _glowSeq.length] + 1,
                ),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
    );
  }

  /// 下拉刷新：增量同步（缓存为空时自动转全量重建）+ 完成提示（同步静默时用户
  /// 无感知，会被误以为没有下拉刷新）。完成/失败后重洗卡片颜色序列（每次刷新
  /// 都不一样，2026-11-16 用户拍板）。
  Future<void> _refresh() async {
    try {
      await ref.read(appSessionProvider.notifier).syncNow();
      if (mounted) ref.read(appSessionProvider.notifier).showToast('已同步 ✓');
    } catch (_) {
      // 失败进 syncError 横幅；指示器自动收回
    } finally {
      if (mounted) _rerandomize();
    }
  }

  /// 横幅「重试」：清错误态 → 重注册 + 重同步（内部吞错，失败重新亮横幅）。
  Future<void> _refreshError() async {
    await ref.read(appSessionProvider.notifier).retrySync();
    if (mounted) _rerandomize();
  }

  /// 下拉刷新头（仿原生）：下拉时箭头随拉距旋转（朝下→朝上），超过触发距离变蓝；
  /// 松手后转圈 + 「正在刷新…」；完成后 ✓ + 「已同步 ✓」随头部收回淡出。
  Widget _refreshHeader(
    BuildContext context,
    RefreshIndicatorMode state,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) {
    final b = Theme.of(context).brightness;
    final t = (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0);
    final appear = (pulledExtent / 48).clamp(0.0, 1.0);

    final Widget content = switch (state) {
      RefreshIndicatorMode.drag || RefreshIndicatorMode.armed => Transform.rotate(
          angle: (1 - t) * math.pi, // 0=朝下 → 1=朝上（松手即刷新）
          child: Icon(
            Icons.arrow_downward,
            size: 20,
            color: state == RefreshIndicatorMode.armed
                ? Tokens.blue(b)
                : Tokens.label2(b),
          ),
        ),
      RefreshIndicatorMode.refresh => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Tokens.blue(b),
                backgroundColor: Tokens.fill(b),
              ),
            ),
            const SizedBox(width: 9),
            Text('正在刷新…',
                style: TextStyle(fontSize: 12.5, color: Tokens.label2(b))),
          ],
        ),
      RefreshIndicatorMode.done => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 16, color: Tokens.green),
            const SizedBox(width: 7),
            Text('已同步 ✓',
                style: TextStyle(fontSize: 12.5, color: Tokens.label2(b))),
          ],
        ),
      _ => const SizedBox.shrink(),
    };

    return Center(
      child: Opacity(
        opacity: appear,
        child: content,
      ),
    );
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

  /// 标题行圆钮（搜索 / 锁定）。
  Widget _iconBtn(Brightness b, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: Tokens.fill(b), shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: Tokens.label(b)),
      ),
    );
  }

  /// 搜索条：实时过滤（正文/标签，大小写不敏感），× 清空。
  Widget _searchBar(Brightness b) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Tokens.card(b),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tokens.sep(b)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: Tokens.label3(b)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: Tokens.label(b)),
                decoration: InputDecoration(
                  hintText: '搜索关键词（正文 / 标签）',
                  hintStyle: TextStyle(
                      fontSize: 13, color: Tokens.label3(b)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 11),
                ),
                onChanged: (v) => setState(() => _kw = v),
              ),
            ),
            if (_kw.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _kw = '');
                },
                child: Icon(Icons.close,
                    size: 16, color: Tokens.label3(b)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _noResult(Brightness b) {
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
      child: Text('没有找到「$_kw」',
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

  const DayCardBody({
    super.key,
    required this.dateKey,
    required this.entries,
    required this.glowIndex,
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

    // 日数字与卡片光晕同色、常显（2026-11-15 用户拍板：日的变色和卡片颜色一致；
    // 覆盖 mockup「常态 label 仅高亮变色」原语义）
    final accent = Tokens.glowAnchors[(glowIndex - 1) % 8].$3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部：头像左上（后端链接，每天一条 → 每天一个）+ 日右上；
        // 年月收在日下（原「月 + 完整日期」两行重复，2026-11-15 用户去掉）
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 4),
          child: Row(
            children: [
              // 天卡头像 56（晨 17 真机反馈「再大点」；接口图像链路不变 §2.7 v3）
              NetAvatar(url: entries.first.avatarUrl, size: 56),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      if (badge != null) ...[
                        badge,
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: accent,
                          fontFeatures: const [],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${d.year}年${d.month}月',
                      style: TextStyle(fontSize: 10, color: Tokens.label3(b))),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                // 同日内条目分隔：若隐若现（分隔线 = sep 再压暗，对齐正文起点）
                if (i > 0)
                  Container(
                    height: .5,
                    margin: const EdgeInsets.only(left: 38, right: 6, bottom: 2),
                    color: Tokens.sep(b).withValues(alpha: .4),
                  ),
                EntryView(
                  entry: entries[i],
                  isFirstOfDay: i == 0,
                  weekday: Dates.weekdayNames[d.weekday - 1],
                ),
              ],
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
    // 刷新后收起评论（晨 17 §4.4）：syncNow 成功自增 dataRev，rev 变化即收起；
    // 失败路径（横幅）不增 rev → 评论不收。
    ref.listen(appSessionProvider.select((s) => s.dataRev), (prev, next) {
      if (prev != next && _commentsOpen && mounted) {
        setState(() => _commentsOpen = false);
      }
    });
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
        padding: const EdgeInsets.symmetric(vertical: 6),
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
          // post-actions（mockup .post-actions space-between）：标签/心情在左，评论按钮在右
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MoodEmoji(moodKey: p.mood),
                      for (final t in tags) TagChip(t, seed: p.text),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 评论徽标（0 条不显示数字）
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
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.68,
                        color: Tokens.label(b)),
                    children: [
                      // 待同步标记（* 指针）：显示层注入，不进载荷
                      ...pendingMark(widget.entry.textPending, b),
                      TextSpan(text: text),
                    ],
                  ),
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
