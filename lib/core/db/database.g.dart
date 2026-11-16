// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $EntriesTable extends Entries with TableInfo<$EntriesTable, Entry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<String> entryDate = GeneratedColumn<String>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cipherJsonMeta = const VerificationMeta(
    'cipherJson',
  );
  @override
  late final GeneratedColumn<String> cipherJson = GeneratedColumn<String>(
    'cipher_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<int> syncState = GeneratedColumn<int>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pendingMetaMeta = const VerificationMeta(
    'pendingMeta',
  );
  @override
  late final GeneratedColumn<String> pendingMeta = GeneratedColumn<String>(
    'pending_meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    serverId,
    entryDate,
    payloadJson,
    cipherJson,
    updatedAtMs,
    createdAtMs,
    deleted,
    syncState,
    pendingMeta,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Entry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('cipher_json')) {
      context.handle(
        _cipherJsonMeta,
        cipherJson.isAcceptableOrUnknown(data['cipher_json']!, _cipherJsonMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('pending_meta')) {
      context.handle(
        _pendingMetaMeta,
        pendingMeta.isAcceptableOrUnknown(
          data['pending_meta']!,
          _pendingMetaMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  Entry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Entry(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      ),
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_date'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      cipherJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cipher_json'],
      ),
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_state'],
      )!,
      pendingMeta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_meta'],
      )!,
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class Entry extends DataClass implements Insertable<Entry> {
  final String localId;
  final int? serverId;
  final String entryDate;
  final String payloadJson;
  final String? cipherJson;
  final int updatedAtMs;
  final int createdAtMs;
  final bool deleted;
  final int syncState;
  final String pendingMeta;
  const Entry({
    required this.localId,
    this.serverId,
    required this.entryDate,
    required this.payloadJson,
    this.cipherJson,
    required this.updatedAtMs,
    required this.createdAtMs,
    required this.deleted,
    required this.syncState,
    required this.pendingMeta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['entry_date'] = Variable<String>(entryDate);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || cipherJson != null) {
      map['cipher_json'] = Variable<String>(cipherJson);
    }
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['deleted'] = Variable<bool>(deleted);
    map['sync_state'] = Variable<int>(syncState);
    map['pending_meta'] = Variable<String>(pendingMeta);
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      entryDate: Value(entryDate),
      payloadJson: Value(payloadJson),
      cipherJson: cipherJson == null && nullToAbsent
          ? const Value.absent()
          : Value(cipherJson),
      updatedAtMs: Value(updatedAtMs),
      createdAtMs: Value(createdAtMs),
      deleted: Value(deleted),
      syncState: Value(syncState),
      pendingMeta: Value(pendingMeta),
    );
  }

  factory Entry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Entry(
      localId: serializer.fromJson<String>(json['localId']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      entryDate: serializer.fromJson<String>(json['entryDate']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      cipherJson: serializer.fromJson<String?>(json['cipherJson']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      syncState: serializer.fromJson<int>(json['syncState']),
      pendingMeta: serializer.fromJson<String>(json['pendingMeta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'serverId': serializer.toJson<int?>(serverId),
      'entryDate': serializer.toJson<String>(entryDate),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'cipherJson': serializer.toJson<String?>(cipherJson),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'deleted': serializer.toJson<bool>(deleted),
      'syncState': serializer.toJson<int>(syncState),
      'pendingMeta': serializer.toJson<String>(pendingMeta),
    };
  }

  Entry copyWith({
    String? localId,
    Value<int?> serverId = const Value.absent(),
    String? entryDate,
    String? payloadJson,
    Value<String?> cipherJson = const Value.absent(),
    int? updatedAtMs,
    int? createdAtMs,
    bool? deleted,
    int? syncState,
    String? pendingMeta,
  }) => Entry(
    localId: localId ?? this.localId,
    serverId: serverId.present ? serverId.value : this.serverId,
    entryDate: entryDate ?? this.entryDate,
    payloadJson: payloadJson ?? this.payloadJson,
    cipherJson: cipherJson.present ? cipherJson.value : this.cipherJson,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    deleted: deleted ?? this.deleted,
    syncState: syncState ?? this.syncState,
    pendingMeta: pendingMeta ?? this.pendingMeta,
  );
  Entry copyWithCompanion(EntriesCompanion data) {
    return Entry(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      cipherJson: data.cipherJson.present
          ? data.cipherJson.value
          : this.cipherJson,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      pendingMeta: data.pendingMeta.present
          ? data.pendingMeta.value
          : this.pendingMeta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Entry(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('entryDate: $entryDate, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cipherJson: $cipherJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('deleted: $deleted, ')
          ..write('syncState: $syncState, ')
          ..write('pendingMeta: $pendingMeta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    serverId,
    entryDate,
    payloadJson,
    cipherJson,
    updatedAtMs,
    createdAtMs,
    deleted,
    syncState,
    pendingMeta,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entry &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.entryDate == this.entryDate &&
          other.payloadJson == this.payloadJson &&
          other.cipherJson == this.cipherJson &&
          other.updatedAtMs == this.updatedAtMs &&
          other.createdAtMs == this.createdAtMs &&
          other.deleted == this.deleted &&
          other.syncState == this.syncState &&
          other.pendingMeta == this.pendingMeta);
}

class EntriesCompanion extends UpdateCompanion<Entry> {
  final Value<String> localId;
  final Value<int?> serverId;
  final Value<String> entryDate;
  final Value<String> payloadJson;
  final Value<String?> cipherJson;
  final Value<int> updatedAtMs;
  final Value<int> createdAtMs;
  final Value<bool> deleted;
  final Value<int> syncState;
  final Value<String> pendingMeta;
  final Value<int> rowid;
  const EntriesCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.cipherJson = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.pendingMeta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesCompanion.insert({
    required String localId,
    this.serverId = const Value.absent(),
    required String entryDate,
    required String payloadJson,
    this.cipherJson = const Value.absent(),
    required int updatedAtMs,
    this.createdAtMs = const Value.absent(),
    this.deleted = const Value.absent(),
    this.syncState = const Value.absent(),
    this.pendingMeta = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       entryDate = Value(entryDate),
       payloadJson = Value(payloadJson),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<Entry> custom({
    Expression<String>? localId,
    Expression<int>? serverId,
    Expression<String>? entryDate,
    Expression<String>? payloadJson,
    Expression<String>? cipherJson,
    Expression<int>? updatedAtMs,
    Expression<int>? createdAtMs,
    Expression<bool>? deleted,
    Expression<int>? syncState,
    Expression<String>? pendingMeta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (entryDate != null) 'entry_date': entryDate,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (cipherJson != null) 'cipher_json': cipherJson,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (deleted != null) 'deleted': deleted,
      if (syncState != null) 'sync_state': syncState,
      if (pendingMeta != null) 'pending_meta': pendingMeta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesCompanion copyWith({
    Value<String>? localId,
    Value<int?>? serverId,
    Value<String>? entryDate,
    Value<String>? payloadJson,
    Value<String?>? cipherJson,
    Value<int>? updatedAtMs,
    Value<int>? createdAtMs,
    Value<bool>? deleted,
    Value<int>? syncState,
    Value<String>? pendingMeta,
    Value<int>? rowid,
  }) {
    return EntriesCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      entryDate: entryDate ?? this.entryDate,
      payloadJson: payloadJson ?? this.payloadJson,
      cipherJson: cipherJson ?? this.cipherJson,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      deleted: deleted ?? this.deleted,
      syncState: syncState ?? this.syncState,
      pendingMeta: pendingMeta ?? this.pendingMeta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<String>(entryDate.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (cipherJson.present) {
      map['cipher_json'] = Variable<String>(cipherJson.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<int>(syncState.value);
    }
    if (pendingMeta.present) {
      map['pending_meta'] = Variable<String>(pendingMeta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('entryDate: $entryDate, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('cipherJson: $cipherJson, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('deleted: $deleted, ')
          ..write('syncState: $syncState, ')
          ..write('pendingMeta: $pendingMeta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KvTable extends Kv with TableInfo<$KvTable, KvData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kMeta = const VerificationMeta('k');
  @override
  late final GeneratedColumn<String> k = GeneratedColumn<String>(
    'k',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vMeta = const VerificationMeta('v');
  @override
  late final GeneratedColumn<String> v = GeneratedColumn<String>(
    'v',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [k, v];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('k')) {
      context.handle(_kMeta, k.isAcceptableOrUnknown(data['k']!, _kMeta));
    } else if (isInserting) {
      context.missing(_kMeta);
    }
    if (data.containsKey('v')) {
      context.handle(_vMeta, v.isAcceptableOrUnknown(data['v']!, _vMeta));
    } else if (isInserting) {
      context.missing(_vMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {k};
  @override
  KvData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvData(
      k: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k'],
      )!,
      v: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}v'],
      )!,
    );
  }

  @override
  $KvTable createAlias(String alias) {
    return $KvTable(attachedDatabase, alias);
  }
}

class KvData extends DataClass implements Insertable<KvData> {
  final String k;
  final String v;
  const KvData({required this.k, required this.v});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['k'] = Variable<String>(k);
    map['v'] = Variable<String>(v);
    return map;
  }

  KvCompanion toCompanion(bool nullToAbsent) {
    return KvCompanion(k: Value(k), v: Value(v));
  }

  factory KvData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvData(
      k: serializer.fromJson<String>(json['k']),
      v: serializer.fromJson<String>(json['v']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'k': serializer.toJson<String>(k),
      'v': serializer.toJson<String>(v),
    };
  }

  KvData copyWith({String? k, String? v}) =>
      KvData(k: k ?? this.k, v: v ?? this.v);
  KvData copyWithCompanion(KvCompanion data) {
    return KvData(
      k: data.k.present ? data.k.value : this.k,
      v: data.v.present ? data.v.value : this.v,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvData(')
          ..write('k: $k, ')
          ..write('v: $v')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(k, v);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvData && other.k == this.k && other.v == this.v);
}

class KvCompanion extends UpdateCompanion<KvData> {
  final Value<String> k;
  final Value<String> v;
  final Value<int> rowid;
  const KvCompanion({
    this.k = const Value.absent(),
    this.v = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvCompanion.insert({
    required String k,
    required String v,
    this.rowid = const Value.absent(),
  }) : k = Value(k),
       v = Value(v);
  static Insertable<KvData> custom({
    Expression<String>? k,
    Expression<String>? v,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (k != null) 'k': k,
      if (v != null) 'v': v,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvCompanion copyWith({
    Value<String>? k,
    Value<String>? v,
    Value<int>? rowid,
  }) {
    return KvCompanion(
      k: k ?? this.k,
      v: v ?? this.v,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (k.present) {
      map['k'] = Variable<String>(k.value);
    }
    if (v.present) {
      map['v'] = Variable<String>(v.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvCompanion(')
          ..write('k: $k, ')
          ..write('v: $v, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingMediaTable extends PendingMedia
    with TableInfo<$PendingMediaTable, PendingMediaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingMediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secMeta = const VerificationMeta('sec');
  @override
  late final GeneratedColumn<int> sec = GeneratedColumn<int>(
    'sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cekWrappedB64Meta = const VerificationMeta(
    'cekWrappedB64',
  );
  @override
  late final GeneratedColumn<String> cekWrappedB64 = GeneratedColumn<String>(
    'cek_wrapped_b64',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localId,
    kind,
    sec,
    bytes,
    cekWrappedB64,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_media';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingMediaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('sec')) {
      context.handle(
        _secMeta,
        sec.isAcceptableOrUnknown(data['sec']!, _secMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('cek_wrapped_b64')) {
      context.handle(
        _cekWrappedB64Meta,
        cekWrappedB64.isAcceptableOrUnknown(
          data['cek_wrapped_b64']!,
          _cekWrappedB64Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cekWrappedB64Meta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingMediaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingMediaData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sec'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      cekWrappedB64: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cek_wrapped_b64'],
      )!,
    );
  }

  @override
  $PendingMediaTable createAlias(String alias) {
    return $PendingMediaTable(attachedDatabase, alias);
  }
}

class PendingMediaData extends DataClass
    implements Insertable<PendingMediaData> {
  final int id;
  final String localId;
  final String kind;
  final int? sec;
  final Uint8List bytes;
  final String cekWrappedB64;
  const PendingMediaData({
    required this.id,
    required this.localId,
    required this.kind,
    this.sec,
    required this.bytes,
    required this.cekWrappedB64,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_id'] = Variable<String>(localId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || sec != null) {
      map['sec'] = Variable<int>(sec);
    }
    map['bytes'] = Variable<Uint8List>(bytes);
    map['cek_wrapped_b64'] = Variable<String>(cekWrappedB64);
    return map;
  }

  PendingMediaCompanion toCompanion(bool nullToAbsent) {
    return PendingMediaCompanion(
      id: Value(id),
      localId: Value(localId),
      kind: Value(kind),
      sec: sec == null && nullToAbsent ? const Value.absent() : Value(sec),
      bytes: Value(bytes),
      cekWrappedB64: Value(cekWrappedB64),
    );
  }

  factory PendingMediaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingMediaData(
      id: serializer.fromJson<int>(json['id']),
      localId: serializer.fromJson<String>(json['localId']),
      kind: serializer.fromJson<String>(json['kind']),
      sec: serializer.fromJson<int?>(json['sec']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      cekWrappedB64: serializer.fromJson<String>(json['cekWrappedB64']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localId': serializer.toJson<String>(localId),
      'kind': serializer.toJson<String>(kind),
      'sec': serializer.toJson<int?>(sec),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'cekWrappedB64': serializer.toJson<String>(cekWrappedB64),
    };
  }

  PendingMediaData copyWith({
    int? id,
    String? localId,
    String? kind,
    Value<int?> sec = const Value.absent(),
    Uint8List? bytes,
    String? cekWrappedB64,
  }) => PendingMediaData(
    id: id ?? this.id,
    localId: localId ?? this.localId,
    kind: kind ?? this.kind,
    sec: sec.present ? sec.value : this.sec,
    bytes: bytes ?? this.bytes,
    cekWrappedB64: cekWrappedB64 ?? this.cekWrappedB64,
  );
  PendingMediaData copyWithCompanion(PendingMediaCompanion data) {
    return PendingMediaData(
      id: data.id.present ? data.id.value : this.id,
      localId: data.localId.present ? data.localId.value : this.localId,
      kind: data.kind.present ? data.kind.value : this.kind,
      sec: data.sec.present ? data.sec.value : this.sec,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      cekWrappedB64: data.cekWrappedB64.present
          ? data.cekWrappedB64.value
          : this.cekWrappedB64,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingMediaData(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('kind: $kind, ')
          ..write('sec: $sec, ')
          ..write('bytes: $bytes, ')
          ..write('cekWrappedB64: $cekWrappedB64')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    localId,
    kind,
    sec,
    $driftBlobEquality.hash(bytes),
    cekWrappedB64,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingMediaData &&
          other.id == this.id &&
          other.localId == this.localId &&
          other.kind == this.kind &&
          other.sec == this.sec &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.cekWrappedB64 == this.cekWrappedB64);
}

class PendingMediaCompanion extends UpdateCompanion<PendingMediaData> {
  final Value<int> id;
  final Value<String> localId;
  final Value<String> kind;
  final Value<int?> sec;
  final Value<Uint8List> bytes;
  final Value<String> cekWrappedB64;
  const PendingMediaCompanion({
    this.id = const Value.absent(),
    this.localId = const Value.absent(),
    this.kind = const Value.absent(),
    this.sec = const Value.absent(),
    this.bytes = const Value.absent(),
    this.cekWrappedB64 = const Value.absent(),
  });
  PendingMediaCompanion.insert({
    this.id = const Value.absent(),
    required String localId,
    required String kind,
    this.sec = const Value.absent(),
    required Uint8List bytes,
    required String cekWrappedB64,
  }) : localId = Value(localId),
       kind = Value(kind),
       bytes = Value(bytes),
       cekWrappedB64 = Value(cekWrappedB64);
  static Insertable<PendingMediaData> custom({
    Expression<int>? id,
    Expression<String>? localId,
    Expression<String>? kind,
    Expression<int>? sec,
    Expression<Uint8List>? bytes,
    Expression<String>? cekWrappedB64,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localId != null) 'local_id': localId,
      if (kind != null) 'kind': kind,
      if (sec != null) 'sec': sec,
      if (bytes != null) 'bytes': bytes,
      if (cekWrappedB64 != null) 'cek_wrapped_b64': cekWrappedB64,
    });
  }

  PendingMediaCompanion copyWith({
    Value<int>? id,
    Value<String>? localId,
    Value<String>? kind,
    Value<int?>? sec,
    Value<Uint8List>? bytes,
    Value<String>? cekWrappedB64,
  }) {
    return PendingMediaCompanion(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      kind: kind ?? this.kind,
      sec: sec ?? this.sec,
      bytes: bytes ?? this.bytes,
      cekWrappedB64: cekWrappedB64 ?? this.cekWrappedB64,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sec.present) {
      map['sec'] = Variable<int>(sec.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (cekWrappedB64.present) {
      map['cek_wrapped_b64'] = Variable<String>(cekWrappedB64.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingMediaCompanion(')
          ..write('id: $id, ')
          ..write('localId: $localId, ')
          ..write('kind: $kind, ')
          ..write('sec: $sec, ')
          ..write('bytes: $bytes, ')
          ..write('cekWrappedB64: $cekWrappedB64')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $EntriesTable entries = $EntriesTable(this);
  late final $KvTable kv = $KvTable(this);
  late final $PendingMediaTable pendingMedia = $PendingMediaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    entries,
    kv,
    pendingMedia,
  ];
}

typedef $$EntriesTableCreateCompanionBuilder =
    EntriesCompanion Function({
      required String localId,
      Value<int?> serverId,
      required String entryDate,
      required String payloadJson,
      Value<String?> cipherJson,
      required int updatedAtMs,
      Value<int> createdAtMs,
      Value<bool> deleted,
      Value<int> syncState,
      Value<String> pendingMeta,
      Value<int> rowid,
    });
typedef $$EntriesTableUpdateCompanionBuilder =
    EntriesCompanion Function({
      Value<String> localId,
      Value<int?> serverId,
      Value<String> entryDate,
      Value<String> payloadJson,
      Value<String?> cipherJson,
      Value<int> updatedAtMs,
      Value<int> createdAtMs,
      Value<bool> deleted,
      Value<int> syncState,
      Value<String> pendingMeta,
      Value<int> rowid,
    });

class $$EntriesTableFilterComposer extends Composer<_$AppDb, $EntriesTable> {
  $$EntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cipherJson => $composableBuilder(
    column: $table.cipherJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingMeta => $composableBuilder(
    column: $table.pendingMeta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntriesTableOrderingComposer extends Composer<_$AppDb, $EntriesTable> {
  $$EntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cipherJson => $composableBuilder(
    column: $table.cipherJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingMeta => $composableBuilder(
    column: $table.pendingMeta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$AppDb, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cipherJson => $composableBuilder(
    column: $table.cipherJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get pendingMeta => $composableBuilder(
    column: $table.pendingMeta,
    builder: (column) => column,
  );
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $EntriesTable,
          Entry,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (Entry, BaseReferences<_$AppDb, $EntriesTable, Entry>),
          Entry,
          PrefetchHooks Function()
        > {
  $$EntriesTableTableManager(_$AppDb db, $EntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<int?> serverId = const Value.absent(),
                Value<String> entryDate = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> cipherJson = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<String> pendingMeta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion(
                localId: localId,
                serverId: serverId,
                entryDate: entryDate,
                payloadJson: payloadJson,
                cipherJson: cipherJson,
                updatedAtMs: updatedAtMs,
                createdAtMs: createdAtMs,
                deleted: deleted,
                syncState: syncState,
                pendingMeta: pendingMeta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                Value<int?> serverId = const Value.absent(),
                required String entryDate,
                required String payloadJson,
                Value<String?> cipherJson = const Value.absent(),
                required int updatedAtMs,
                Value<int> createdAtMs = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> syncState = const Value.absent(),
                Value<String> pendingMeta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion.insert(
                localId: localId,
                serverId: serverId,
                entryDate: entryDate,
                payloadJson: payloadJson,
                cipherJson: cipherJson,
                updatedAtMs: updatedAtMs,
                createdAtMs: createdAtMs,
                deleted: deleted,
                syncState: syncState,
                pendingMeta: pendingMeta,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntriesTable, Entry>(table),
                  BaseReferences<_$AppDb, $EntriesTable, Entry>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $EntriesTable,
      Entry,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (Entry, BaseReferences<_$AppDb, $EntriesTable, Entry>),
      Entry,
      PrefetchHooks Function()
    >;
typedef $$KvTableCreateCompanionBuilder =
    KvCompanion Function({
      required String k,
      required String v,
      Value<int> rowid,
    });
typedef $$KvTableUpdateCompanionBuilder =
    KvCompanion Function({Value<String> k, Value<String> v, Value<int> rowid});

class $$KvTableFilterComposer extends Composer<_$AppDb, $KvTable> {
  $$KvTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvTableOrderingComposer extends Composer<_$AppDb, $KvTable> {
  $$KvTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvTableAnnotationComposer extends Composer<_$AppDb, $KvTable> {
  $$KvTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get k =>
      $composableBuilder(column: $table.k, builder: (column) => column);

  GeneratedColumn<String> get v =>
      $composableBuilder(column: $table.v, builder: (column) => column);
}

class $$KvTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $KvTable,
          KvData,
          $$KvTableFilterComposer,
          $$KvTableOrderingComposer,
          $$KvTableAnnotationComposer,
          $$KvTableCreateCompanionBuilder,
          $$KvTableUpdateCompanionBuilder,
          (KvData, BaseReferences<_$AppDb, $KvTable, KvData>),
          KvData,
          PrefetchHooks Function()
        > {
  $$KvTableTableManager(_$AppDb db, $KvTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> k = const Value.absent(),
                Value<String> v = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvCompanion(k: k, v: v, rowid: rowid),
          createCompanionCallback:
              ({
                required String k,
                required String v,
                Value<int> rowid = const Value.absent(),
              }) => KvCompanion.insert(k: k, v: v, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KvTable, KvData>(table),
                  BaseReferences<_$AppDb, $KvTable, KvData>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $KvTable,
      KvData,
      $$KvTableFilterComposer,
      $$KvTableOrderingComposer,
      $$KvTableAnnotationComposer,
      $$KvTableCreateCompanionBuilder,
      $$KvTableUpdateCompanionBuilder,
      (KvData, BaseReferences<_$AppDb, $KvTable, KvData>),
      KvData,
      PrefetchHooks Function()
    >;
typedef $$PendingMediaTableCreateCompanionBuilder =
    PendingMediaCompanion Function({
      Value<int> id,
      required String localId,
      required String kind,
      Value<int?> sec,
      required Uint8List bytes,
      required String cekWrappedB64,
    });
typedef $$PendingMediaTableUpdateCompanionBuilder =
    PendingMediaCompanion Function({
      Value<int> id,
      Value<String> localId,
      Value<String> kind,
      Value<int?> sec,
      Value<Uint8List> bytes,
      Value<String> cekWrappedB64,
    });

class $$PendingMediaTableFilterComposer
    extends Composer<_$AppDb, $PendingMediaTable> {
  $$PendingMediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sec => $composableBuilder(
    column: $table.sec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cekWrappedB64 => $composableBuilder(
    column: $table.cekWrappedB64,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingMediaTableOrderingComposer
    extends Composer<_$AppDb, $PendingMediaTable> {
  $$PendingMediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sec => $composableBuilder(
    column: $table.sec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cekWrappedB64 => $composableBuilder(
    column: $table.cekWrappedB64,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingMediaTableAnnotationComposer
    extends Composer<_$AppDb, $PendingMediaTable> {
  $$PendingMediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get sec =>
      $composableBuilder(column: $table.sec, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get cekWrappedB64 => $composableBuilder(
    column: $table.cekWrappedB64,
    builder: (column) => column,
  );
}

class $$PendingMediaTableTableManager
    extends
        RootTableManager<
          _$AppDb,
          $PendingMediaTable,
          PendingMediaData,
          $$PendingMediaTableFilterComposer,
          $$PendingMediaTableOrderingComposer,
          $$PendingMediaTableAnnotationComposer,
          $$PendingMediaTableCreateCompanionBuilder,
          $$PendingMediaTableUpdateCompanionBuilder,
          (
            PendingMediaData,
            BaseReferences<_$AppDb, $PendingMediaTable, PendingMediaData>,
          ),
          PendingMediaData,
          PrefetchHooks Function()
        > {
  $$PendingMediaTableTableManager(_$AppDb db, $PendingMediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingMediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingMediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingMediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int?> sec = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<String> cekWrappedB64 = const Value.absent(),
              }) => PendingMediaCompanion(
                id: id,
                localId: localId,
                kind: kind,
                sec: sec,
                bytes: bytes,
                cekWrappedB64: cekWrappedB64,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localId,
                required String kind,
                Value<int?> sec = const Value.absent(),
                required Uint8List bytes,
                required String cekWrappedB64,
              }) => PendingMediaCompanion.insert(
                id: id,
                localId: localId,
                kind: kind,
                sec: sec,
                bytes: bytes,
                cekWrappedB64: cekWrappedB64,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingMediaTable, PendingMediaData>(table),
                  BaseReferences<_$AppDb, $PendingMediaTable, PendingMediaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingMediaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDb,
      $PendingMediaTable,
      PendingMediaData,
      $$PendingMediaTableFilterComposer,
      $$PendingMediaTableOrderingComposer,
      $$PendingMediaTableAnnotationComposer,
      $$PendingMediaTableCreateCompanionBuilder,
      $$PendingMediaTableUpdateCompanionBuilder,
      (
        PendingMediaData,
        BaseReferences<_$AppDb, $PendingMediaTable, PendingMediaData>,
      ),
      PendingMediaData,
      PrefetchHooks Function()
    >;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
  $$KvTableTableManager get kv => $$KvTableTableManager(_db, _db.kv);
  $$PendingMediaTableTableManager get pendingMedia =>
      $$PendingMediaTableTableManager(_db, _db.pendingMedia);
}
