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
  static String tagColorName(String name) => _hashColorName(name);

  /// 动态色（2026-11-14 用户拍板）：哈希种子 = 标签名 + 正文 → 同一标签在不同
  /// 条目呈现不同颜色（覆盖 01 §6「同名永远同色」原约定）。调色板覆盖仍优先。
  static String tagColorSeeded(String name, String seed) =>
      _hashColorName(name + seed);

  static String _hashColorName(String s) {
    var h = 0;
    for (var i = 0; i < s.length; i++) {
      final cc = s.codeUnitAt(i);
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

  /// 取标签显示色：调色板覆盖 > 名字哈希。
  static Color tagColor(String name) => _colorByOverrideOr(name, () => tagColorName(name));

  /// 取标签显示色（动态）：调色板覆盖 > 标签名+正文哈希。
  static Color tagColorOf(String name, {String? seed}) =>
      _colorByOverrideOr(name, () => seed == null ? tagColorName(name) : tagColorSeeded(name, seed));

  static Color _colorByOverrideOr(String name, String Function() fallback) {
    final cn = tagColorOverrides[name];
    if (cn != null && tagColorHex.containsKey(cn)) {
      return Color(tagColorHex[cn]!);
    }
    return Color(tagColorHex[fallback()]!);
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

  /// 服务端心情列表（§5.14 全面服务端化：后端 mood 全局表=唯一事实源，sort ASC；
  /// 会话层拉取覆盖 + KV 快照离线兜底）。空 = 未拉取/服务端空表 → 回落静态种子。
  static List<MoodCfg> serverMoods = const [];

  /// 心情选择器全集：服务端列表优先，未拉取（首启/demo/服务端空表）回落种子。
  static List<MoodCfg> get allMoods =>
      serverMoods.isNotEmpty ? serverMoods : moods;

  /// 心情 key → 显示名：服务端 name（缺口 #9）→ 种子中文名 → key 本身。
  static String moodNameOf(String key, {String? serverName}) {
    if (serverName != null && serverName.isNotEmpty) return serverName;
    for (final m in moods) {
      if (m.key == key) return m.name;
    }
    return key;
  }

  static MoodCfg moodOf(String key) {
    for (final m in allMoods) {
      if (m.key == key) return m;
    }
    return moods.last; // 未知 key 兜底（与原实现一致）
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
