// 待同步标记渲染（2026-11-16 晨 15 方案 * 指针）：正文/评论行首橙 *，
// 显示层注入——pending 条目有、干净条目没有；评论按下标精确标注。
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/features/feed/comments_view.dart';
import 'package:diary_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DiaryEntry _entry({
  bool textPending = false,
  List<int> pendingComments = const [],
  List<EntryComment> comments = const [],
}) =>
    DiaryEntry(
      localId: 'x',
      serverId: 1,
      date: '2026-11-16',
      payload: EntryPayload(
          text: '正文内容', time: '09:30', mood: null, comments: comments),
      cipherJson: null,
      updatedAt: DateTime(2026),
      textPending: textPending,
      pendingComments: pendingComments,
    );

void main() {
  testWidgets('正文：pending 条目行首有 *，干净条目没有', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: EntryView(
              entry: _entry(textPending: true),
              isFirstOfDay: true,
              weekday: '日'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('*', findRichText: true), findsOneWidget);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: EntryView(
              entry: _entry(), isFirstOfDay: true, weekday: '日'),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('*', findRichText: true), findsNothing);
  });

  testWidgets('评论：按下标精确标注（只有离线新增的那条带 *）', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: CommentsView(
            entry: _entry(
              pendingComments: const [1],
              comments: const [
                EntryComment(who: '我', text: '旧评论', time: '2026-11-16 09:00'),
                EntryComment(who: '我', text: '新评论', time: '2026-11-16 09:05'),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final rich = find.textContaining('*', findRichText: true);
    expect(rich, findsOneWidget);
    final span =
        tester.widget<RichText>(rich.first).text.toPlainText();
    expect(span, contains('*新评论'));
    expect(span, isNot(contains('旧评论*')));
  });
}
