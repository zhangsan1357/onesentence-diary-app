// 锁屏：全屏模糊覆盖 + Face ID 按钮（真机 local_auth）+ 口令回退。
// （首次身份创建走 OnboardingPage 门控，锁屏只负责已初始化会话的解锁。）
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/session/app_session.dart';
import '../../core/util/errors.dart';
import '../../features/shell/home_shell.dart';
import '../../features/theme/tokens.dart';

class LockOverlay extends ConsumerStatefulWidget {
  final VoidCallback onCompose;
  final void Function(HomeTab) switchTab;

  const LockOverlay({
    super.key,
    required this.onCompose,
    required this.switchTab,
  });

  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<LockOverlay> {
  final _pass = TextEditingController();
  bool _showPassField = false;
  bool _busy = false;
  bool _prompted = false; // 自动唤起面容只触发一次
  String? _error;
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    // 已开启面容解锁：锁屏出现即自动弹出系统 Face ID（识别通过 → 钥匙串取私钥
    // 直接解锁，无需口令；未开启面容解锁时识别通过仍回退口令——旧语义）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_prompted &&
          ref.read(appSessionProvider).bioUnlock &&
          !ref.read(appSessionProvider).demo) {
        _prompted = true;
        _faceUnlock();
      }
    });
  }

  @override
  void dispose() {
    _pass.dispose();
    _autoLockTimer?.cancel();
    super.dispose();
  }

  Future<void> _faceUnlock() async {
    final state = ref.read(appSessionProvider);
    if (state.demo) {
      // 演示模式：模拟识别延迟
      setState(() => _busy = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('欢迎回来 👋');
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: '用于解锁你的加密日记',
        biometricOnly: true,
      );
      if (!mounted) return;
      if (!ok) return;
      if (state.bioUnlock) {
        // 全量面容解锁：私钥自生物识别保护的钥匙串直取
        await ref.read(appSessionProvider.notifier).unlockBiometric();
        if (!mounted) return;
        _toast('欢迎回来 👋');
        _scheduleAutoLock();
        return;
      }
      setState(() => _showPassField = true);
    } catch (_) {
      // 钥匙串无存档（未启用/生物特征集变更失效）或解锁链路失败 → 回退口令
      if (!mounted) return;
      setState(() {
        _showPassField = true;
        _error = '面容解锁未就绪，请使用口令解锁';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithPass() async {
    if (_pass.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(appSessionProvider.notifier).unlock(_pass.text);
      // §5.11 解锁收敛后 locked=false 早于联网尾段完成 → 锁屏可能已提前
      // 卸载（locked=false 即隐藏），此处必须 mounted 守卫（E2E T3 实测崩溃）
      if (!mounted) return;
      _pass.clear();
      _toast('欢迎回来 👋');
      _scheduleAutoLock();
    } catch (e) {
      // 错误提示统一友好映射（晨 19 §5.11）：口令错误/本机无身份/其余异常
      // 均给中文文案，不透原始异常
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleAutoLock() {
    // 自动上锁（1/5 分钟）由生命周期暂停触发；此处在解锁成功后启动兜底计时
    _autoLockTimer?.cancel();
    final min = ref.read(appSessionProvider).autoLockMin;
    if (min <= 0) return;
    _autoLockTimer = Timer(Duration(minutes: min), () {
      ref.read(appSessionProvider.notifier).lock();
    });
  }

  void _toast(String msg) {
    ref.read(appSessionProvider.notifier).highlight(DateTime.now());
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: const Color(0x8C06080E),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.face,
                    size: 74, color: Colors.white.withValues(alpha: .9)),
                const SizedBox(height: 6),
                const Text(
                  '日记已锁定',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '内容已端到端加密，密钥仅在本机',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .65), fontSize: 13),
                ),
                const SizedBox(height: 14),
                if (_showPassField) ...[
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _pass,
                      obscureText: true,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入口令解锁',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: .4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: .3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Tokens.blue(Brightness.dark)),
                        ),
                      ),
                      onSubmitted: (_) => _unlockWithPass(),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFFF453A), fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  _unlockBtn(_busy ? '处理中…' : '解锁', _unlockWithPass),
                ] else
                  _unlockBtn(_busy ? '正在识别…' : '面容 ID 解锁', _faceUnlock),
                if (!_showPassField)
                  TextButton(
                    onPressed: () =>
                        setState(() => _showPassField = true),
                    child: Text(
                      '使用口令解锁',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .6),
                          fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unlockBtn(String label, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
