// 评论视图：懒加载展开后的列表 + 输入行（0 条显示空态文案）。
// 每条评论配头像（2026-11-16 用户拍板退回本地动物图标、扩到 12 种）：
// 评论在端上密文内、后端不可见 → AnimalAvatar 本地绘制，种子 =
// 刷新盐 + 评论身份（who|time|text）——同一刷新周期内同一条评论稳定，
// 每次刷新（下拉/横幅重试/重启）盐重掷 → 全部评论换新动物。时间显示
// 标准格式 yyyy-MM-dd HH:mm。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider 在 Riverpod 3 收进 legacy（一个可变 int 的最简载体）
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
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

  @override
  void dispose() {
    _input.dispose();
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimalAvatar(
                      seed: '$salt|${c.who}|${c.time}|${c.text}', size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 只显示头像+内容（2026-11-15 用户拍板去掉「我/她」署名）
                        // 待同步标记（* 指针，晨 15）：离线新增的评论按库行 meta 标注
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Tokens.label(b)),
                            children: [
                              ...pendingMark(
                                  widget.entry.pendingComments.contains(i), b),
                              TextSpan(text: c.text),
                            ],
                          ),
                        ),
                        Text(_fmtTime(c),
                            style: TextStyle(
                                fontSize: 10, color: Tokens.label3(b))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  style: TextStyle(fontSize: 13, color: Tokens.label(b)),
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
    );
  }

  /// 评论时间标准格式 yyyy-MM-dd HH:mm：新评论已存完整格式；
  /// 存量只有 HH:mm，用条目日期补全。
  String _fmtTime(EntryComment c) =>
      c.time.length > 5 ? c.time : '${widget.entry.date} ${c.time}';

  Future<void> _send() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _input.clear();
    try {
      await ref.read(appSessionProvider.notifier).addComment(widget.entry, v);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评论发送失败：$err')),
        );
      }
    }
  }
}
