// 键盘与评论交互（晨 17 §4.4/§4.6/§4.8/§4.11/§4.12 的 widget 级验证）。
// 会话层注入 MemoryLocalStore（本地先行 → 评论发送纯本地，无网络依赖）。
import 'dart:convert';

import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:diary_app/features/compose/compose_page.dart';
import 'package:diary_app/features/feed/comments_view.dart';
import 'package:diary_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DiaryEntry _entry({List<EntryComment> comments = const []}) => DiaryEntry(
      localId: 'e1',
      serverId: 1,
      date: '2026-11-16',
      payload: EntryPayload(
          text: '正文', time: '09:30', mood: null, comments: comments),
      cipherJson: null,
      updatedAt: DateTime(2026),
    );

Future<ProviderContainer> _bootstrap(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final session = container.read(appSessionProvider.notifier);
  await session.debugUseStore(db.MemoryLocalStore());
  session.debugHoldFlush = true;
  await session.createIdentity(RecoveryWords.generate(), '测试者');
  // testWidgets 是 FakeAsync 区：真 Future.delayed 不会推进，用 pump 推假时钟
  await tester.pump(const Duration(milliseconds: 50));
  // 放掉 _loadHolidays 资产加载的 2s timeout Timer（否则测试收尾判 pending timer）
  await tester.pump(const Duration(seconds: 3));
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return container;
}

Future<void> _pumpEntry(
    WidgetTester tester, ProviderContainer container, DiaryEntry e) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          EntryView(entry: e, isFirstOfDay: true, weekday: '日'),
        ]),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _openComments(
    WidgetTester tester, ProviderContainer container, DiaryEntry e) async {
  await _pumpEntry(tester, container, e);
  await tester.tap(find.text('${e.payload.comments.length}'));
  await tester.pumpAndSettle();
}

/// 取首个可编辑输入框的焦点节点（键盘收起断言用：hasFocus 翻转）。
FocusNode _firstEditableFocus(WidgetTester tester) =>
    tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .widget
        .focusNode;

void main() {
  testWidgets('长按评论 → 不误触条目编辑（§4.8 手势吸收）', (tester) async {
    final container = await _bootstrap(tester);
    final e = _entry(comments: const [
      EntryComment(who: '我', text: '一条评论', time: '2026-11-16 09:35'),
    ]);
    await _openComments(tester, container, e);
    await tester.longPress(find.text('一条评论'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePage), findsNothing,
        reason: '评论区长按被吸收，不再打开条目编辑');
  });

  testWidgets('评论发送 → 键盘收起 + 输入清空 + 草稿清除（§4.6/§4.12）', (tester) async {
    final container = await _bootstrap(tester);
    final session = container.read(appSessionProvider.notifier);
    final e = _entry(comments: const [
      EntryComment(who: '我', text: '已有评论', time: '2026-11-16 09:00'),
    ]);
    await _openComments(tester, container, e);
    await tester.enterText(find.byType(TextField), '新评论');
    final focus = _firstEditableFocus(tester);
    expect(focus.hasFocus, isTrue);
    expect(await session.loadDraft('cmt.e1'), '新评论', reason: '输入即缓存');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse, reason: '发送后键盘收起');
    expect(await session.loadDraft('cmt.e1'), isNull, reason: '落库成功草稿清除');
    expect(find.widgetWithText(TextField, ''), findsOneWidget,
        reason: '发送后输入框清空');
  });

  testWidgets('评论草稿恢复：重新展开后输入框预填上次未发送内容（§4.12）', (tester) async {
    final container = await _bootstrap(tester);
    container
        .read(appSessionProvider.notifier)
        .saveDraft('cmt.e1', '还没发的评论');
    final e = _entry(comments: const [
      EntryComment(who: '我', text: '已有评论', time: '2026-11-16 09:00'),
    ]);
    await _openComments(tester, container, e);
    expect(find.text('还没发的评论'), findsOneWidget);
    await tester
        .pump(const Duration(milliseconds: 350)); // 冲掉防抖 Timer（测试收尾不变量）
  });

  testWidgets('同步成功 → 已展开评论自动收起（§4.4 dataRev）；失败路径不收', (tester) async {
    final container = await _bootstrap(tester);
    final session = container.read(appSessionProvider.notifier);
    final e = _entry(comments: const [
      EntryComment(who: '我', text: '一条评论', time: '2026-11-16 09:35'),
    ]);
    await _openComments(tester, container, e);
    expect(find.byType(CommentsView), findsOneWidget);
    // rev 不变（同步失败路径）→ 不收
    await tester.pumpAndSettle();
    expect(find.byType(CommentsView), findsOneWidget);
    // syncNow 成功 → dataRev 自增 → 收起
    session.state =
        session.state.copyWith(dataRev: session.state.dataRev + 1);
    await tester.pumpAndSettle();
    expect(find.byType(CommentsView), findsNothing);
  });

  testWidgets('compose：草稿恢复 + 点空白收键盘（§4.11/§4.12）', (tester) async {
    final container = await _bootstrap(tester);
    container.read(appSessionProvider.notifier).saveDraft('new',
        jsonEncode({'text': '上次的草稿', 'mood': null, 'tags': ['工作']}));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ComposePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('上次的草稿'), findsOneWidget, reason: '草稿恢复');
    expect(find.text('#工作'), findsOneWidget, reason: '标签随草稿恢复');
    // 正文 autofocus 已持焦点 → 点页面底部空白 → 收起
    final focus = _firstEditableFocus(tester);
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(const Offset(195, 810));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse, reason: '点空白收键盘');
    await tester
        .pump(const Duration(milliseconds: 350)); // 冲掉防抖 Timer（测试收尾不变量）
  });
}
