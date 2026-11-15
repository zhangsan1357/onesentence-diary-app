// 本地存储：条目明文索引（01 §7：搜索/统计全部端上做）+ KV（keystore/设置/游标/服务端地址）
// + 离线队列（2026-11-16：云端不可达时 CRUD 本地保存，恢复后一次性同步）。
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
  // 同步状态（离线队列，2026-11-16）：0=已同步 1=待新建 2=待替换 3=待删除。
  // 非 0 行是本地未上云的最终态，拉取同步必须跳过（防云端旧密文覆盖本地改动）。
  IntColumn get syncState => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {localId};
}

/// 离线暂存媒体（已加密字节，联网后随条目队列一起上传；落盘零明文 P1-3 同款约束）。
class PendingMedia extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localId => text()(); // 所属条目（entries.localId）
  TextColumn get kind => text()(); // image | audio
  IntColumn get sec => integer().nullable()(); // 音频秒数
  // 列名不能用 blob（与 drift Table.blob 构建器冲突）：bytes = nonce12 ‖ AES-GCM 密文（含 tag）
  BlobColumn get bytes => blob()();
  TextColumn get cekWrappedB64 => text()(); // 媒体 CEK 的 ECIES 包裹（b64）

  @override
  Set<Column> get primaryKey => {id};
}

class Kv extends Table {
  TextColumn get k => text()();
  TextColumn get v => text()();

  @override
  Set<Column> get primaryKey => {k};
}

@DriftDatabase(tables: [Entries, Kv, PendingMedia])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2（2026-11-16 离线队列）：条目加同步状态列 + 待传媒体表
          if (from < 2) {
            await m.addColumn(entries, entries.syncState);
            await m.createTable(pendingMedia);
          }
        },
      );

  // ---------- entries ----------
  Future<List<Entry>> allEntries() =>
      (select(entries)..orderBy([(e) => OrderingTerm.desc(e.updatedAtMs)]))
          .get();

  Future<void> upsertEntry(EntriesCompanion c) =>
      into(entries).insertOnConflictUpdate(c);

  Future<void> deleteEntryHard(String localId) =>
      (delete(entries)..where((e) => e.localId.equals(localId))).go();

  // ---------- pending media（离线暂存） ----------
  Future<List<PendingMediaData>> allPendingMedia() => select(pendingMedia).get();

  Future<void> insertPendingMedia(PendingMediaCompanion c) =>
      into(pendingMedia).insert(c);

  Future<void> deletePendingMediaFor(String localId) =>
      (delete(pendingMedia)..where((t) => t.localId.equals(localId))).go();

  Future<void> clearPendingMedia() => delete(pendingMedia).go();

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

/// 待传媒体项（离线队列的接口层 DTO：会话层不接触 drift 行类）。
class PendingMediaItem {
  final String localId;
  final String kind; // image | audio
  final int? sec;
  final Uint8List blob; // 已加密（nonce12 ‖ AES-GCM 密文）
  final String cekWrappedB64;

  const PendingMediaItem({
    required this.localId,
    required this.kind,
    required this.blob,
    required this.cekWrappedB64,
    this.sec,
  });
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
  Future<void> deleteEntryHard(String localId); // 未上云条目的本地直接清除
  // 离线队列（2026-11-16）：待传媒体 + 注销/换身份清空
  Future<List<PendingMediaItem>> pendingMediaFor(String localId);
  Future<void> insertPendingMedia(PendingMediaItem item);
  Future<void> deletePendingMediaFor(String localId);
  Future<void> clearPendingMedia();
}

/// 内存实现：web 条目缓存基底 / 原生打库失败兜底（本次会话内可用）。
class MemoryLocalStore implements LocalStore {
  final Map<String, String> _kv = {};
  final Map<String, Entry> _entries = {};
  final List<PendingMediaItem> _pendingMedia = [];

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
  Future<void> deleteEntryHard(String localId) async => _entries.remove(localId);

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
      syncState: c.syncState.present ? c.syncState.value : 0,
    );
  }

  @override
  Future<List<PendingMediaItem>> pendingMediaFor(String localId) async =>
      [for (final m in _pendingMedia) if (m.localId == localId) m];

  @override
  Future<void> insertPendingMedia(PendingMediaItem item) async =>
      _pendingMedia.add(item);

  @override
  Future<void> deletePendingMediaFor(String localId) async =>
      _pendingMedia.removeWhere((m) => m.localId == localId);

  @override
  Future<void> clearPendingMedia() async => _pendingMedia.clear();
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
  Future<void> deleteEntryHard(String localId) => _db.deleteEntryHard(localId);

  @override
  Future<List<Entry>> allEntries() => _db.allEntries();

  @override
  Future<void> upsertEntry(EntriesCompanion c) => _db.upsertEntry(c);

  @override
  Future<List<PendingMediaItem>> pendingMediaFor(String localId) async =>
      [
        for (final r in await _db.allPendingMedia())
          if (r.localId == localId)
            PendingMediaItem(
              localId: r.localId,
              kind: r.kind,
              sec: r.sec,
              blob: r.bytes,
              cekWrappedB64: r.cekWrappedB64,
            ),
      ];

  @override
  Future<void> insertPendingMedia(PendingMediaItem item) =>
      _db.insertPendingMedia(PendingMediaCompanion.insert(
        localId: item.localId,
        kind: item.kind,
        bytes: item.blob,
        cekWrappedB64: item.cekWrappedB64,
        sec: item.sec == null ? const Value.absent() : Value(item.sec),
      ));

  @override
  Future<void> deletePendingMediaFor(String localId) =>
      _db.deletePendingMediaFor(localId);

  @override
  Future<void> clearPendingMedia() => _db.clearPendingMedia();
}
