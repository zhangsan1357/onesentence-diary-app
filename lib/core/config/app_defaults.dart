// 标签 8 色稳定哈希（移植 web/src/utils/tagColor.js，01 手册 §6）与心情默认表。
// JS 位运算是 32 位截断，Dart 需显式 toSigned(32) 模拟；向量由 Node 生成
//（test/core/config/tag_color_test.dart）。
import 'package:flutter/material.dart';

class AppDefaults {
  AppDefaults._();

  /// 8 色名序（mockup TCN）。
  static const tagColorNames = [
    'blue',
    'green',
    'red',
    'orange',
    'purple',
    'gray',
    'pink',
    'cyan',
  ];

  /// 8 色值（iOS 系统色板，01 手册 §6 注释）。
  static const tagColorHex = {
    'blue': 0xFF007AFF,
    'green': 0xFF34C759,
    'red': 0xFFFF3B30,
    'orange': 0xFFFF9500,
    'purple': 0xFFAF52DE,
    'gray': 0xFF8E8E93,
    'pink': 0xFFFF2D55,
    'cyan': 0xFF30B0C7,
  };

  /// 同名标签永远同色（JS 32 位溢出语义模拟）。
  static String tagColorName(String name) {
    var h = 0;
    for (var i = 0; i < name.length; i++) {
      final cc = name.codeUnitAt(i);
      // JS: h = charCode + ((h << 5) - h)   —— 全程按 32 位有符号截断
      h = _toInt32(cc) + _toInt32((_toInt32(h << 5)) - h);
      h = _toInt32(h);
    }
    final abs = h.isNegative ? _toInt32(-h) : h;
    return tagColorNames[abs % 8];
  }

  /// 用户调色板覆盖（标签管理设置，设备本地 KV，AppSession 加载/回写）：
  /// 标签名 → 8 色名；未覆盖的标签走稳定哈希。
  static Map<String, String> tagColorOverrides = {};

  /// 用户标签库（标签管理增删改查；初始 = defaultTags 三项，KV 持久化后整体替换）。
  static List<String> tagPresets = defaultTags;

  static Color tagColor(String name) {
    final cn = tagColorOverrides[name];
    if (cn != null && tagColorHex.containsKey(cn)) {
      return Color(tagColorHex[cn]!);
    }
    return Color(tagColorHex[tagColorName(name)]!);
  }

  static int _toInt32(int x) => x.toSigned(32);

  /// 心情默认表（02 §4.2 种子 + mockup 中文名）。key/emoji/色值全局稳定。
  static const moods = [
    MoodCfg(key: 'happy', emoji: '😊', name: '开心', colorHex: 0xFF34C759),
    MoodCfg(key: 'love', emoji: '😍', name: '喜爱', colorHex: 0xFFFF2D55),
    MoodCfg(key: 'angry', emoji: '😤', name: '吐槽', colorHex: 0xFFFF9500),
    MoodCfg(key: 'surprise', emoji: '😮', name: '惊讶', colorHex: 0xFFAF52DE),
    MoodCfg(key: 'sad', emoji: '😢', name: '低落', colorHex: 0xFF5856D6),
    MoodCfg(key: 'tired', emoji: '😴', name: '疲惫', colorHex: 0xFF8E8E93),
  ];

  /// 默认心情的显示覆盖（心情管理编辑，key → 完整 MoodCfg；设备本地 KV）。
  static Map<String, MoodCfg> moodOverrides = {};

  /// 用户自定义心情（心情管理新增）。
  static List<MoodCfg> customMoods = const [];

  /// 心情选择器全集：默认 6 + 自定义。
  static List<MoodCfg> get allMoods => [...moods, ...customMoods];

  static MoodCfg moodOf(String key) {
    for (final m in customMoods) {
      if (m.key == key) return m;
    }
    MoodCfg? base;
    for (final m in moods) {
      if (m.key == key) base = m;
    }
    if (base == null) return moods.last; // 未知 key 兜底（与原实现一致）
    final o = moodOverrides[key];
    return o ?? base;
  }

  /// 标签默认模板（02 §4.2 tag_config 种子，device 0）。
  static const defaultTags = ['吐槽', '趣事', '流水账'];
}

class MoodCfg {
  final String key;
  final String emoji;
  final String name;
  final int colorHex;

  const MoodCfg({
    required this.key,
    required this.emoji,
    required this.name,
    required this.colorHex,
  });

  Color get color => Color(colorHex);
}
