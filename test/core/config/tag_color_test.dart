// 标签 8 色哈希黄金向量：由 Node（真实 JS 引擎，保证 32 位溢出语义）生成。
// 生成命令：
//   node -e "const TCN=['blue','green','red','orange','purple','gray','pink','cyan'];
//            function tagColor(t){var h=0;for(var i=0;i<t.length;i++){h=t.charCodeAt(i)+((h<<5)-h)}
//            h=Math.abs(h);return TCN[h%TCN.length]}"
import 'package:diary_app/core/config/app_defaults.dart';
import 'package:flutter/material.dart' show Color;
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

  test('动态色（2026-11-14 用户拍板）：标签名+正文哈希 → 同标签异条目变色', () {
    // 确定性
    expect(AppDefaults.tagColorSeeded('吐槽', '今天写了一句话'),
        AppDefaults.tagColorSeeded('吐槽', '今天写了一句话'));
    // 同标签、不同正文 → 颜色不同（抽样向量实测异色）
    final a = AppDefaults.tagColorSeeded('吐槽', '今天又开了三个小时的会');
    final b = AppDefaults.tagColorSeeded('吐槽', '加班到十一点，窗外的雨一直没停');
    expect(a, isNot(b), reason: '不同条目的同一标签应呈不同颜色');
    // 调色板覆盖优先于动态色
    AppDefaults.tagColorOverrides['吐槽'] = 'pink';
    expect(AppDefaults.tagColorOf('吐槽', seed: '任意正文'),
        const Color(0xFFFF2D55));
    AppDefaults.tagColorOverrides.remove('吐槽');
  });
}
