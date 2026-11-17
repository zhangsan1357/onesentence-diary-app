// 评论视图：懒加载展开后的列表 + 输入行（0 条显示空态文案）。
// 每条评论配头像（2026-11-16 用户拍板退回本地动物图标、扩到 12 种）：
// 评论在端上密文内、后端不可见 → AnimalAvatar 本地绘制，种子 =
// 刷新盐 + 评论身份（who|time|text）——同一刷新周期内同一条评论稳定，
// 每次刷新（下拉/横幅重试/重启）盐重掷 → 全部评论换新动物。时间显示
// 标准格式 yyyy-MM-dd HH:mm。
// 晨 17：头像调回原版 24（d776648）；发送后键盘收起（§4.6）；未发送输入
// 走会话层草稿缓存（§4.12）；长按评论区不再误触条目编辑（§4.8 手势吸收）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 Riverpod 3 收进 legacy（一个可变 int 的最简载体）
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'dart:async' show unawaited;

import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/errors.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/animal_avatar.dart';
import '../../widgets/common.dart' show pendingMark;

/// 评论头像刷新盐（2026-11-16）：feed 页每次刷新重掷 → 全部评论动物换新
/// （随机性语义与卡片颜色序列一致）。
final avatarSaltProvider = StateProvider<int>((ref) => 0);

class CommentsView extends ConsumerStatefulWidget {
  final DiaryEntry entry;

  const CommentsView({super.key, required this.entry});

  @override
  ConsumerState<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends ConsumerState<CommentsView> {
  final _input = TextEditingController();
  int? _editingIndex; // 行内编辑中的评论下标（晨 19 §5.2）
  final _editCtrl = TextEditingController();

  /// 草稿键：按条目隔离（§4.12），addComment 本地落库成功即清。
  String get _draftKey => 'cmt.${widget.entry.localId}';

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDraft());
  }

  Future<void> _restoreDraft() async {
    final d = await ref
        .read(appSessionProvider.notifier)
        .loadDraft(_draftKey);
    if (d != null && d.isNotEmpty && mounted && _input.text.isEmpty) {
      setState(() => _input.text = d);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final salt = ref.watch(avatarSaltProvider);
    final comments = widget.entry.payload.comments;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Tokens.sep(b),
            width: .5,
          ),
        ),
      ),
      // 长按吸收（§4.8）：内层识别器胜出手势竞技场 → 不再冒泡到 EntryView
      // 的长按编辑；后续评论长按菜单在此扩展点落地。
      child: GestureDetector(
        onLongPress: () {},
        behavior: HitTestBehavior.opaque,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('还没有评论，写第一条',
                  style: TextStyle(fontSize: 12, color: Tokens.label3(b))),
            ),
          for (final (i, c) in comments.indexed)
            GestureDetector(
              // 长按菜单（晨 19 §5.2，§4.8 吸收层在外不变）；编辑中不再弹菜单
              onLongPress: _editingIndex == i ? null : () => _showMenu(i, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimalAvatar(
                        seed: '$salt|${c.who}|${c.time}|${c.text}', size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_editingIndex == i) ...[
                            TextField(
                              controller: _editCtrl,
                              autofocus: true,
                              style:
                                  TextStyle(fontSize: 13, color: Tokens.label(b)),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: Tokens.fill(b),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 7),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _saveEdit(i),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _editingIndex = null),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => _saveEdit(i),
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          ] else ...[
                            // 只显示头像+内容（2026-11-15 用户拍板去掉「我/她」署名）
                            // 待同步标记（* 指针，晨 15）：未上云评论内容（新增/编辑，
                            // 晨 19 §5.2 扩义）按库行 meta 标注
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: Tokens.label(b)),
                                children: [
                                  ...pendingMark(
                                      widget.entry.pendingComments.contains(i),
                                      b),
                                  TextSpan(text: c.text),
                                ],
                              ),
                            ),
                            Text(_fmtTime(c),
                                style: TextStyle(
                                    fontSize: 10, color: Tokens.label3(b))),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: TextStyle(fontSize: 13, color: Tokens.label(b)),
                  onChanged: (v) => ref
                      .read(appSessionProvider.notifier)
                      .saveDraft(_draftKey, v),
                  decoration: InputDecoration(
                    hintText: '写评论…',
                    hintStyle: TextStyle(color: Tokens.label3(b)),
                    filled: true,
                    fillColor: Tokens.fill(b),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 7),
              Material(
                color: Tokens.blue(b),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _send,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    child: Text('发送',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  /// 评论时间标准格式 yyyy-MM-dd HH:mm：新评论已存完整格式；
  /// 存量只有 HH:mm，用条目日期补全。
  String _fmtTime(EntryComment c) =>
      c.time.length > 5 ? c.time : '${widget.entry.date} ${c.time}';

  /// 长按菜单（晨 19 §5.2）：复制所有评论可看；编辑/删除仅自己的（who=='我'）。
  void _showMenu(int i, EntryComment c) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: c.text));
              _toast('已复制');
            },
            child: const Text('复制'),
          ),
          if (c.who == '我') ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _editingIndex = i;
                  _editCtrl.text = c.text;
                });
              },
              child: const Text('编辑'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDelete(i);
              },
              isDestructiveAction: true,
              child: const Text('删除'),
            ),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('删除后不可恢复，确定删除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(appSessionProvider.notifier)
          .deleteComment(widget.entry, i);
    } catch (err) {
      if (mounted) _toast('删除失败：${friendlyError(err)}');
    }
  }

  Future<void> _saveEdit(int i) async {
    final v = _editCtrl.text.trim();
    if (v.isEmpty) return;
    try {
      await ref
          .read(appSessionProvider.notifier)
          .editComment(widget.entry, i, v);
      if (mounted) setState(() => _editingIndex = null);
    } catch (err) {
      // 失败：编辑框保留，可重试
      if (mounted) _toast('修改失败：${friendlyError(err)}');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    // 发送后键盘收起（§4.6）：提交即 unfocus（本地先行后发送即时返回）
    FocusScope.of(context).unfocus();
    try {
      await ref.read(appSessionProvider.notifier).addComment(widget.entry, v);
      await ref.read(appSessionProvider.notifier).clearDraft(_draftKey);
      _input.clear();
    } catch (err) {
      // 失败：输入保留（草稿仍在），可重试
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评论发送失败：${friendlyError(err)}')),
        );
      }
    }
  }
}
