// 主壳：5 槽 tab（中央凸起发布键，微博式）+ 弹层（发布页全屏）+ 锁屏覆盖 + toast。
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/app_session.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_page.dart';
import '../compose/compose_page.dart';
import '../feed/feed_page.dart';
import '../lock/lock_overlay.dart';
import '../me/me_page.dart';
import '../memory/memory_page.dart';

enum HomeTab { feed, cal, memo, me }

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  HomeTab _tab = HomeTab.feed;

  void _switchTab(HomeTab t) => setState(() => _tab = t);

  Future<void> _openCompose() async {
    await Navigator.of(context).push(ComposeRoute());
  }

  Widget _pageFor(HomeTab t) => switch (t) {
        HomeTab.feed => FeedPage(switchTab: _switchTab),
        HomeTab.cal => CalendarPage(switchTab: _switchTab),
        HomeTab.memo => const MemoryPage(),
        HomeTab.me => const MePage(),
      };

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);

    return Scaffold(
      backgroundColor: Tokens.bg(b),
      body: Stack(
        children: [
          // 内容页
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 86),
              child: _pageFor(_tab),
            ),
          ),
          // 底部 tab 栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TabBar(current: _tab, onTap: _switchTab, onFab: _openCompose),
          ),
          // toast
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ToastHost(
                message: state.toast,
                onDismiss: () =>
                    ref.read(appSessionProvider.notifier).clearToast(),
              ),
            ),
          ),
          // 锁屏覆盖（全屏 + 高斯模糊；ready 后才判定，避免初始化闪烁）
          if (state.ready && !state.unlocked)
            Positioned.fill(child: LockOverlay(
              onCompose: _openCompose,
              switchTab: _switchTab,
            )),
        ],
      ),
    );
  }
}

class _TabBar extends ConsumerWidget {
  final HomeTab current;
  final ValueChanged<HomeTab> onTap;
  final VoidCallback onFab;

  const _TabBar({required this.current, required this.onTap, required this.onFab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    Widget item(HomeTab t, IconData icon, String label) {
      final on = current == t;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(t),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 25,
                  color: on ? Tokens.blue(b) : Tokens.label3(b)),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: on ? Tokens.blue(b) : Tokens.label3(b),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 86,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 24),
          decoration: BoxDecoration(
            color: Tokens.bg(b).withValues(alpha: .82),
            border: Border(top: BorderSide(color: Tokens.sep(b), width: .5)),
          ),
          child: Row(
            children: [
              item(HomeTab.feed, Icons.access_time, '时光'),
              item(HomeTab.cal, Icons.calendar_month_outlined, '日历'),
              // 中央发布键：与左右图标同一视觉线（此前 margin-top 20 导致偏下 10px），
              // 直径加大 + 重阴影突出
              SizedBox(
                width: 70,
                child: Center(
                  child: GestureDetector(
                    onTap: onFab,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Tokens.blue(b),
                        boxShadow: [
                          BoxShadow(
                            color: Tokens.blue(b).withValues(alpha: .5),
                            blurRadius: 24,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.edit, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
              item(HomeTab.memo, Icons.history, '回忆'),
              item(HomeTab.me, Icons.account_circle_outlined, '我的'),
            ],
          ),
        ),
      ),
    );
  }
}
