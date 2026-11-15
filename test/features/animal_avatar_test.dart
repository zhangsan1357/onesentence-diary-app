// 动物头像（2026-11-16）：seed 确定性（同刷新周期稳定）+ 刷新盐整体换新（随机性）。
import 'package:diary_app/widgets/animal_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _emoji(String seed) {
  final table = animalAvatars;
  return table[stableHash(seed) % table.length].$1;
}

void main() {
  test('stableHash：确定性 + 分散', () {
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
  });

  test('12 生肖配置表：数量 12、emoji 互不相同', () {
    expect(animalAvatars.length, 12);
    expect(animalAvatars.map((e) => e.$1).toSet().length, 12);
  });

  testWidgets('渲染冒烟（圆底 + emoji）+ 盐变后多数换新', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AnimalAvatar(seed: '1|谁|时间|内容', size: 32)));
    expect(find.byType(AnimalAvatar), findsOneWidget);
    expect(find.byType(ClipOval), findsOneWidget);

    // 随机性语义：换盐后 20 个种子里撞回同动物的应是少数（期望约 20/12≈1.7）
    var same = 0;
    for (var i = 0; i < 20; i++) {
      final s = '评论者$i|时间$i|内容$i';
      if (_emoji(s) == _emoji('x$s')) same++;
    }
    expect(same, lessThan(5), reason: '盐变后撞同动物的应为少数');
  });
}
