// 首次身份引导（2026-11-14 后端身份模型 v4）：
// create   = ①首次启动 · 生成身份：12 宫格直接输入恢复词（默认），下方可一键随机生成
//            + 派生密钥同屏展示 + 注册名（终身不变，多设备共用）
// login    = ②新设备登录：同一注册名 + 同一份身份凭证（12 词/12 段自定义/派生密钥）→ 校验 → 全量同步
// nameOnly = 存量 keystore 一次性补设注册名（旧版身份接入多设备共享）
// 身份凭证只在本页出现：创建/登录完成后，应用内任何页面不再显示恢复词与派生密钥。
// 页面动作经回调注入（main.dart 接线会话层），自身不依赖存储，可独立 widget 测试。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/e2ee/bytes.dart';
import '../../core/session/recovery_words.dart';
import '../../core/util/errors.dart';
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
  // ① 12 宫格：默认逐格输入（顺序即位置），「随机生成」把 12 词填入各格
  final _cells =
      List<TextEditingController>.generate(12, (_) => TextEditingController());
  bool _busy = false;
  bool _copied = false;
  bool _copiedKey = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    for (final c in _cells) {
      c.dispose();
    }
    super.dispose();
  }

  /// 创建身份实际使用的恢复词：逐格拼接（非法时原样交会话层报错）。
  String get _effectivePhrase =>
      _cells.map((c) => c.text.trim()).join(' ');

  /// 随机生成 12 词填入宫格（生成后仍可逐格修改）。
  void _regenerate() {
    final words = RecoveryWords.generate().split(' ');
    for (var i = 0; i < 12; i++) {
      _cells[i].text = words[i];
    }
    setState(() {});
  }

  /// 派生密钥（= 恢复词的 SHA-256 seed hex）：12 段非空即显示（§5.15——自定义
  /// 12 段没有校验和，派生密钥是唯一可核对的等价副本）。
  String? get _derivedKey {
    if (RecoveryWords.canonicalPhrase(_effectivePhrase) == null) return null;
    return hexEncode(RecoveryWords.phraseToSeed(_effectivePhrase));
  }

  Future<void> _copyPhrase() async {
    await Clipboard.setData(ClipboardData(text: _effectivePhrase));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted && _copied) setState(() => _copied = false);
  }

  Future<void> _copyKey() async {
    final key = _derivedKey;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    setState(() => _copiedKey = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted && _copiedKey) setState(() => _copiedKey = false);
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
          await widget.onCreate!(_effectivePhrase, _name.text);
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
        _wordGrid(b),
        // 宫格下方：随机生成 / 复制（12 词有效后才可复制）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _regenerate,
              icon: Icon(Icons.casino_outlined,
                  size: 15, color: Tokens.blue(b)),
              label: Text('随机生成 12 词',
                  style: TextStyle(fontSize: 13, color: Tokens.blue(b))),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed:
                  (_busy || _derivedKey == null) ? null : _copyPhrase,
              icon: Icon(
                _copied ? Icons.check : Icons.copy_outlined,
                size: 15,
                color: _copied ? Tokens.green : Tokens.blue(b),
              ),
              label: Text(
                _copied ? '已复制，请妥善保存' : '复制全部 12 词',
                style: TextStyle(
                    fontSize: 13,
                    color: _copied
                        ? Tokens.green
                        : (_derivedKey == null
                            ? Tokens.label3(b)
                            : Tokens.blue(b))),
              ),
            ),
          ],
        ),
        _keyBlock(b),
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

  /// 派生密钥展示块：宫格 12 词有效即显示，实时随输入更新。
  Widget _keyBlock(Brightness b) {
    final key = _derivedKey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tokens.card(b),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tokens.sep(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '派生密钥（与恢复词等价，登录新设备时任选其一）',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: Tokens.label2(b)),
          ),
          const SizedBox(height: 6),
          if (key == null)
            Text('恢复词有效后自动生成',
                style: TextStyle(fontSize: 12, color: Tokens.label3(b)))
          else ...[
            SelectableText(
              key,
              key: const ValueKey('derived-key'),
              style: TextStyle(fontSize: 11, height: 1.5, color: Tokens.label(b)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: Material(
                color: Tokens.fill(b),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _copyKey,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copiedKey ? Icons.check : Icons.copy_outlined,
                          size: 14,
                          color: _copiedKey ? Tokens.green : Tokens.blue(b),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _copiedKey ? '已复制，请妥善保存' : '复制派生密钥',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _copiedKey ? Tokens.green : Tokens.blue(b)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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

  /// 12 宫格：逐格直接输入（顺序即位置），iOS 键盘「下一项」逐格跳转。
  Widget _wordGrid(Brightness b) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Tokens.card(b),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tokens.sep(b)),
      ),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.4,
            children: [
              for (var i = 0; i < 12; i++) _wordCellInput(b, i + 1, _cells[i]),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('逐格按顺序输入；把整段恢复词粘贴到任意一格也可以',
                style: TextStyle(fontSize: 11, color: Tokens.label3(b))),
          ),
        ],
      ),
    );
  }

  /// 手动输入格：序号可见（顺序即位置），iOS 键盘「下一项」逐格跳转。
  Widget _wordCellInput(Brightness b, int n, TextEditingController ctrl) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Tokens.fill(b),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Tokens.label3(b))),
            const SizedBox(width: 5),
            Expanded(
              child: TextField(
                controller: ctrl,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Tokens.label(b)),
                textInputAction:
                    n < 12 ? TextInputAction.next : TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ],
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
