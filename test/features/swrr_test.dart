// SWRR（平滑加权轮询，nginx 同款）——卡片颜色分配的算法回归（2026-11-16）：
// 等权不饿死（每项都轮到）、平滑（= 洗牌池顺序）、加权平滑性（高权重项不相邻挤兑）。
import 'package:diary_app/features/feed/feed_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('等权：输出 = 输入池顺序（平滑轮询），全部覆盖不饿死', () {
    final pool = [3, 7, 1, 5, 0, 6, 2, 4]; // 模拟洗牌后的颜色索引池
    final out = swrrOrder(pool);
    expect(out, pool, reason: '等权 SWRR 即平滑轮询：按池顺序每项各选一次');
    expect(out.toSet().length, 8, reason: '8 色全覆盖');
  });

  test('等权：每个索引恰好一次（无重复无遗漏）', () {
    for (final n in [1, 2, 5, 8, 12]) {
      final out = swrrOrder(List<int>.generate(n, (i) => i));
      expect(out.toSet(), {for (var i = 0; i < n; i++) i});
    }
  });

  test('加权 [1,1,2]：总权重 4 轮内 2 份权重项出现 2 次，且不相邻（平滑性）', () {
    final out = swrrOrder(['a', 'b', 'c'], weights: [1, 1, 2], rounds: 4);
    expect(out.where((x) => x == 'c').length, 2);
    expect(out.where((x) => x == 'a').length, 1);
    expect(out.where((x) => x == 'b').length, 1);
    // 平滑性：权重最大的 c 的两次分配不连续
    final ci = [for (var i = 0; i < out.length; i++)
      if (out[i] == 'c') i];
    expect(ci[1] - ci[0], greaterThan(1));
  });
}
