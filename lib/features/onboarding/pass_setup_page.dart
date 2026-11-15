// 锁定口令引导页（2026-11-15 P0 默认安全基线）：身份建立后的一次性步骤——
// 开启锁定保护（口令包裹私钥，Argon2id）或明确知晓风险后跳过。
// 跳过的后果：私钥本机明文存放、退出/切后台不上锁，拿到手机的人可直接阅读全部日记。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/app_session.dart';
import '../../features/theme/tokens.dart';

class PassSetupPage extends ConsumerStatefulWidget {
  const PassSetupPage({super.key});

  @override
  ConsumerState<PassSetupPage> createState() => _PassSetupPageState();
}

class _PassSetupPageState extends ConsumerState<PassSetupPage> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    if (_busy) return;
    final p = _pass.text.trim();
    if (p.length < 6) {
      setState(() => _error = '口令至少 6 位');
      return;
    }
    if (p != _again.text.trim()) {
      setState(() => _error = '两次输入不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(appSessionProvider.notifier)
          .setLockEnabled(true, passcode: p);
    } catch (e) {
      if (mounted) setState(() => _error = '开启失败：$e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _done();
  }

  void _done() => ref.read(appSessionProvider.notifier).finishPassSetup();

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final already = ref.watch(appSessionProvider).lockEnabled;

    return Scaffold(
      backgroundColor: Tokens.bg(b),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          children: [
            Text('最后一步 · 锁定保护',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                    color: Tokens.label(b))),
            const SizedBox(height: 14),
            Text(
              '开启后：退出应用或超时会自动上锁，需口令或面容 ID 解锁；'
              '私钥改为口令加密存放，数据零重加密。',
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: Tokens.label2(b)),
            ),
            const SizedBox(height: 10),
            Text(
              '跳过的风险：私钥在本机明文存放，退出/切后台不上锁——'
              '拿到这台手机的人可以直接阅读你的全部日记。',
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: Tokens.red(b)),
            ),
            const SizedBox(height: 28),
            if (already) ...[
              Text('本机已开启锁定保护，无需重复设置。',
                  style: TextStyle(
                      fontSize: 14, height: 1.6, color: Tokens.label(b))),
              const SizedBox(height: 24),
              _primary(b, '继续', _done),
            ] else ...[
              TextField(
                controller: _pass,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(color: Tokens.label(b)),
                decoration: InputDecoration(
                  labelText: '口令（≥6 位）',
                  labelStyle: TextStyle(color: Tokens.label3(b)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Tokens.sep(b))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Tokens.blue(b))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _again,
                obscureText: true,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _enable(),
                style: TextStyle(color: Tokens.label(b)),
                decoration: InputDecoration(
                  labelText: '再输入一次',
                  labelStyle: TextStyle(color: Tokens.label3(b)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Tokens.sep(b))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Tokens.blue(b))),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        TextStyle(fontSize: 12, color: Tokens.red(b))),
              ],
              const SizedBox(height: 24),
              _primary(b, _busy ? '开启中…' : '开启锁定保护', _enable),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _done,
                  child: Text('暂不设置，直接进入',
                      style: TextStyle(
                          fontSize: 13, color: Tokens.label3(b))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primary(Brightness b, String label, VoidCallback onTap) => Material(
        color: Tokens.blue(b),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ),
      );
}
