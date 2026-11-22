// 首次身份引导（2026-11-14 后端身份模型 v4）：
// create   = ①首次启动 · 生成身份：12 宫格直接输入恢复词（默认），下方可一键随机生成
//            + 派生密钥同屏展示 + 注册名（终身不变，多设备共用）——宫格形态在
//            IdentityWordsGrid 公共组件（§5.17，与更换主密钥弹窗同源）
// login    = ②新设备登录：同一注册名 + 同一份身份凭证（12 词/12 段自定义/派生密钥）→ 校验 → 全量同步
// nameOnly = 存量 keystore 一次性补设注册名（旧版身份接入多设备共享）
// 身份凭证只在本页出现：创建/登录完成后，应用内任何页面不再显示恢复词与派生密钥。
// 页面动作经回调注入（main.dart 接线会话层），自身不依赖存储，可独立 widget 测试。
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/util/errors.dart';
import '../../widgets/identity_words_grid.dart';
import '../theme/tokens.dart';

enum OnboardingMode { create, login, nameOnly }

class OnboardingPage extends StatefulWidget {
  final OnboardingMode mode;
  final Future<void> Function(String wordsOrKey, String userId)? onCreate;
  final Future<void> Function(String userId, String secret)? onLogin;
  final Future<void> Function(String userId)? onSetName;

  const OnboardingPage({
    super.key,
    this.mode = OnboardingMode.create,
    this.onCreate,
    this.onLogin,
    this.onSetName,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late OnboardingMode _mode = widget.mode;
  final _name = TextEditingController();
  final _secret = TextEditingController();
  // ① 12 宫格：形态在 IdentityWordsGrid 公共组件（§5.17，注册/换钥同源）——
  // 拼接短语经 onChanged 维护到 _phrase（校验交会话层 validateImport）。
  String _phrase = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case OnboardingMode.create:
          await widget.onCreate!(_phrase, _name.text);
        case OnboardingMode.login:
          await widget.onLogin!(_name.text, _secret.text);
        case OnboardingMode.nameOnly:
          await widget.onSetName!(_name.text);
      }
      // 成功：会话状态更新 → main.dart 自动切回主界面，无需在此导航
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message?.toString() ?? '输入有误');
    } on ApiException catch (e) {
      setState(() => _error = '服务端：${e.message}');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: Tokens.bg(b),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 44, 18, 32),
          children: [
            Text(
              switch (_mode) {
                OnboardingMode.create => '欢迎使用一句话日记',
                OnboardingMode.login => '新设备登录',
                OnboardingMode.nameOnly => '起一个注册名',
              },
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                  color: Tokens.label(b)),
            ),
            const SizedBox(height: 4),
            Text(
              switch (_mode) {
                OnboardingMode.create => '首次启动 · 生成身份',
                OnboardingMode.login => '同一身份，随处同步',
                OnboardingMode.nameOnly => '本机已有身份密钥 · 一次性设置',
              },
              style: TextStyle(fontSize: 13, color: Tokens.label2(b)),
            ),
            const SizedBox(height: 16),
            ...switch (_mode) {
              OnboardingMode.create => _createBody(b),
              OnboardingMode.login => _loginBody(b),
              OnboardingMode.nameOnly => _nameOnlyBody(b),
            },
          ],
        ),
      ),
    );
  }

  // ---------- ① 生成身份 ----------
  List<Widget> _createBody(Brightness b) => [
        _card(
          b,
          '在下面的 12 宫格内按顺序输入你的 12 个恢复词（或点击「随机生成」）——'
              '它是你唯一的身份与解密凭证，只保存在本机，不会上传服务器。\n'
              '也可以输入 12 段自定义字符串（每段非空、区分大小写）：全部是词表词'
              '时校验和仍生效；自创密钥没有抄写校验保护，请点「复制」保存原文。',
        ),
        const SizedBox(height: 12),
        IdentityWordsGrid(onChanged: (p) => _phrase = p),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 14, color: Tokens.orange(b)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '丢失后将无法找回本机日记，也无法在多设备间同步。'
                '创建完成后本应用不再显示恢复词与派生密钥，请务必现在抄写/保存。',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: Tokens.orange(b)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _field(b, _name, '注册名', helper: '终身使用 · 多设备共用（不可更改）'),
        _errorBox(b),
        const SizedBox(height: 8),
        _primary(b, _busy ? '创建中…' : '创建身份',
            _name.text.trim().isEmpty || _busy ? null : _submit),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _mode = OnboardingMode.login;
                      _error = null;
                    }),
            child: Text('已有身份？在新设备登录',
                style: TextStyle(fontSize: 13, color: Tokens.blue(b))),
          ),
        ),
      ];

  // ---------- ② 新设备登录 ----------
  List<Widget> _loginBody(Brightness b) => [
        _card(
          b,
          '在新设备输入：同一个注册名 + 同一份身份凭证——12 个词表恢复词、'
          '或 12 段自定义字符串（空格分隔，区分大小写）、或 64 位派生密钥。'
          '校验通过后本机自动同步全部加密数据并在本地解密。请勿复用旧设备的设备号。',
        ),
        const SizedBox(height: 16),
        _field(b, _name, '注册名'),
        const SizedBox(height: 10),
        _field(b, _secret, '恢复词（12 词/12 段自定义）或派生密钥',
            hint: '粘贴同一份 12 个恢复词或 12 段自定义字符串，或 64 位派生密钥',
            minLines: 3),
        _errorBox(b),
        const SizedBox(height: 8),
        _primary(b, _busy ? '校验并同步中…' : '导入并同步',
            _busy ? null : _submit),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _mode = OnboardingMode.create;
                      _error = null;
                    }),
            child: Text('返回 · 生成新身份',
                style: TextStyle(fontSize: 13, color: Tokens.blue(b))),
          ),
        ),
      ];

  // ---------- 存量身份补设注册名 ----------
  List<Widget> _nameOnlyBody(Brightness b) => [
        _card(
          b,
          '本机已有一份身份密钥。给它起一个注册名以接入多设备共享：'
          '注册名终身使用、不可更改，所有设备用它 + 同一份恢复词登录。',
        ),
        const SizedBox(height: 16),
        _field(b, _name, '注册名', helper: '终身使用 · 多设备共用（不可更改）'),
        _errorBox(b),
        const SizedBox(height: 8),
        _primary(b, _busy ? '设置中…' : '完成设置',
            _name.text.trim().isEmpty || _busy ? null : _submit),
      ];

  // ---------- 通用组件 ----------
  Widget _card(Brightness b, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.card(b),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 13, height: 1.6, color: Tokens.label2(b)),
        ),
      );

  Widget _field(
    Brightness b,
    TextEditingController c,
    String label, {
    String? helper,
    String? hint,
    int minLines = 1,
  }) =>
      TextField(
        controller: c,
        minLines: minLines,
        maxLines: minLines == 1 ? 1 : 4,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          hintText: hint,
          filled: true,
          fillColor: Tokens.card(b),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Tokens.sep(b)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Tokens.sep(b)),
          ),
        ),
      );

  Widget _errorBox(Brightness b) {
    if (_error == null) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 14, color: Tokens.red(b)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: Tokens.red(b)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary(Brightness b, String label, VoidCallback? onTap) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: Material(
          color: onTap == null ? Tokens.fill(b) : Tokens.blue(b),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onTap == null ? Tokens.label2(b) : Colors.white),
              ),
            ),
          ),
        ),
      );
}
