// 动物头像（2026-11-16 用户拍板退回原版）：seed 确定性（同刷新周期稳定）+
// 刷新盐整体换新（随机性）+ 评论场景无底色（裸 emoji）。
import 'package:diary_app/widgets/animal_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _face(String seed) =>
    animalFaces[stableHash(seed) % animalFaces.length];

void main() {
  test('stableHash：确定性 + 分散', () {
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
  });

  test('原版动物配置表：数量 20、互不相同', () {
    expect(animalFaces.length, 20);
    expect(animalFaces.toSet().length, 20);
  });

  testWidgets('渲染为裸 emoji：无底色圆（ClipOval/Container 着色）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AnimalAvatar(seed: '1|谁|时间|内容', size: 32)));
    expect(find.byType(AnimalAvatar), findsOneWidget);
    expect(find.byType(ClipOval), findsNothing);
    expect(find.byType(Container), findsNothing);
  });

  test('盐变随机性：换盐后 20 个种子里撞回同动物的应是少数（期望约 1）', () {
    var same = 0;
    for (var i = 0; i < 20; i++) {
      final s = '评论者$i|时间$i|内容$i';
      if (_face(s) == _face('x$s')) same++;
    }
    expect(same, lessThan(5), reason: '盐变后撞同动物的应为少数');
  });
}
