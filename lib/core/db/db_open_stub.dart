// Web：无本地 SQLite 运行时 → localStorage KV（持久，含 keystore/设置/游标/服务端地址）
// + 内存条目缓存（父类）。条目真实数据在服务端密文，浏览器刷新后解锁+sync 即重建索引。
import 'dart:convert';

import 'package:web/web.dart' as web;

import 'database.dart';

class WebLocalStore extends MemoryLocalStore {
  static const _indexKey = 'kv.index';

  web.Storage get _ls => web.window.localStorage;

  List<String> _index() {
    final raw = _ls.getItem(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  void _writeIndex(Set<String> keys) =>
      _ls.setItem(_indexKey, jsonEncode(keys.toList()));

  @override
  Future<Map<String, String>> kvAll() async {
    final out = <String, String>{};
    for (final k in _index()) {
      final v = _ls.getItem(k);
      if (v != null) out[k] = v;
    }
    return out;
  }

  @override
  Future<String?> kvGet(String key) async => _ls.getItem(key);

  @override
  Future<void> kvSet(String key, String value) async {
    _ls.setItem(key, value);
    _writeIndex({..._index(), key});
  }

  @override
  Future<void> kvRemove(String key) async {
    _ls.removeItem(key);
    _writeIndex(_index().toSet()..remove(key));
  }
}

Future<LocalStore> openLocalStore() => Future.value(WebLocalStore());
