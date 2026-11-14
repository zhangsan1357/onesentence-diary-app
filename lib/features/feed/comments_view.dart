// 评论视图：懒加载展开后的列表 + 输入行（0 条显示空态文案）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_defaults.dart';
import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../features/theme/tokens.dart';

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
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          AppDefaults.tagColor(c.who).withValues(alpha: .13),
                    ),
                    child: Text(
                      c.who.isEmpty ? '?' : c.who.characters.first,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppDefaults.tagColor(c.who),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: c.who,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Tokens.label(b),
                                ),
                              ),
                              const WidgetSpan(child: SizedBox(width: 6)),
                              TextSpan(
                                text: c.text,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: Tokens.label(b),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(c.time,
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
