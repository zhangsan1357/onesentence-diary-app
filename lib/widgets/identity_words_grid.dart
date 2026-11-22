// 身份短语 12 宫格输入——注册（引导页创建）与更换主密钥共用的唯一实现（§5.17）。
// 形态：3×4 序号格逐格输入（顺序即位置；整段短语粘贴到任意一格也可以——空白
// 归一由 canonicalPhrase 收口）+ 随机生成/复制全部 + 派生密钥同屏（12 格非空
// 即显，§5.15：自定义 12 段没有校验和，派生密钥是唯一可核对的等价副本）。
// 校验不在组件内：拼接短语经 onChanged 交调用方，会话层 validateImport 三态兜底。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/e2ee/bytes.dart';
import '../core/session/recovery_words.dart';
import '../features/theme/tokens.dart';

class IdentityWordsGrid extends StatefulWidget {
  const IdentityWordsGrid({super.key, this.initialPhrase = '', this.onChanged});

  /// 预填短语（换钥随机预填；注册默认空）。
  final String initialPhrase;

  /// 输入变化回调：携带当前拼接短语（逐格 trim 单空格连接）。
  final ValueChanged<String>? onChanged;

  @override
  State<IdentityWordsGrid> createState() => _IdentityWordsGridState();
}

class _IdentityWordsGridState extends State<IdentityWordsGrid> {
  final _cells =
      List<TextEditingController>.generate(12, (_) => TextEditingController());
  bool _copied = false;
  bool _copiedKey = false;

  @override
  void initState() {
    super.initState();
    final init = RecoveryWords.canonicalPhrase(widget.initialPhrase);
    if (init != null) {
      final words = init.split(' ');
      for (var i = 0; i < 12; i++) {
        _cells[i].text = words[i];
      }
    }
  }

  @override
  void dispose() {
    for (final c in _cells) {
      c.dispose();
    }
    super.dispose();
  }

  /// 当前拼接短语（逐格 trim 单空格连接）。
  String get phrase => _cells.map((c) => c.text.trim()).join(' ');

  /// 派生密钥（= 短语的 SHA-256 seed hex）：12 格非空即有值。
  String? get _derivedKey {
    if (RecoveryWords.canonicalPhrase(phrase) == null) return null;
    return hexEncode(RecoveryWords.phraseToSeed(phrase));
  }

  void _regenerate() {
    final words = RecoveryWords.generate().split(' ');
    for (var i = 0; i < 12; i++) {
      _cells[i].text = words[i];
    }
    widget.onChanged?.call(phrase);
    setState(() {});
  }

  Future<void> _copyPhrase() async {
    await Clipboard.setData(ClipboardData(text: phrase));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && _copied) setState(() => _copied = false);
  }

  Future<void> _copyKey() async {
    final key = _derivedKey;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    setState(() => _copiedKey = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && _copiedKey) setState(() => _copiedKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grid(b),
        // Wrap：注册页宽度一行放下；弹窗窄宽度自动换行不溢出（§5.17）
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _regenerate,
              icon: Icon(Icons.casino_outlined,
                  size: 15, color: Tokens.blue(b)),
              label: Text('随机生成 12 词',
                  style: TextStyle(fontSize: 13, color: Tokens.blue(b))),
            ),
            TextButton.icon(
              onPressed: _derivedKey == null ? null : _copyPhrase,
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
      ],
    );
  }

  /// 12 宫格：逐格直接输入（顺序即位置），iOS 键盘「下一项」逐格跳转。
  Widget _grid(Brightness b) {
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
                onChanged: (_) {
                  widget.onChanged?.call(phrase);
                  setState(() {});
                },
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ],
        ),
      );

  /// 派生密钥展示块：12 格非空即显示，实时随输入更新。
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Tokens.label2(b)),
          ),
          const SizedBox(height: 6),
          if (key == null)
            Text('恢复词有效后自动生成',
                style: TextStyle(fontSize: 12, color: Tokens.label3(b)))
          else ...[
            SelectableText(
              key,
              key: const ValueKey('derived-key'),
              style: TextStyle(
                  fontSize: 11, height: 1.5, color: Tokens.label(b)),
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
                              color: _copiedKey
                                  ? Tokens.green
                                  : Tokens.blue(b)),
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
}
