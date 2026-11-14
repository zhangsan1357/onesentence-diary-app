// 入口：主题（跟随系统 + 手动三档）+ 会话初始化 + 身份门（生成/登录/补注册名）+ 生命周期自动上锁。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session/app_session.dart';
import 'features/me/dialogs.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/shell/home_shell.dart';
import 'features/theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: DiaryApp()));
}

class DiaryApp extends ConsumerStatefulWidget {
  const DiaryApp({super.key});

  @override
  ConsumerState<DiaryApp> createState() => _DiaryAppState();
}

class _DiaryAppState extends ConsumerState<DiaryApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appSessionProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台即锁（锁定保护关闭或 autoLockMin=0 时不锁）
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final s = ref.read(appSessionProvider);
      if (s.unlocked && !s.demo && s.lockEnabled && s.autoLockMin > 0) {
        ref.read(appSessionProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appSessionProvider);
    return MaterialApp(
      title: '一句话日记',
      debugShowCheckedModeBanner: false,
      theme: Tokens.theme(Brightness.light),
      darkTheme: Tokens.theme(Brightness.dark),
      themeMode: switch (s.theme) {
        ThemeSetting.auto => ThemeMode.system,
        ThemeSetting.light => ThemeMode.light,
        ThemeSetting.dark => ThemeMode.dark,
      },
      home: _home(s),
    );
  }

  /// 路由门：首次启动 → ①生成身份；存量身份缺注册名（已解锁）→ 补设引导；
  /// 其余 → 主界面（锁定遮罩由 HomeShell 内部处理）。
  Widget _home(AppState s) {
    if (s.needsOnboarding) {
      return OnboardingPage(
        mode: OnboardingMode.create,
        onCreate: (secret, name) async {
          final n = ref.read(appSessionProvider.notifier);
          await n.createIdentity(secret, name);
          // 极少见的「开了锁定开关但未生成身份」：创建后补口令包裹，保持锁定语义
          if (!mounted) return;
          if (ref.read(appSessionProvider).lockEnabled) {
            final pass = await showSetPasscodeDialog(context);
            if (pass != null) {
              await n.setLockEnabled(true, passcode: pass);
            }
          }
        },
        onLogin: (name, secret) =>
            ref.read(appSessionProvider.notifier).loginIdentity(name, secret),
      );
    }
    if (s.needsName && s.unlocked) {
      return OnboardingPage(
        mode: OnboardingMode.nameOnly,
        onSetName: (name) =>
            ref.read(appSessionProvider.notifier).setName(name),
      );
    }
    return const HomeShell();
  }
}
