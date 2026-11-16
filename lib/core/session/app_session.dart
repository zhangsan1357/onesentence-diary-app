// 应用会话（Riverpod）：身份门（首次生成/新设备登录/补设注册名）、锁定门、加密发布、同步、配置。
// 身份模型（2026-11-14 后端演进）：12 恢复词（或派生密钥）+ 注册名；deviceNo 每设备随机；
// 动态口令 X-Diary-Pass 由密钥本地推算（kdf.diaryPass），401 口令类错误由 ApiClient 透明重试。
// 模式选择：不区分构建环境——仅测试环境（FLUTTER_TEST）用演示数据；
// 服务端地址在「我的 → 服务端地址」运行时配置（默认本机 9060），所有接口拼接此地址。
import 'dart:async';
import 'dart:convert';


import 'package:dio/dio.dart' show DioException;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

import '../config/app_defaults.dart';
import '../db/database.dart' as db;
import '../e2ee/bytes.dart';
import '../e2ee/envelope.dart';
import '../e2ee/kdf.dart';
import '../holiday/holiday.dart';
import '../notify/notification_service.dart';
import '../model/diary_entry.dart';
import '../repo/demo_data.dart';
import '../util/avatar_pool.dart';
import '../util/dates.dart';
import 'bio_vault.dart';
import 'crypto_session.dart';
import 'env_check.dart';
import 'recovery_words.dart';

/// 外观三档（01 §2.4）。
enum ThemeSetting { auto, light, dark }

/// 发布输入的媒体字节。
class MediaInput {
  final String kind; // image | audio
  final Uint8List bytes;
  final int? sec;
  const MediaInput({required this.kind, required this.bytes, this.sec});
}

/// 标签/心情显示配置（设备本地 KV，注销账号一并清除）。
/// cfg.tagDeleted = 本地删除名单（契约无标签删除端点，防拉取复活，§4.1）。
const cfgKvKeys = [
  'cfg.tagColor',
  'cfg.tagPreset',
  'cfg.moodOver',
  'cfg.moodCustom',
  'cfg.tagDeleted',
];

class AppState {
  final bool ready; // 初始化完成
  final bool hasKeystore;
  final bool locked;
  final bool lockEnabled; // 锁定保护开关（关闭 = 免口令直进，调试友好）
  final bool demo; // 演示数据模式
  final List<DiaryEntry> entries;
  final MonthHolidays? holidays;
  final ThemeSetting theme;
  final int autoLockMin; // 0=关闭
  final bool notifyEnabled;
  final DateTime? highlightDate; // 日历跳转/新发布高亮（仅日期数字变色）
  final String? toast; // 一次性提示（UI 消费后清除）
  final String? serverStatus; // 后端状态描述（设置页显示）
  final String serverBase; // 服务端地址（客户端配置，所有接口拼接）
  final bool needsOnboarding; // 首次启动 · 生成身份（①）——无 keystore 时引导
  final bool needsName; // 存量 keystore 补设注册名（一次性）
  final bool needsPass; // 身份建立后的锁定口令引导（2026-11-15 P0 默认安全基线）
  final String userId; // 注册名（终身不变，多设备共用）
  final String? syncError; // 最近一次同步失败（401 横幅/重试入口；null=正常）
  final bool bioUnlock; // 面容 ID 解锁（私钥存生物识别保护的钥匙串）
  final int cfgVersion; // 标签/心情显示配置版本（变更自增，驱动 UI 重建）
  final int pendingCount; // 离线队列长度（云端不可达时本地暂存的增删改条数）
  final int dataRev; // 同步代次（syncNow 成功自增；驱动一次性 UI 动作如收起评论，晨 17）

  const AppState({
    this.ready = false,
    this.hasKeystore = false,
    this.locked = true,
    this.lockEnabled = false,
    this.demo = false,
    this.entries = const [],
    this.holidays,
    this.theme = ThemeSetting.auto,
    this.autoLockMin = 1,
    this.notifyEnabled = false,
    this.highlightDate,
    this.toast,
    this.serverStatus,
    this.serverBase = apiBase,
    this.needsOnboarding = false,
    this.needsName = false,
    this.needsPass = false,
    this.userId = '',
    this.syncError,
    this.bioUnlock = false,
    this.cfgVersion = 0,
    this.pendingCount = 0,
    this.dataRev = 0,
  });

  bool get unlocked => ready && !locked;

  AppState copyWith({
    bool? ready,
    bool? hasKeystore,
    bool? locked,
    bool? lockEnabled,
    bool? demo,
    List<DiaryEntry>? entries,
    MonthHolidays? holidays,
    ThemeSetting? theme,
    int? autoLockMin,
    bool? notifyEnabled,
    DateTime? highlightDate,
    String? toast,
    String? serverStatus,
    String? serverBase,
    bool? needsOnboarding,
    bool? needsName,
    bool? needsPass,
    String? userId,
    String? syncError,
    bool clearHighlight = false,
    bool clearToast = false,
    bool clearSyncError = false,
    bool? bioUnlock,
    int? cfgVersion,
    int? pendingCount,
    int? dataRev,
  }) =>
      AppState(
        ready: ready ?? this.ready,
        hasKeystore: hasKeystore ?? this.hasKeystore,
        locked: locked ?? this.locked,
        lockEnabled: lockEnabled ?? this.lockEnabled,
        demo: demo ?? this.demo,
        entries: entries ?? this.entries,
        holidays: holidays ?? this.holidays,
        theme: theme ?? this.theme,
        autoLockMin: autoLockMin ?? this.autoLockMin,
        notifyEnabled: notifyEnabled ?? this.notifyEnabled,
        highlightDate:
            clearHighlight ? null : (highlightDate ?? this.highlightDate),
        toast: clearToast ? null : (toast ?? this.toast),
        serverStatus: serverStatus ?? this.serverStatus,
        serverBase: serverBase ?? this.serverBase,
        needsOnboarding: needsOnboarding ?? this.needsOnboarding,
        needsName: needsName ?? this.needsName,
        needsPass: needsPass ?? this.needsPass,
        userId: userId ?? this.userId,
        syncError: clearSyncError ? null : (syncError ?? this.syncError),
        bioUnlock: bioUnlock ?? this.bioUnlock,
        cfgVersion: cfgVersion ?? this.cfgVersion,
        pendingCount: pendingCount ?? this.pendingCount,
        dataRev: dataRev ?? this.dataRev,
      );
}

class AppSession extends Notifier<AppState> {
  db.LocalStore? _db;
  UnlockedSession? _session;
  ApiClient _api = ApiClient();
  bool _demo = false;
  bool _flushing = false; // 冲正在途标志（§2.4 并发保护：后台触发与手动刷新互斥）
  // 后端头像链接（EntryVO.avatar）按 localId 挂内存——客户端只消费不拼装。
  // 每次同步覆盖更新（后端现生成、每次不同）：用户拍板「刷新后新头像，有新鲜感」
  //（2026-11-15），故不持久化——重启/刷新后占位，同步完成即换新。
  final _avatars = <String, String>{};

  /// 面容 ID 解锁桥（测试注入假实现）。
  @visibleForTesting
  BioVault bio = BioVaultImpl();

  @override
  AppState build() => const AppState();

  /// 模式选择：不区分环境，仅测试环境（flutter test 注入 FLUTTER_TEST）用演示数据。
  bool _resolveDemo() => isTestEnv();

  /// 测试注入本地存储（身份流程单测用，绕过 init 的平台分支与演示模式）。
  @visibleForTesting
  Future<void> debugUseStore(db.LocalStore store) async {
    _db = store;
    _demo = false;
  }

  /// 测试注入 API 客户端（离线队列单测用：假实现模拟云端不可达/恢复）。
  @visibleForTesting
  void debugUseApi(ApiClient api) => _api = api;

  /// 测试钩子：按 init 明文分支从 KV 重建会话（存量身份流程单测用）。
  @visibleForTesting
  Future<void> debugRestorePlainSession() async {
    final kv = await _db!.kvAll();
    final ks = readKeystore((k) => kv[k]);
    if (ks == null || ks.wrapNonceB64.isNotEmpty) return;
    final session = sessionFromPlain(ks);
    _session = session;
    _api.otpKey = ks.publicKeyHex;
    state = state.copyWith(
      ready: true,
      hasKeystore: true,
      demo: false,
      lockEnabled: false,
      locked: false,
      userId: ks.userId,
      needsName: ks.userId.isEmpty,
    );
  }

  /// 测试钩子：从密文重建内存条目索引（P1-3/P1-4 安全单测用）。
  @visibleForTesting
  Future<void> debugReloadEntries() => _loadLocalEntries();

  Future<void> init() async {
    if (state.ready) return;
    _demo = _resolveDemo();

    // 头像池后台静默填充（晨 18 §2.7 v4）：无需身份、公开素材，锁屏下也可填；
    // 失败静默（渲染回落接口链路），不阻塞初始化。
    unawaited(ref.read(avatarPoolProvider).start());

    // 同步先用内置种子设置调休（asset/服务端随后异步覆盖），保证首帧数据完整
    final seedHolidays =
        MonthHolidays(builtin2026Seed.map(Holiday.fromJson).toList());

    if (_demo) {
      state = state.copyWith(
        ready: true,
        demo: true,
        locked: false,
        hasKeystore: true,
        entries: demoEntries,
        holidays: seedHolidays,
        serverStatus: '演示数据（Chrome 视觉迭代）',
      );
      unawaited(_loadHolidays());
      return;
    }

    try {
      _db = await db.openLocalStore().timeout(const Duration(seconds: 3));
    } catch (e) {
      // 本地库不可用（含打开超时）：回落内存存储 + 演示数据，保可用性
      _db = db.MemoryLocalStore();
      _demo = true;
      state = state.copyWith(
        ready: true,
        demo: true,
        locked: false,
        hasKeystore: true,
        entries: demoEntries,
        serverStatus: '本地库不可用，演示数据（$e）',
      );
      unawaited(_loadHolidays());
      return;
    }
    final kv = await _db!.kvAll();
    _loadCfg(kv); // 标签/心情显示配置（设备本地，覆盖静态表）
    final customBase = kv['api.base'];
    if (customBase != null && customBase.isNotEmpty) {
      _api.setBase(customBase);
    }
    final lockEnabled = kv['ui.lock'] == '1';
    final bioUnlock = kv['ui.bio'] == '1';
    final ks = readKeystore((k) => kv[k]);

    if (ks == null) {
      // 本机无身份 → 首次启动 · 生成身份（①，UI 走 OnboardingPage）
      state = state.copyWith(
        ready: true,
        hasKeystore: false,
        demo: false,
        lockEnabled: lockEnabled,
        needsOnboarding: true,
        theme: _themeOf(kv['ui.theme']),
        autoLockMin: int.tryParse(kv['ui.autoLock'] ?? '') ?? 1,
        notifyEnabled: kv['ui.notify'] == '1',
        serverBase: _api.base,
        serverStatus: lockEnabled ? '完成身份生成后需设置口令' : null,
      );
      unawaited(_loadHolidays());
      return;
    }

    // 有 keystore：注册名缺失（旧版身份）→ 一次性补设注册名引导
    final needsName = ks.userId.isEmpty;

    if (lockEnabled) {
      // 锁定保护开启：维持口令门
      state = state.copyWith(
        ready: true,
        hasKeystore: true,
        demo: false,
        lockEnabled: true,
        bioUnlock: bioUnlock,
        userId: ks.userId,
        needsName: needsName,
        theme: _themeOf(kv['ui.theme']),
        autoLockMin: int.tryParse(kv['ui.autoLock'] ?? '') ?? 1,
        notifyEnabled: kv['ui.notify'] == '1',
        serverBase: _api.base,
      );
      unawaited(_loadHolidays());
    } else if (ks.wrapNonceB64.isNotEmpty) {
      // 锁定已关但残留口令 keystore：需最后一次口令解锁以迁移为明文（unlock 内转换）
      state = state.copyWith(
        ready: true,
        hasKeystore: true,
        demo: false,
        lockEnabled: false,
        bioUnlock: bioUnlock,
        userId: ks.userId,
        needsName: needsName,
        theme: _themeOf(kv['ui.theme']),
        autoLockMin: int.tryParse(kv['ui.autoLock'] ?? '') ?? 1,
        notifyEnabled: kv['ui.notify'] == '1',
        serverBase: _api.base,
        serverStatus: '输入一次口令迁移为免口令模式',
      );
      unawaited(_loadHolidays());
    } else {
      // 明文 keystore：免口令直进（无 Argon2id，启动瞬时）
      final session = sessionFromPlain(ks);
      _session = session;
      _api.otpKey = ks.publicKeyHex;
      state = state.copyWith(
        ready: true,
        hasKeystore: true,
        demo: false,
        lockEnabled: false,
        bioUnlock: bioUnlock,
        locked: false,
        userId: ks.userId,
        needsName: needsName,
        theme: _themeOf(kv['ui.theme']),
        autoLockMin: int.tryParse(kv['ui.autoLock'] ?? '') ?? 1,
        notifyEnabled: kv['ui.notify'] == '1',
        serverBase: _api.base,
      );
      unawaited(_loadHolidays());
      unawaited(_registerAndSync());
    }
  }

  Future<void> _loadHolidays() async {
    final year = DateTime.now().year;
    // 内置：优先读 asset（每年加一个 JSON 文件即可），缺失回落种子常量
    List<Holiday> builtin;
    try {
      builtin = await loadBuiltinHolidays(year)
          .timeout(const Duration(seconds: 2));
      if (builtin.isEmpty) {
        builtin = builtin2026Seed.map(Holiday.fromJson).toList();
      }
    } catch (_) {
      builtin = builtin2026Seed.map(Holiday.fromJson).toList();
    }
    List<Holiday> server = [];
    if (!_demo && _db != null) {
      try {
        final raw = await _api.holidays(year);
        server = raw.map(Holiday.fromJson).toList();
      } on ApiException catch (e) {
        if (e.code == 401) {
          try {
            await _ensureRegistered();
            final raw = await _api.holidays(year);
            server = raw.map(Holiday.fromJson).toList();
          } catch (_) {}
        }
      } catch (_) {}
    }
    // 异步间隙后容器可能已释放（测试收尾/热重载）：不再回写状态
    if (!ref.mounted) return;
    state = state.copyWith(holidays: MonthHolidays(mergeHolidays(builtin, server)));
  }

  ThemeSetting _themeOf(String? s) => switch (s) {
        'light' => ThemeSetting.light,
        'dark' => ThemeSetting.dark,
        _ => ThemeSetting.auto,
      };

  // ---------- 锁定门 ----------
  Future<void> unlock(String passcode) async {
    final kv = await _db!.kvAll();
    final ks = readKeystore((k) => kv[k]);
    if (ks == null) {
      throw StateError('本机无身份，请先完成首次开通（生成身份）');
    }
    final session = await unlockKeystore(ks, passcode);
    _session = session;
    _api.otpKey = ks.publicKeyHex;
    state = state.copyWith(locked: false);
    if (!state.lockEnabled && ks.wrapNonceB64.isNotEmpty) {
      // 一次性迁移：口令 keystore → 明文（此后免口令直进）
      await _persistKeystore(plainFromSession(session));
    }
    await _loadLocalEntries();
    await _ensureRegistered();
    await syncNow();
  }

  void lock() {
    if (!state.lockEnabled) return; // 锁定保护关闭：不锁
    _session = null;
    _avatars.clear();
    // 清空内存明文（P1-4 纵深防御）：解锁后 _loadLocalEntries 从密文重建
    state = state.copyWith(locked: true, entries: const []);
  }

  /// 后台路径的状态回写：异步间隙后容器可能已释放（测试收尾/热重载）→ 静默丢弃。
  void _set(AppState Function(AppState) update) {
    if (ref.mounted) {
      state = update(state);
    }
  }

  Future<void> _registerAndSync() async {
    try {
      await _loadLocalEntries();
      await _ensureRegistered();
      await syncNow();
    } catch (e) {
      // 后台自举失败不阻塞 UI：错误进同步横幅（syncError），可重试
      _set((s) => s.copyWith(syncError: e is ApiException ? e.message : '$e'));
    }
  }

  /// 首次启动 · 生成身份（①）：12 恢复词 + 注册名 → 本机 keystore（明文，锁定开关
  /// 默认关闭）→ 注册 + 同步。恢复词校验失败抛 FormatException。
  Future<void> createIdentity(String wordsPhrase, String userId) async {
    final name = _checkUserId(userId);
    RecoveryWords.validate(wordsPhrase); // 抛 FormatException → UI 内联展示
    final session = await sessionFromIdentity(wordsPhrase, userId: name);
    _session = session;
    _api.otpKey = session.keystore.publicKeyHex;
    await _persistKeystore(session.keystore);
    state = state.copyWith(
      ready: true,
      hasKeystore: true,
      needsOnboarding: false,
      needsName: false,
      needsPass: true, // 锁定口令引导（默认安全基线，2026-11-15 P0）
      userId: name,
      locked: false,
      entries: [],
      clearSyncError: true,
      toast: '身份已创建 · 端到端加密已开启',
    );
    unawaited(_loadHolidays());
    unawaited(_registerAndSync());
  }

  /// 新设备登录（②）：同一注册名 + 同一份恢复词（或派生密钥）→ 本机重建身份 →
  /// 注册（服务端校验身份二元组）+ 全量同步并本地解密。
  /// 失败（词校验不过 / 服务端拒绝）抛异常给 UI 内联展示。
  Future<void> loginIdentity(String userId, String text,
      {String passcode = ''}) async {
    final name = _checkUserId(userId);
    if (text.trim().isEmpty) {
      throw const FormatException('请输入恢复词或派生密钥');
    }
    final session = await sessionFromIdentity(text, userId: name);
    KeystoreData ks = plainFromSession(session);
    if (state.lockEnabled) {
      if (passcode.length < 6) {
        throw ArgumentError('口令不足 6 位');
      }
      final salt = randomBytes(16);
      final master = await argon2idKey(passcode, salt);
      final nonce = randomBytes(12);
      final wrapped = await aesGcmEncrypt(master, nonce, session.privateKey);
      ks = KeystoreData(
        saltB64: b64Encode(salt),
        wrappedPrivB64: b64Encode(wrapped),
        wrapNonceB64: b64Encode(nonce),
        publicKeyHex: session.keystore.publicKeyHex,
        deviceNo: session.keystore.deviceNo,
        userId: name,
        recoveryCode: session.keystore.recoveryCode,
      );
    }
    _session = UnlockedSession(
      keystore: ks,
      privateKey: session.privateKey,
      publicKey: session.publicKey,
    );
    _api.otpKey = ks.publicKeyHex;
    await _persistKeystore(ks);
    await _db!.clearEntries(); // 旧身份的本地索引作废
    await _db!.clearPendingMedia(); // 旧身份的离线队列一并作废
    await _db!.clearDrafts(); // 旧身份的输入草稿一并作废（§4.12）
    await _db!.kvRemove('sync.cursor');
    await _db!.kvRemove('api.token');
    state = state.copyWith(
      ready: true,
      hasKeystore: true,
      needsOnboarding: false,
      needsName: false,
      needsPass: !state.lockEnabled, // 新设备引导设口令；本机已开锁定则不重复引导
      userId: name,
      locked: false,
      entries: [],
      pendingCount: 0, // 旧身份队列已清
      clearSyncError: true,
      toast: '身份已登录 · 同步中',
    );
    unawaited(_loadHolidays());
    await _ensureRegistered(); // 服务端校验身份二元组（同 userId 必须同 userKey）
    await syncNow();
  }

  /// 存量 keystore 一次性补设注册名（终身使用，不可更改）。
  Future<void> setName(String userId) async {
    final s = _session;
    if (s == null) return;
    final name = _checkUserId(userId);
    final newKs = KeystoreData(
      saltB64: s.keystore.saltB64,
      wrappedPrivB64: s.keystore.wrappedPrivB64,
      wrapNonceB64: s.keystore.wrapNonceB64,
      publicKeyHex: s.keystore.publicKeyHex,
      deviceNo: s.keystore.deviceNo,
      userId: name,
      recoveryCode: s.keystore.recoveryCode,
    );
    _session = UnlockedSession(
      keystore: newKs,
      privateKey: s.privateKey,
      publicKey: s.publicKey,
    );
    await _persistKeystore(newKs);
    state = state.copyWith(
      needsName: false,
      needsPass: !state.lockEnabled, // 存量身份补设注册名后同样引导设口令
      userId: name,
      clearSyncError: true,
      toast: '注册名已设置 · 同步中',
    );
    unawaited(_registerAndSync());
  }

  /// 锁定口令引导完成（开了锁定或跳过）：进入主界面。
  /// 开启锁定本身由 PassSetupPage 调 setLockEnabled 完成。
  void finishPassSetup() {
    _set((s) => s.copyWith(needsPass: false));
  }

  /// 注销账号（本机）：清除 keystore/令牌/同步游标/显示配置与本地数据索引，回到生成身份引导。
  /// 服务端密文保留（契约无服务端删除端点）；凭同一注册名 + 12 词恢复词（或派生密钥）
  /// 可重新登录找回。恢复词只显示过一次——UI 侧需二次确认并强提示先妥善保管。
  Future<void> logout() async {
    _session = null;
    _api.token = null;
    _api.otpKey = null;
    AppDefaults.tagColorOverrides = {};
    AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    AppDefaults.moodOverrides = {};
    AppDefaults.customMoods = const [];
    try {
      await bio.deletePriv(); // 面容解锁的钥匙串私钥存档一并清除（平台异常不阻塞注销）
    } catch (_) {}
    final db = _db;
    if (db != null) {
      for (final k in keystoreKvKeys) {
        await db.kvRemove(k);
      }
      for (final k in cfgKvKeys) {
        await db.kvRemove(k);
      }
      _deletedTags.clear();
      await db.clearDrafts(); // 输入草稿随注销一并清除（§4.12）
      await db.kvRemove('ui.bio');
      await db.kvRemove('api.token');
      await db.kvRemove('api.deviceId');
      await db.kvRemove('sync.cursor');
      _avatars.clear();
      await db.clearEntries();
      await db.clearPendingMedia(); // 离线队列（暂存媒体）随注销一并清除
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      hasKeystore: false,
      lockEnabled: false,
      locked: true,
      needsOnboarding: true,
      needsName: false,
      needsPass: false,
      userId: '',
      entries: [],
      pendingCount: 0,
      bioUnlock: false,
      clearSyncError: true,
      clearHighlight: true,
      clearToast: true,
    );
  }

  String _checkUserId(String raw) {
    final name = raw.trim();
    if (name.isEmpty) {
      throw const FormatException('请输入注册名');
    }
    if (name.length > 64) {
      throw const FormatException('注册名最长 64 字');
    }
    return name;
  }

  // ---------- 面容 ID 解锁（私钥存生物识别保护的钥匙串，面容即解锁） ----------

  /// 启用：生物识别确认 → 当前会话私钥存入钥匙串（biometryCurrentSet）。
  /// 需已解锁（锁屏里先口令解锁一次后再到「我的」开启）。
  Future<void> enableBioUnlock() async {
    final s = _session;
    if (s == null) {
      throw StateError('请先解锁后再开启面容解锁');
    }
    if (!await bio.available()) {
      throw const FormatException('本设备无可用面容/生物识别');
    }
    if (!await bio.authenticate('启用面容 ID 解锁你的加密日记')) {
      throw const FormatException('生物识别未通过');
    }
    await bio.savePriv(b64Encode(s.privateKey));
    await _db?.kvSet('ui.bio', '1');
    if (!ref.mounted) return;
    state = state.copyWith(bioUnlock: true, toast: '面容 ID 解锁已开启');
  }

  Future<void> disableBioUnlock() async {
    await bio.deletePriv();
    await _db?.kvSet('ui.bio', '0');
    if (!ref.mounted) return;
    state = state.copyWith(bioUnlock: false, toast: '面容 ID 解锁已关闭');
  }

  /// 面容解锁（LockOverlay 在生物识别通过后调用）：私钥自钥匙串直取。
  /// 无存档（未启用/生物特征集变更失效）抛 StateError('bio-missing') → UI 回退口令。
  Future<void> unlockBiometric() async {
    final kv = await _db!.kvAll();
    final ks = readKeystore((k) => kv[k]);
    if (ks == null) {
      throw StateError('本机无身份');
    }
    final privB64 = await bio.readPriv();
    if (privB64 == null) {
      throw StateError('bio-missing');
    }
    final priv = b64Decode(privB64);
    _session = UnlockedSession(
      keystore: ks,
      privateKey: priv,
      publicKey: hexDecode(ks.publicKeyHex),
    );
    _api.otpKey = ks.publicKeyHex;
    if (!ref.mounted) return;
    state = state.copyWith(locked: false);
    await _loadLocalEntries();
    await _ensureRegistered();
    await syncNow();
  }

  void showToast(String msg) {
    state = state.copyWith(toast: msg);
  }

  /// 同步横幅「重试」：清错误态 → 重注册 + 重同步（失败由 syncNow 重新置错）。
  Future<void> retrySync() async {
    state = state.copyWith(clearSyncError: true);
    try {
      await _ensureRegistered();
      await syncNow();
    } catch (_) {
      // syncNow 已置 syncError（横幅保持显示）
    }
  }

  /// 同步横幅「忽略」：本次不再提示（下次失败会重新出现）。
  void dismissSyncError() => state = state.copyWith(clearSyncError: true);

  /// 锁定保护开关（我的页）。开启需设口令（仅重包裹私钥，数据零重加密）；
  /// 关闭时私钥转明文本机存储，免口令直进。
  Future<void> setLockEnabled(bool on, {String passcode = ''}) async {
    final s = _session;
    if (s == null) return; // 锁定态下设置页不可达
    await _db?.kvSet('ui.lock', on ? '1' : '0');
    if (on) {
      final newKs = await rekeyKeystore(s, passcode);
      await _persistKeystore(newKs);
      _session = UnlockedSession(
        keystore: newKs,
        privateKey: s.privateKey,
        publicKey: s.publicKey,
      );
      state = state.copyWith(lockEnabled: true, toast: '锁定保护已开启');
    } else {
      await _persistKeystore(plainFromSession(s));
      state = state.copyWith(lockEnabled: false, toast: '锁定保护已关闭 · 免口令直进');
    }
  }

  Future<void> rekey(String oldPasscode, String newPasscode) async {
    final s = _session;
    if (s == null) return;
    // 校验旧口令
    final kv = await _db!.kvAll();
    final ks = readKeystore((k) => kv[k])!;
    await unlockKeystore(ks, oldPasscode); // 抛错=旧口令不对
    final newKs = await rekeyKeystore(s, newPasscode);
    await _persistKeystore(newKs);
    state = state.copyWith(toast: '主密钥已更换 · 数据无需重加密');
  }

  Future<void> _persistKeystore(KeystoreData ks) async {
    for (final e in keystoreToKv(ks).entries) {
      await _db!.kvSet(e.key, e.value);
    }
  }

  // ---------- 注册与同步 ----------
  Future<void> _ensureRegistered() async {
    final s = _session;
    if (s == null || _db == null) return;
    if (s.keystore.userId.isEmpty) return; // 未设注册名（引导页流程中）
    final saved = await _db!.kvGet('api.token');
    if (saved != null) {
      _api.token = saved;
      return;
    }
    await _register();
  }

  Future<void> _register() async {
    final s = _session!;
    if (s.keystore.userId.isEmpty) {
      throw StateError('未设置注册名');
    }
    final result = await _api.registerDevice(
      userId: s.keystore.userId,
      deviceNo: s.keystore.deviceNo,
      name: 'iPhone',
      userKeyHex: s.keystore.publicKeyHex,
    );
    _api.token = result.token;
    _api.otpKey = s.keystore.publicKeyHex;
    await _db!.kvSet('api.token', result.token);
    await _db!.kvSet('api.deviceId', '${result.deviceId}');
    _set((s) => s.copyWith(serverStatus: '已注册 · 设备#${result.deviceId}'));
  }

  Future<void> syncNow() async {
    final s = _session;
    if (s == null || _db == null) return;
    try {
      // 先冲正离线队列（云端不可达时本地暂存的增删改），再全量拉取——
      // 手动刷新（下拉/解锁/横幅重试）是遗留队列的续传时机（2026-11-16 用户拍板：
      // 不加定时自动重试）；写路径本地先行后每次写还有一次后台冲正（§2.3）。
      await flushNow();
      await _syncOnce();
      await _syncCfg(); // 标签/心情显示配置双写·拉（§4.1，内部吞错）
      _set((s) => s.copyWith(
            clearSyncError: true,
            dataRev: s.dataRev + 1, // 同步代次：驱动一次性 UI 动作（收起评论，§4.4）
          ));
    } on ApiException catch (e) {
      if (e.code == 401 && !e.message.contains('动态口令')) {
        // token 失效（换发 token 动态口令仍无法通过时不会走到这）→ 重注册再试
        await _register();
        await flushNow();
        await _syncOnce();
        await _syncCfg();
        _set((s) => s.copyWith(
              clearSyncError: true,
              dataRev: s.dataRev + 1,
            ));
      } else {
        // 动态口令类 401（时钟偏差 >5 分钟等）或其他业务错误 → 横幅提示 + 可重试
        _set((s) => s.copyWith(
              syncError: e.message,
              serverStatus: '同步失败：${e.message}',
            ));
        rethrow;
      }
    }
  }

  /// 离线队列冲正：按最后修改时间从旧到新重放本地暂存的增删改。
  /// 网络仍不可达（DioException）→ 中断保留队列（下次手动刷新再试）；
  /// 业务错误（ApiException）→ 上抛给 syncNow 的横幅；删除 404 视为已删成功。
  Future<void> _flushDirty() async {
    final s = _session;
    if (s == null || _db == null) return;
    final rows = (await _db!.allEntries())
        .where((r) => r.syncState != 0)
        .toList()
      ..sort((a, b) => a.updatedAtMs.compareTo(b.updatedAtMs));
    try {
      for (final r in rows) {
      // 暂存媒体先上传 → 引用注入载荷 → 整条重加密（明文只在内存，P1-3 同款约束）
      var cipherJson = r.cipherJson ?? '';
      final pending = await _db!.pendingMediaFor(r.localId);
      if (pending.isNotEmpty && r.syncState != 3) {
        final refs = <MediaRef>[];
        for (final m in pending) {
          final up = await _api.uploadMedia(m.blob);
          refs.add(MediaRef(
              id: up.id, kind: m.kind, cekB64: m.cekWrappedB64, sec: m.sec));
        }
        final bytes = await Envelope.decrypt(cipherJson, s.privateKey);
        final old = EntryPayload.decode(utf8.decode(bytes));
        final payload = EntryPayload(
          text: old.text,
          time: old.time,
          mood: old.mood,
          tags: old.tags,
          media: [...old.media, ...refs],
          comments: old.comments,
        );
        cipherJson = await Envelope.encryptJson(
          utf8.encode(payload.encode()),
          s.publicKey,
        );
      }
      final parts = jsonDecode(cipherJson) as Map<String, dynamic>;
      switch (r.syncState) {
        case 1: // 待新建
          final serverId = await _api.createEntry(
            entryDate: r.entryDate,
            ciphertext: parts['ciphertext'] as String,
            nonceContent: parts['nonce_content'] as String,
            encryptedCek: parts['encrypted_cek'] as String,
          );
          await _upsertLocal(
            localId: r.localId,
            serverId: serverId,
            date: r.entryDate,
            cipherJson: cipherJson,
            updatedAtMs: r.updatedAtMs,
            syncState: 0,
            pendingMeta: '', // 冲正成功 = 标记清空
          );
          break;
        case 2: // 待替换（编辑/评论）
          await _api.replaceEntry(
            id: r.serverId!,
            entryDate: r.entryDate,
            ciphertext: parts['ciphertext'] as String,
            nonceContent: parts['nonce_content'] as String,
            encryptedCek: parts['encrypted_cek'] as String,
          );
          await _upsertLocal(
            localId: r.localId,
            serverId: r.serverId,
            date: r.entryDate,
            cipherJson: cipherJson,
            updatedAtMs: r.updatedAtMs,
            syncState: 0,
            pendingMeta: '',
          );
          break;
        case 3: // 待删除
          try {
            await _api.deleteEntry(r.serverId!);
          } on ApiException catch (e) {
            if (e.code != 404) rethrow; // 404=服务端本就没有，视为已删
          }
          await _upsertLocal(
            localId: r.localId,
            serverId: r.serverId,
            date: r.entryDate,
            cipherJson: r.cipherJson,
            updatedAtMs: r.updatedAtMs,
            deleted: true,
            syncState: 0,
            pendingMeta: '',
          );
          break;
      }
      await _db!.deletePendingMediaFor(r.localId);
    }
    } finally {
      await _loadLocalEntries(); // 冲正成功/中断都重建内存（serverId/引用/标记/计数一并刷新）
    }
  }

  /// 写路径本地先行的后台冲正触发（§2.3/§2.4）：每次写完调用一次，unawaited。
  /// DioException → 留队 + toast（联网后手动刷新续传）；ApiException → 同步横幅。
  /// 与手动刷新共用 _flushDirty，语义完全一致，区别只是不 await。
  @visibleForTesting
  bool debugHoldFlush = false; // 测试开关：挂起后台触发（确定性测试显式 flushNow）

  void _kickFlush() {
    if (debugHoldFlush) return;
    if (_flushing) return; // 在途：遗留行由下次写/手动刷新续传（§2.4）
    _flushing = true;
    unawaited(_flushBg());
  }

  Future<void> _flushBg() async {
    try {
      await _flushDirty();
    } on ApiException catch (e) {
      _set((s) => s.copyWith(
            syncError: e.message,
            serverStatus: '同步失败：${e.message}',
          ));
    } on DioException {
      _set((s) => s.copyWith(
            toast: '云端不可达 · 已本地保存，联网后手动刷新同步',
          ));
    } catch (_) {
      // 其余异常（如锁定态竞态）：留队静默
    } finally {
      _flushing = false;
    }
  }

  /// 显式冲正（手动刷新/横幅重试/测试）：等待在途后台冲正后跑一轮。
  Future<void> flushNow() async {
    var guard = 0;
    while (_flushing && guard < 200) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      guard++;
    }
    _flushing = true;
    try {
      await _flushDirty();
    } finally {
      _flushing = false;
    }
  }

  Future<void> _syncOnce() async {
    final existing = await _db!.allEntries();
    // 每次全量拉取（纪元游标）：① 头像每轮刷新换新（用户拍板新鲜感）——增量
    // 列表在重启后为空会拿不到任何头像；② 顺带重建条目索引。本地密文比对
    // 未变的条目直接 continue，实际开销在传输与解密，个人日记量级可接受。
    final result = await _api.sync('1970-01-01T00:00:00');
    final byServerId = {
      for (final e in existing)
        if (e.serverId != null) e.serverId!: e,
    };
    for (final se in result.list) {
      final local = byServerId[se.id];
      // 本地未同步的改动（离线队列）是最终态：跳过，防云端旧密文覆盖本地新密文
      if (local != null && local.syncState != 0) continue;
      final localId = local?.localId ?? _newLocalId();
      // 后端头像链接：每次同步覆盖（后端现生成、每次不同 → 刷新后有新鲜感）
      //（§2.7 v3：天卡必用接口图像；预下载池为后续增强，未实现前维持现链路）
      final av = se.avatar;
      if (!se.deleted && av != null && av.isNotEmpty) {
        _avatars[localId] = av;
      }
      final cipherJson = jsonEncode({
        'ciphertext': se.ciphertext,
        'nonce_content': se.nonceContent,
        'encrypted_cek': se.encryptedCek,
      });
      if (local != null &&
          local.cipherJson != null &&
          local.cipherJson == cipherJson) {
        continue; // 无变化
      }
      if (se.deleted) {
        if (local != null) {
          await _db!.upsertEntry(local.copyWithDeleted());
        }
        continue;
      }
      // 落盘只存密文（P1-3）：同步不再解密（他设备密文原样保留，读取时才解密）
      await _upsertLocal(
        localId: localId,
        serverId: se.id,
        date: se.entryDate,
        cipherJson: cipherJson,
        updatedAtMs: _isoToMs(se.updatedAt),
        // 新行创建序回填（服务端无 created_at 元数据，updatedAt 近似，晨 19 §5.8）；
        // 已有行 null = 保留原创建序
        createdAtMs: local == null ? _isoToMs(se.updatedAt) : null,
        deleted: false,
      );
    }
    await _loadLocalEntries();
  }

  Future<void> _loadLocalEntries() async {
    final rows = await _db!.allEntries();
    final entries = <DiaryEntry>[];
    for (final r in rows) {
      // 落盘只存密文（P1-3 本地明文根治）：读取时解密进内存；旧版本落过明文
      // payloadJson → 含 'text' 键即旧格式，顺手重写为密文（一次性迁移）。
      // 解密失败（损坏密文）→ 跳过渲染（密文仍在库，不丢数据）。
      final cipher = r.cipherJson;
      final priv = _session?.privateKey;
      EntryPayload? payload;
      var legacyPlain = false;
      if (cipher != null && cipher.isNotEmpty && priv != null) {
        try {
          final bytes = await Envelope.decrypt(cipher, priv);
          payload = EntryPayload.decode(utf8.decode(bytes));
        } catch (_) {
          continue;
        }
        try {
          final j = jsonDecode(r.payloadJson) as Map<String, dynamic>;
          legacyPlain = j.containsKey('text');
        } catch (_) {}
      } else if (cipher == null || cipher.isEmpty) {
        // 无密文行（仅旧数据/异常路径）：明文兜底展示
        try {
          final j = jsonDecode(r.payloadJson) as Map<String, dynamic>;
          if (j.containsKey('text')) {
            payload = EntryPayload.decode(r.payloadJson);
          }
        } catch (_) {}
        if (payload == null) continue;
      } else {
        continue; // 有密文但无解锁会话：不入内存
      }
      if (legacyPlain) {
        await _db!.upsertEntry(db.EntriesCompanion.insert(
          localId: r.localId,
          serverId: driftValue(r.serverId),
          entryDate: r.entryDate,
          payloadJson: cipher!, // legacyPlain 只在 cipher 非空分支置位
          cipherJson: driftStr(cipher),
          updatedAtMs: r.updatedAtMs,
          deleted: driftBool(r.deleted),
        ));
      }
      entries.add(DiaryEntry(
        localId: r.localId,
        serverId: r.serverId,
        date: r.entryDate,
        payload: payload,
        cipherJson: cipher,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAtMs),
        createdAt: r.createdAtMs == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
        deleted: r.deleted,
        avatarUrl: _avatars[r.localId],
        textPending: parsePendingMeta(r.pendingMeta).text,
        pendingComments: parsePendingMeta(r.pendingMeta).comments,
      ));
    }
    final pending = rows.where((r) => r.syncState != 0).length;
    _set((s) => s.copyWith(entries: entries, pendingCount: pending));
  }

  Future<void> _upsertLocal({
    required String localId,
    int? serverId,
    required String date,
    String? cipherJson,
    required int updatedAtMs,
    int? createdAtMs, // null = 不改动（创建序不可覆盖，晨 19 §5.8）
    bool deleted = false,
    int? syncState, // null = 不改动（保留现有状态）
    String? pendingMeta, // null = 不改动；'' = 清空标记
  }) async {
    // 落盘零明文（P1-3）：payloadJson 列复用存密文 JSON（免 schema 迁移），
    // 解密只在读取（_loadLocalEntries）时发生。
    await _db!.upsertEntry(db.EntriesCompanion.insert(
      localId: localId,
      serverId: driftValue(serverId),
      entryDate: date,
      payloadJson: cipherJson ?? '',
      cipherJson: driftStr(cipherJson),
      updatedAtMs: updatedAtMs,
      createdAtMs: createdAtMs == null
          ? const Value.absent()
          : Value(createdAtMs),
      deleted: driftBool(deleted),
      syncState:
          syncState == null ? const Value.absent() : Value(syncState),
      pendingMeta:
          pendingMeta == null ? const Value.absent() : Value(pendingMeta),
    ));
  }

  /// 从库行刷新内存条目的待同步标记（* 前缀）与待同步计数——
  /// 显示层标记的唯一事实源是库行 pendingMeta，内存条目一律由此重建，杜绝各处手工维护。
  Future<void> _refreshMarks() async {
    final store = _db;
    if (store == null) return; // demo/无库：无标记
    final rows = {for (final r in await store.allEntries()) r.localId: r};
    final pending = rows.values.where((r) => r.syncState != 0).length;
    _set((s) => s.copyWith(
          entries: [
            for (final e in s.entries)
              e.copyWithMark(parsePendingMeta(rows[e.localId]?.pendingMeta)),
          ],
          pendingCount: pending,
        ));
  }

  // ---------- 发布 / 编辑 / 删除 / 评论 ----------
  Future<void> publish({
    required String text,
    required String? mood,
    required List<String> tags,
    required List<MediaInput> media,
  }) async {
    final now = DateTime.now();
    final time = Dates.hm(now);
    final date = Dates.date(now);

    if (_demo) {
      final entry = DiaryEntry(
        localId: _newLocalId(),
        serverId: null,
        date: date,
        payload: EntryPayload(
          text: text.isEmpty ? '（一句没打完的话）' : text,
          time: time,
          mood: mood,
          tags: tags,
          media: [
            for (final m in media)
              MediaRef(id: -(500 + now.millisecondsSinceEpoch % 500),
                  kind: m.kind, cekB64: '', sec: m.sec),
          ],
        ),
        cipherJson: null,
        updatedAt: now,
      );
      state = state.copyWith(
        entries: [entry, ...state.entries],
        highlightDate: now,
        toast: '已加密保存 · 每条独立密钥 ✓',
      );
      return;
    }

    final s = _session;
    if (s == null) throw StateError('locked');
    final localId = _newLocalId(); // 在媒体加密前生成：暂存媒体要与条目关联

    // 1) 媒体端上加密暂存（本地先行 §2.3：发布路径不等网络，冲正时统一上传+注入引用）
    final pendingMedia = <db.PendingMediaItem>[];
    for (final m in media) {
      pendingMedia.add(await _encryptMediaLocal(m, s, localId));
    }

    // 2) 载荷加密（每条独立 CEK；媒体引用等冲正时注入）
    final payload = EntryPayload(
      text: text.isEmpty ? '（一句没打完的话）' : text,
      time: time,
      mood: mood,
      tags: tags,
      media: const [],
    );
    final cek = randomBytes(32);
    final cipherJson = await Envelope.encryptJson(
      utf8.encode(payload.encode()),
      s.publicKey,
      cek: cek,
    );

    // 3) 本地先行落库（§2.3 统一路径）：在线/离线同型，UI 即时返回不等网络
    for (final m in pendingMedia) {
      await _db!.insertPendingMedia(m);
    }
    await _upsertLocal(
      localId: localId,
      date: date,
      cipherJson: cipherJson,
      updatedAtMs: now.millisecondsSinceEpoch,
      createdAtMs: now.millisecondsSinceEpoch, // 创建序只在此写一次（§5.8）
      syncState: 1,
      pendingMeta: encodePendingMeta(true, const []), // 整条待上云 → 正文标 *
    );
    final entry = DiaryEntry(
      localId: localId,
      serverId: null, // 冲正成功后回填（serverId==null = 尚未推成）
      date: date,
      payload: payload,
      cipherJson: cipherJson,
      updatedAt: now,
      createdAt: now,
    );
    state = state.copyWith(
      entries: [entry, ...state.entries],
      highlightDate: now,
      toast: '已加密保存 · 每条独立密钥 ✓',
    );
    await _refreshMarks(); // 标记与计数唯一写入口
    _kickFlush(); // 后台冲正一次：上传媒体→注入引用→create→回填 serverId（§2.4）
  }

  /// 添加评论：载荷追加后整条重新加密替换（契约：编辑=整条替换）。
  Future<void> addComment(DiaryEntry entry, String text) async {
    final now = DateTime.now();
    final comment = EntryComment(
      who: '我',
      text: text,
      time: '${Dates.date(now)} ${Dates.hm(now)}', // 标准格式（2026-11-15 用户拍板）
    );
    final payload = EntryPayload(
      text: entry.payload.text,
      time: entry.payload.time,
      mood: entry.payload.mood,
      tags: entry.payload.tags,
      media: entry.payload.media,
      comments: [...entry.payload.comments, comment],
    );
    final updated = entry.copyWith(payload: payload, updatedAt: now);
    await _stageLocal(updated,
        pendingMark:
            (textEdited: false, newCommentIndex: entry.payload.comments.length));
    _replaceLocal(updated);
    state = state.copyWith(
      entries: state.entries.map((e) => e.localId == entry.localId ? updated : e).toList(),
      toast: '评论已加密保存',
    );
    await _refreshMarks();
    _kickFlush(); // 本地先行：推云交给后台冲正（§2.3）
  }

  /// 编辑评论（晨 19 §5.2）：评论内嵌载荷（契约无独立评论接口）→ 重建载荷走
  /// 既有 replaceEntry 冲正，本地先行同 addComment。标记：该索引并入
  /// 「未上云评论内容索引」（_stageLocal 去重合并），冲正成功自动清除。
  Future<void> editComment(DiaryEntry entry, int index, String text) async {
    final now = DateTime.now();
    final old = entry.payload.comments[index];
    final payload = entry.payload.copyWithComments([
      for (final (i, c) in entry.payload.comments.indexed)
        if (i == index)
          EntryComment(who: old.who, text: text, time: old.time)
        else
          c,
    ]);
    final updated = entry.copyWith(payload: payload, updatedAt: now);
    await _stageLocal(updated,
        pendingMark: (textEdited: false, newCommentIndex: index));
    _replaceLocal(updated);
    state = state.copyWith(toast: '评论已修改');
    await _refreshMarks();
    _kickFlush();
  }

  /// 删除评论（晨 19 §5.2）：同上重建载荷；标记重排——旧 meta 移除该索引、
  /// 其后整体 -1（评论行号前移，标记必须跟着移位，replaceMeta 整体替换）。
  /// 删除本身不加标（评论已从界面消失，同条目删除先例）。
  Future<void> deleteComment(DiaryEntry entry, int index) async {
    final now = DateTime.now();
    final payload = entry.payload.copyWithComments([
      for (final (i, c) in entry.payload.comments.indexed)
        if (i != index) c,
    ]);
    final updated = entry.copyWith(payload: payload, updatedAt: now);
    if (!_demo) {
      final row = await _findRow(entry.localId);
      final meta = parsePendingMeta(row?.pendingMeta);
      await _stageLocal(
        updated,
        replaceMeta: (
          text: meta.text,
          comments: [
            for (final v in meta.comments)
              if (v != index) (v > index ? v - 1 : v),
          ],
        ),
      );
    }
    _replaceLocal(updated);
    state = state.copyWith(toast: '评论已删除');
    await _refreshMarks();
    _kickFlush();
  }

  Future<void> deleteEntry(DiaryEntry entry) async {
    final now = DateTime.now();
    final deleted = entry.copyWith(deleted: true, updatedAt: now);
    if (!_demo && entry.serverId == null) {
      // 尚未推成（离线新建/本地先行窗口内）：无服务端可删 → 本地直接清除
      await _db!.deleteEntryHard(entry.localId);
      await _db!.deletePendingMediaFor(entry.localId);
      state = state.copyWith(
        entries:
            state.entries.where((e) => e.localId != entry.localId).toList(),
      );
      await _refreshMarks();
      return;
    }
    if (!_demo && entry.serverId != null) {
      // 本地先行（§2.3）：标记删除（syncState=3）+ UI 即隐，推云交给后台冲正
      //（404 视为已删成功）；云端不可达时条目保持隐藏、下次手动刷新续传。
      await _upsertLocal(
        localId: entry.localId,
        serverId: entry.serverId,
        date: entry.date,
        cipherJson: entry.cipherJson,
        updatedAtMs: now.millisecondsSinceEpoch,
        deleted: true,
        syncState: 3,
      );
      await _db!.deletePendingMediaFor(entry.localId); // 已删条目的暂存媒体不再上传
      _replaceLocal(deleted);
      state = state.copyWith(entries: [...state.entries]);
      await _refreshMarks();
      _kickFlush();
      return;
    }
    if (_db != null) {
      await _upsertLocal(
        localId: entry.localId,
        serverId: entry.serverId,
        date: entry.date,
        cipherJson: entry.cipherJson,
        updatedAtMs: now.millisecondsSinceEpoch,
        deleted: true,
      );
      _avatars.remove(entry.localId);
    }
    _replaceLocal(deleted);
    state = state.copyWith(entries: [...state.entries]);
  }

  /// 单个媒体端上加密（不上传）：暂存用（落盘只有密文，P1-3 同款约束）；
  /// 上传在冲正时发生（_flushDirty）。
  Future<db.PendingMediaItem> _encryptMediaLocal(
      MediaInput m, UnlockedSession s, String localId) async {
    final mCek = randomBytes(32);
    final mNonce = randomBytes(12);
    final blob = concat([
      mNonce,
      await aesGcmEncrypt(mCek, mNonce, m.bytes),
    ]);
    final wrapped = await wrapCek(mCek, s.publicKey);
    return db.PendingMediaItem(
      localId: localId, // 与条目关联，冲正上传后按条目清理
      kind: m.kind,
      sec: m.sec,
      blob: blob,
      cekWrappedB64: b64Encode(wrapped),
    );
  }

  /// 长按编辑：改文本/心情/标签（可追加新媒体），整条重新加密替换（契约：编辑=整条替换）。
  /// 云端不可达：新媒体本地加密暂存、载荷不带其引用，冲正时上传并注入（离线队列）。
  Future<void> updateEntry(
    DiaryEntry entry, {
    required String text,
    required String? mood,
    required List<String> tags,
    List<MediaInput> newMedia = const [],
  }) async {
    final now = DateTime.now();
    final mediaRefs = [...entry.payload.media];
    final pendingMedia = <db.PendingMediaItem>[];
    if (_demo) {
      for (final m in newMedia) {
        mediaRefs.add(MediaRef(
          id: -(500 + now.millisecondsSinceEpoch % 500),
          kind: m.kind,
          cekB64: '',
          sec: m.sec,
        ));
      }
    } else {
      final s = _session;
      if (s == null) throw StateError('locked');
      // 本地先行：新媒体端上加密暂存（不等上传），冲正时统一上传+注入引用
      for (final m in newMedia) {
        pendingMedia.add(await _encryptMediaLocal(m, s, entry.localId));
      }
    }
    final payload = EntryPayload(
      text: text.isEmpty ? '（一句没打完的话）' : text,
      time: entry.payload.time, // 创建时间不变
      mood: mood,
      tags: tags,
      media: mediaRefs,
      comments: entry.payload.comments,
    );
    final updated = entry.copyWith(payload: payload, updatedAt: now);
    await _stageLocal(updated,
        pendingMedia: pendingMedia,
        pendingMark: (textEdited: true, newCommentIndex: null));
    _replaceLocal(updated);
    state = state.copyWith(toast: '已更新 · 重新加密 ✓');
    await _refreshMarks();
    _kickFlush(); // 本地先行：推云交给后台冲正（§2.3）
  }

  /// 本地先行落库（§2.3 统一路径）：加密 → 暂存媒体重置 → 按 serverId 决定
  /// syncState（null→1 待新建 / 非 null→2 待替换）+ 合并待同步标记。推云交给
  /// 后台冲正（_kickFlush）或手动刷新（flushNow/syncNow），本方法绝不触网。
  /// [replaceMeta] 非空时整体替换标记（晨 19 §5.2 评论删除重排：合并语义不成立
  /// ——被删下标必须移除且其后前移，不能与旧集合并集）。
  Future<void> _stageLocal(DiaryEntry entry,
      {List<db.PendingMediaItem> pendingMedia = const [],
      ({bool textEdited, int? newCommentIndex})? pendingMark,
      ({bool text, List<int> comments})? replaceMeta}) async {
    if (_demo) return;
    final s = _session!;
    final cek = randomBytes(32);
    final cipherJson = await Envelope.encryptJson(
      utf8.encode(entry.payload.encode()),
      s.publicKey,
      cek: cek,
    );
    // 旧标记合并基础（离线窗口内多次修改 → 标记并集；Set 去重——编辑并入
    // 已在集合中的下标时不产生重复，晨 19 §5.2）
    final row = await _findRow(entry.localId);
    final old = parsePendingMeta(row?.pendingMeta);
    final mergedMeta = encodePendingMeta(
      old.text || (pendingMark?.textEdited ?? false),
      {
        ...old.comments,
        if (pendingMark?.newCommentIndex != null)
          pendingMark!.newCommentIndex!,
      }.toList(),
    );
    final metaToWrite = replaceMeta != null
        ? encodePendingMeta(replaceMeta.text, replaceMeta.comments)
        : mergedMeta;
    // 暂存媒体按本次编辑重置（冲正时载荷重建引用，避免重复上传）
    await _db!.deletePendingMediaFor(entry.localId);
    for (final m in pendingMedia) {
      await _db!.insertPendingMedia(m);
    }
    await _upsertLocal(
      localId: entry.localId,
      serverId: entry.serverId,
      date: entry.date,
      cipherJson: cipherJson,
      updatedAtMs: entry.updatedAt.millisecondsSinceEpoch,
      syncState: entry.serverId == null ? 1 : 2,
      pendingMeta: metaToWrite,
    );
  }

  Future<db.Entry?> _findRow(String localId) async {
    for (final r in await _db!.allEntries()) {
      if (r.localId == localId) return r;
    }
    return null;
  }

  void _replaceLocal(DiaryEntry entry) {
    state = state.copyWith(
      entries: state.entries
          .map((e) => e.localId == entry.localId ? entry : e)
          .toList(),
    );
  }

  // ---------- 设置 ----------
  /// 服务端地址（客户端配置，不区分构建环境）：所有接口调用拼接此地址。
  Future<void> setServerBase(String raw) async {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    _api.setBase(url);
    await _db?.kvSet('api.base', url);
    await _db?.kvRemove('api.token'); // 新服务端 → 旧 token 作废，解锁后自动重注册
    state = state.copyWith(
      serverBase: url,
      serverStatus: '服务端已切换 · $url',
      toast: '服务端地址已保存',
    );
    final s = _session;
    if (s != null) {
      try {
        await _register();
        unawaited(_loadHolidays());
        await syncNow();
      } catch (e) {
        state = state.copyWith(serverStatus: '新服务端不可达：$e');
      }
    }
  }

  Future<void> setTheme(ThemeSetting t) async {
    state = state.copyWith(theme: t);
    await _db?.kvSet('ui.theme', t.name);
  }

  Future<void> setAutoLock(int minutes) async {
    state = state.copyWith(autoLockMin: minutes);
    await _db?.kvSet('ui.autoLock', '$minutes');
  }

  Future<void> setNotify(bool on) async {
    state = state.copyWith(notifyEnabled: on);
    await _db?.kvSet('ui.notify', on ? '1' : '0');
    // 每日 21:30 本地提醒（web/桌面跳过；真机生效）
    try {
      if (on) {
        await NotificationService.enableDaily();
      } else {
        await NotificationService.disableDaily();
      }
    } catch (_) {
      // 通知不可用不阻塞设置（真机权限拒绝等）
    }
  }

  // ---------- 标签/心情显示配置（设备本地 KV；标签颜色=调色板覆盖或稳定哈希） ----------

  /// 从 KV 恢复显示配置到 AppDefaults 静态表（init 时调用；坏数据按缺省处理）。
  void _loadCfg(Map<String, String> kv) {
    Map<String, dynamic> jMap(String? s) =>
        s == null || s.isEmpty ? {} : (jsonDecode(s) as Map<String, dynamic>);
    List<dynamic> jList(String? s) =>
        s == null || s.isEmpty ? const [] : (jsonDecode(s) as List);
    try {
      AppDefaults.tagColorOverrides = {
        for (final e in jMap(kv['cfg.tagColor']).entries)
          if (e.value is String && AppDefaults.tagColorHex.containsKey(e.value))
            e.key: e.value as String,
      };
    } catch (_) {
      AppDefaults.tagColorOverrides = {};
    }
    try {
      // 无配置（键缺失）→ 回默认三项；显式 '[]'（用户删空）按空库
      final rawPreset = kv['cfg.tagPreset'];
      AppDefaults.tagPresets = rawPreset == null
          ? List<String>.of(AppDefaults.defaultTags)
          : {
              for (final v in jList(rawPreset))
                if (v is String && v.trim().isNotEmpty) v.trim(),
            }.toList()
            ..sort();
    } catch (_) {
      AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    }
    MoodCfg moodFromJson(Map<String, dynamic> j) => MoodCfg(
          key: j['key'] as String,
          emoji: (j['emoji'] as String?) ?? '📝',
          name: (j['name'] as String?) ?? '心情',
          colorHex: (j['colorHex'] as int?) ?? 0xFF8E8E93,
        );
    try {
      AppDefaults.moodOverrides = {
        for (final e in jMap(kv['cfg.moodOver']).entries)
          if (AppDefaults.moods.any((m) => m.key == e.key))
            e.key: moodFromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      AppDefaults.moodOverrides = {};
    }
    try {
      AppDefaults.customMoods = [
        for (final v in jList(kv['cfg.moodCustom']))
          if (v is Map<String, dynamic> && (v['key'] as String?)?.isNotEmpty == true)
            moodFromJson(v),
      ];
    } catch (_) {
      AppDefaults.customMoods = const [];
    }
    _deletedTags
      ..clear()
      ..addAll([
        for (final v in jList(kv['cfg.tagDeleted']))
          if (v is String) v,
      ]);
  }

  /// 测试钩子：按 init 同款逻辑从注入存储恢复显示配置。
  @visibleForTesting
  Future<void> debugLoadCfg() async {
    _loadCfg(await _db!.kvAll());
  }

  /// 静态表 → KV + cfgVersion 自增（驱动观察 AppState 的 UI 重建）。
  Future<void> _persistCfg() async {
    final db = _db;
    if (db != null) {
      await db.kvSet(
          'cfg.tagColor', jsonEncode(AppDefaults.tagColorOverrides));
      await db.kvSet('cfg.tagPreset', jsonEncode(AppDefaults.tagPresets));
      await db.kvSet(
          'cfg.moodOver',
          jsonEncode({
            for (final e in AppDefaults.moodOverrides.entries)
              e.key: {
                'key': e.value.key,
                'emoji': e.value.emoji,
                'name': e.value.name,
                'colorHex': e.value.colorHex,
              },
          }));
      await db.kvSet(
          'cfg.moodCustom',
          jsonEncode([
            for (final m in AppDefaults.customMoods)
              {
                'key': m.key,
                'emoji': m.emoji,
                'name': m.name,
                'colorHex': m.colorHex,
              },
          ]));
    }
    if (!ref.mounted) return;
    state = state.copyWith(cfgVersion: state.cfgVersion + 1);
  }

  /// 标签调色板：设置覆盖色（null = 恢复稳定哈希自动色）。
  Future<void> setTagColor(String tag, String? colorName) async {
    AppDefaults.tagColorOverrides = colorName == null
        ? (Map.of(AppDefaults.tagColorOverrides)..remove(tag))
        : (Map.of(AppDefaults.tagColorOverrides)..[tag] = colorName);
    await _persistCfg();
    _pushTag(tag); // 双写·推（§4.1：色名推当前生效色，自动哈希色物化为显式色）
  }

  /// 标签管理：新增预设标签（出现在撰写页建议里；1~16 字）。
  Future<void> addTagPreset(String tag) async {
    final t = tag.trim();
    if (t.isEmpty || t.length > 16) {
      throw const FormatException('标签需要 1~16 个字');
    }
    AppDefaults.tagPresets = {...AppDefaults.tagPresets, t}.toList()..sort();
    await _persistCfg();
    _pushTag(t);
  }

  /// 标签管理：移除预设标签（不影响已写入日记的标签）。
  /// 契约无删除端点（缺口 #8）→ 本地删除名单防拉取复活，服务端行保持原样。
  Future<void> removeTagPreset(String tag) async {
    AppDefaults.tagPresets = AppDefaults.tagPresets
        .where((t) => t != tag)
        .toList(growable: false);
    AppDefaults.tagColorOverrides =
        (Map.of(AppDefaults.tagColorOverrides)..remove(tag));
    _deletedTags.add(tag);
    final db = _db;
    if (db != null) {
      await db.kvSet('cfg.tagDeleted', jsonEncode(_deletedTags.toList()));
    }
    await _persistCfg();
  }

  /// 心情管理：新增自定义心情（key 设备内唯一即可，展示层直接按 key 渲染）。
  Future<MoodCfg> addMood(String name, String emoji, int colorHex) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 8) {
      throw const FormatException('心情名需要 1~8 个字');
    }
    final m = MoodCfg(
      key: 'm${DateTime.now().millisecondsSinceEpoch}',
      emoji: emoji.isEmpty ? '📝' : emoji,
      name: n,
      colorHex: colorHex,
    );
    AppDefaults.customMoods = [...AppDefaults.customMoods, m];
    await _persistCfg();
    return m;
  }

  /// 心情管理：编辑默认/自定义心情的显示（key 不变，历史条目照常渲染）。
  Future<void> updateMood(
      String key, String emoji, String name, int colorHex) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 8) {
      throw const FormatException('心情名需要 1~8 个字');
    }
    if (AppDefaults.customMoods.any((m) => m.key == key)) {
      AppDefaults.customMoods = [
        for (final m in AppDefaults.customMoods)
          if (m.key == key)
            MoodCfg(key: key, emoji: emoji, name: n, colorHex: colorHex)
          else
            m,
      ];
    } else {
      AppDefaults.moodOverrides = {
        ...AppDefaults.moodOverrides,
        key: MoodCfg(key: key, emoji: emoji, name: n, colorHex: colorHex),
      };
    }
    await _persistCfg();
  }

  /// 心情管理：删除自定义心情（默认 6 心情不可删，仅可改显示）。
  Future<void> removeMood(String key) async {
    AppDefaults.customMoods = AppDefaults.customMoods
        .where((m) => m.key != key)
        .toList(growable: false);
    await _persistCfg();
  }

  // ---------- 标签/心情双写与输入草稿（晨 17 §4.1/§4.12） ----------

  /// 本地删除名单（契约无标签删除端点，防拉取复活；KV cfg.tagDeleted）。
  final _deletedTags = <String>{};

  /// 双写·推（§4.1）：标签增/改色后 saveTag（同 device 同名=更新，幂等）。
  /// 色推「当前生效色」= 覆盖优先，无覆盖时哈希自动色物化为显式色。
  /// 失败静默留本地——下次变更或刷新再推，不加定时重试（与冲正拍板一致）。
  void _pushTag(String tag) {
    final color =
        AppDefaults.tagColorOverrides[tag] ?? AppDefaults.tagColorName(tag);
    unawaited(_api.saveTag(name: tag, color: color).catchError((_) => 0));
  }

  /// 双写·拉（§4.1）：syncNow 挂载。补缺合并——服务器独有的预设/色并入本地
  ///（同名本地优先：契约无时间戳，无法判新旧）；删除名单过滤防复活；
  /// 心情种子仅填充本地没有的 key（并入自定义列表使其可用）。失败静默。
  Future<void> _syncCfg() async {
    try {
      final tags = await _api.configTags();
      final presets = <String>{...AppDefaults.tagPresets};
      final colors = Map<String, String>.of(AppDefaults.tagColorOverrides);
      var changed = false;
      for (final t in tags) {
        if (_deletedTags.contains(t.name) || presets.contains(t.name)) continue;
        presets.add(t.name);
        if (t.color.isNotEmpty) colors[t.name] = t.color; // 色随预设一并补缺
        changed = true;
      }
      if (changed) {
        AppDefaults.tagPresets = presets.toList()..sort();
        AppDefaults.tagColorOverrides = colors;
        await _persistCfg();
      }
      final moods = await _api.configMoods();
      final known = {
        for (final m in AppDefaults.moods) m.key,
        for (final m in AppDefaults.customMoods) m.key,
      };
      final add = <MoodCfg>[];
      for (final m in moods) {
        if (known.contains(m.moodKey)) continue;
        add.add(MoodCfg(
          key: m.moodKey,
          emoji: m.emoji,
          name: m.emoji.isEmpty ? '心情' : m.moodKey,
          colorHex: AppDefaults.tagColorHex[m.color] ?? 0xFF8E8E93,
        ));
      }
      if (add.isNotEmpty) {
        AppDefaults.customMoods = [...AppDefaults.customMoods, ...add];
        await _persistCfg();
      }
    } catch (_) {
      // 网络不可达/业务错误：配置留在本地，下次手动刷新再拉（§4.1）
    }
  }

  // ---------- 输入草稿（§4.12） ----------

  Timer? _draftTimer;
  final _draftPending = <String, String>{};

  /// 保存草稿（值由调用方定义：compose 为 JSON，评论为纯文本）。300ms 防抖合并写。
  void saveDraft(String key, String value) {
    if (_db == null) return;
    _draftPending[key] = value;
    _draftTimer ??= Timer(const Duration(milliseconds: 300), _flushDrafts);
  }

  Future<void> _flushDrafts() async {
    _draftTimer = null;
    final pending = Map<String, String>.of(_draftPending);
    _draftPending.clear();
    final db = _db;
    if (db == null) return;
    for (final e in pending.entries) {
      await db.kvSet('draft.${e.key}', e.value);
    }
  }

  /// 读取草稿：先落防抖中未写盘的（避免读到旧值）。
  Future<String?> loadDraft(String key) async {
    await _flushDrafts();
    return _db?.kvGet('draft.$key');
  }

  /// 清除草稿（输入已落库/用户放弃）。
  Future<void> clearDraft(String key) async {
    _draftPending.remove(key);
    _draftTimer?.cancel();
    _draftTimer = null;
    await _db?.kvRemove('draft.$key');
  }

  void highlight(DateTime date) {
    state = state.copyWith(highlightDate: date);
  }

  void clearToast() {
    state = state.copyWith(clearToast: true);
  }

  Future<void> pushoverTest() async {
    await _api.notify(
      title: '一句话日记',
      message: 'Pushover 测试：端到端链路 OK',
    );
    state = state.copyWith(toast: '测试消息已通过 Pushover 发送');
  }

  // ---------- 工具 ----------
  String _newLocalId() => 'e-${DateTime.now().microsecondsSinceEpoch}-${randomBytes(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  int _isoToMs(String iso) {
    final d = DateTime.tryParse(iso);
    return d?.millisecondsSinceEpoch ?? 0;
  }
}

// drift nullable companion 辅助
Value<int?> driftValue(int? v) => Value(v);
Value<bool> driftBool(bool v) => Value(v);
Value<String?> driftStr(String? v) => Value(v);

/// 长按删除确认等 UI 用的 provider。
final appSessionProvider =
    NotifierProvider<AppSession, AppState>(AppSession.new);

extension on db.Entry {
  db.EntriesCompanion copyWithDeleted() => db.EntriesCompanion.insert(
        localId: localId,
        serverId: driftValue(serverId),
        entryDate: entryDate,
        payloadJson: payloadJson,
        cipherJson: driftStr(cipherJson),
        updatedAtMs: updatedAtMs,
        deleted: driftBool(true),
      );
}

// ---------- 统计辅助（回忆/我的页计算，端上明文索引） ----------

/// 连续记录天数：从今天（或昨天，若今天未写）往回数。
int computeStreak(List<DiaryEntry> entries, DateTime today) {
  final dates = entries.where((e) => !e.deleted).map((e) => e.date).toSet();
  var day = DateTime(today.year, today.month, today.day);
  if (!dates.contains(Dates.date(day))) {
    day = day.subtract(const Duration(days: 1)); // 今天未写不算断签
  }
  var streak = 0;
  while (dates.contains(Dates.date(day))) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

/// 热力图：日期 → 当天条数（GitHub 风格渲染由 UI 分级）。
Map<String, int> heatmapCounts(List<DiaryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    if (e.deleted) continue;
    counts[e.date] = (counts[e.date] ?? 0) + 1;
  }
  return counts;
}

/// 那年今天：去年同日的条目（取第一条非删除）。
DiaryEntry? yearAgoEntry(List<DiaryEntry> entries, DateTime today) {
  final y = today.year - 1;
  final target =
      Dates.date(DateTime(y, today.month, today.day));
  final list = entries.where((e) => !e.deleted && e.date == target).toList();
  return list.isEmpty ? null : list.first;
}

/// 总条数 / 标签数。
(int, int) totalAndTags(List<DiaryEntry> entries) {
  var total = 0;
  final tags = <String>{};
  for (final e in entries.where((e) => !e.deleted)) {
    total++;
    tags.addAll(e.payload.tags);
  }
  return (total, tags.length);
}
