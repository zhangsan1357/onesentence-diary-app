// 标签 8 色哈希黄金向量：由 Node（真实 JS 引擎，保证 32 位溢出语义）生成。
// 生成命令：
//   node -e "const TCN=['blue','green','red','orange','purple','gray','pink','cyan'];
//            function tagColor(t){var h=0;for(var i=0;i<t.length;i++){h=t.charCodeAt(i)+((h<<5)-h)}
//            h=Math.abs(h);return TCN[h%TCN.length]}"
import 'package:diary_app/core/config/app_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vectors = {
    '工作': 'cyan',
    '吐槽': 'gray',
    '生活': 'purple',
    '她': 'green',
    '美食': 'green',
    '电影': 'purple',
    '家庭': 'cyan',
    '摄影': 'gray',
    '流水账': 'orange',
    '趣事': 'blue',
    'travel': 'pink',
    '运动': 'blue',
    '夜跑': 'gray',
    '读书': 'orange',
  };

  test('tagColor 与 JS 参考实现一致（同名永远同色）', () {
    vectors.forEach((name, expected) {
      expect(AppDefaults.tagColorName(name), expected, reason: name);
    });
  });

  test('同色稳定性：同名重复调用结果一致', () {
    expect(AppDefaults.tagColorName('工作'), AppDefaults.tagColorName('工作'));
  });
}
