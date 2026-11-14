// 本地存储：条目明文索引（01 §7：搜索/统计全部端上做）+ KV（keystore/设置/游标/服务端地址）。
// 原生 = drift(sqlite3 落盘)；web = localStorage KV（持久）+ 内存条目缓存（刷新后靠 sync 重建）。
// 平台入口按条件导入（db_open_io.dart / db_open_stub.dart），web 不引 dart:ffi。
export 'db_open_stub.dart' if (dart.library.io) 'db_open_io.dart';
import 'package:drift/drift.dart';

part 'database.g.dart';

class Entries extends Table {
  TextColumn get localId => text()(); // uuid
  IntColumn get serverId => integer().nullable()();
  TextColumn get entryDate => text()(); // yyyy-MM-dd
  TextColumn get payloadJson => text()(); // 载荷明文（本地索引授权存）
  TextColumn get cipherJson => text().nullable()(); // Envelope JSON
  IntColumn get updatedAtMs => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {localId};
}

class Kv extends Table {
  TextColumn get k => text()();
  TextColumn get v => text()();

  @override
  Set<Column> get primaryKey => {k};
}

@DriftDatabase(tables: [Entries, Kv])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 1;

  // ---------- entries ----------
  Future<List<Entry>> allEntries() =>
      (select(entries)..orderBy([(e) => OrderingTerm.desc(e.updatedAtMs)]))
          .get();

  Future<void> upsertEntry(EntriesCompanion c) =>
      into(entries).insertOnConflictUpdate(c);

  Future<void> deleteEntryHard(String localId) =>
      (delete(entries)..where((e) => e.localId.equals(localId))).go();

  // ---------- kv ----------
  Future<String?> kvGet(String k) async {
    final rows = await (select(kv)..where((t) => t.k.equals(k))).get();
    return rows.isEmpty ? null : rows.first.v;
  }

  Future<Map<String, String>> kvAll() async {
    final rows = await select(kv).get();
    return {for (final r in rows) r.k: r.v};
  }

  Future<void> kvSet(String k, String v) =>
      into(kv).insertOnConflictUpdate(KvCompanion.insert(k: k, v: v));

  Future<void> kvRemove(String k) =>
      (delete(kv)..where((t) => t.k.equals(k))).go();

  Future<void> clearEntries() => delete(entries).go();
}

/// 会话层依赖的本地存储抽象：原生走 sqlite，web 走 localStorage，打库失败兜底走内存。
abstract class LocalStore {
  Future<Map<String, String>> kvAll();
  Future<String?> kvGet(String key);
  Future<void> kvSet(String key, String value);
  Future<void> kvRemove(String key);
  Future<void> clearEntries();
  Future<List<Entry>> allEntries();
  Future<void> upsertEntry(EntriesCompanion entry);
}

/// 内存实现：web 条目缓存基底 / 原生打库失败兜底（本次会话内可用）。
class MemoryLocalStore implements LocalStore {
  final Map<String, String> _kv = {};
  final Map<String, Entry> _entries = {};

  @override
  Future<Map<String, String>> kvAll() async => Map.of(_kv);

  @override
  Future<String?> kvGet(String key) async => _kv[key];

  @override
  Future<void> kvSet(String key, String value) async => _kv[key] = value;

  @override
  Future<void> kvRemove(String key) async => _kv.remove(key);

  @override
  Future<void> clearEntries() async => _entries.clear();

  @override
  Future<List<Entry>> allEntries() async => _entries.values.toList();

  @override
  Future<void> upsertEntry(EntriesCompanion c) async {
    _entries[c.localId.value] = Entry(
      localId: c.localId.value,
      serverId: c.serverId.present ? c.serverId.value : null,
      entryDate: c.entryDate.value,
      payloadJson: c.payloadJson.value,
      cipherJson: c.cipherJson.present ? c.cipherJson.value : null,
      updatedAtMs: c.updatedAtMs.value,
      deleted: c.deleted.present ? c.deleted.value : false,
    );
  }
}

/// drift 实现（原生平台）。
class DriftLocalStore implements LocalStore {
  final AppDb _db;
  DriftLocalStore(this._db);

  @override
  Future<Map<String, String>> kvAll() => _db.kvAll();

  @override
  Future<String?> kvGet(String k) => _db.kvGet(k);

  @override
  Future<void> kvSet(String k, String v) => _db.kvSet(k, v);

  @override
  Future<void> kvRemove(String k) => _db.kvRemove(k);

  @override
  Future<void> clearEntries() => _db.clearEntries();

  @override
  Future<List<Entry>> allEntries() => _db.allEntries();

  @override
  Future<void> upsertEntry(EntriesCompanion c) => _db.upsertEntry(c);
}
