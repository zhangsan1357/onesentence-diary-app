// NetAvatar 单测（2026-11-16 晨 15 方案 D）：s= 尺寸规范化、天卡头像预取清单
// 收集去重、URL 缺失回落中性人形占位。淡入动画为声明式 AnimatedOpacity（5 行），
// 回归由 UI 冒烟套件 + 真机验收覆盖（mock HttpClient 的成本高于回归风险）。
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/features/feed/feed_page.dart';
import 'package:diary_app/widgets/net_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sized：无 s 追加、有 s 覆盖、其余查询参数保留', () {
    expect(NetAvatar.sized('https://cn.cravatar.com/avatar/abc.png', 46),
        'https://cn.cravatar.com/avatar/abc.png?s=138');
    final r = Uri.parse(NetAvatar.sized('https://x/avatar/abc?s=64&d=mp', 50));
    expect(r.queryParameters, {'s': '150', 'd': 'mp'});
  });

  test('dayAvatarUrls：每天卡取首条目、去重、跳过无 URL 的天', () {
    DiaryEntry e(String id, {String? url}) => DiaryEntry(
          localId: id,
          serverId: null,
          date: '2026-11-16',
          payload: const EntryPayload(text: '', time: '', mood: null),
          cipherJson: null,
          updatedAt: DateTime(2026),
          avatarUrl: url,
        );
    final groups = [
      MapEntry('2026-11-16', [e('a', url: 'https://x/1'), e('b', url: 'https://x/2')]),
      MapEntry('2026-11-15', [e('c'), e('d', url: 'https://x/3')]),
      MapEntry('2026-11-14', [e('e', url: 'https://x/1')]),
    ];
    expect(dayAvatarUrls(groups), ['https://x/1']);
    expect(dayAvatarUrls(const []), isEmpty);
  });

  testWidgets('url 缺失 → 中性人形占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(child: NetAvatar(url: null, size: 46))));
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
