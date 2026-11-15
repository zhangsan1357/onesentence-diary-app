// 应用会话（Riverpod）：身份门（首次生成/新设备登录/补设注册名）、锁定门、加密发布、同步、配置。
// 身份模型（2026-11-14 后端演进）：12 恢复词（或派生密钥）+ 注册名；deviceNo 每设备随机；
// 动态口令 X-Diary-Pass 由密钥本地推算（kdf.diaryPass），401 口令类错误由 ApiClient 透明重试。
// 模式选择：不区分构建环境——仅测试环境（FLUTTER_TEST）用演示数据；
// 服务端地址在「我的 → 服务端地址」运行时配置（默认本机 9060），所有接口拼接此地址。
import 'dart:async';
import 'dart:convert';


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
const cfgKvKeys = [
  'cfg.tagColor',
  'cfg.tagPreset',
  'cfg.moodOver',
  'cfg.moodCustom',
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
      );
}

class AppSession extends Notifier<AppState> {
  db.LocalStore? _db;
  UnlockedSession? _session;
  final _api = ApiClient();
  bool _demo = false;
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
      await db.kvRemove('ui.bio');
      await db.kvRemove('api.token');
      await db.kvRemove('api.deviceId');
      await db.kvRemove('sync.cursor');
      _avatars.clear();
      await db.clearEntries();
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
      await _syncOnce();
      _set((s) => s.copyWith(clearSyncError: true));
    } on ApiException catch (e) {
      if (e.code == 401 && !e.message.contains('动态口令')) {
        // token 失效（换发 token 动态口令仍无法通过时不会走到这）→ 重注册再试
        await _register();
        await _syncOnce();
        _set((s) => s.copyWith(clearSyncError: true));
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
      final localId = local?.localId ?? _newLocalId();
      // 后端头像链接：每次同步覆盖（后端现生成、每次不同 → 刷新后有新鲜感）
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
        deleted: r.deleted,
        avatarUrl: _avatars[r.localId],
      ));
    }
    _set((s) => s.copyWith(entries: entries));
  }

  Future<void> _upsertLocal({
    required String localId,
    int? serverId,
    required String date,
    String? cipherJson,
    required int updatedAtMs,
    bool deleted = false,
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
      deleted: driftBool(deleted),
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

    // 1) 媒体端上加密后上传（blob = nonce12 ‖ AES-GCM(cipher+tag)）
    final mediaRefs = <MediaRef>[];
    for (final m in media) {
      mediaRefs.add(await _encryptUploadMedia(m, s));
    }

    // 2) 载荷加密（每条独立 CEK）
    final payload = EntryPayload(
      text: text.isEmpty ? '（一句没打完的话）' : text,
      time: time,
      mood: mood,
      tags: tags,
      media: mediaRefs,
    );
    final cek = randomBytes(32);
    final cipherJson = await Envelope.encryptJson(
      utf8.encode(payload.encode()),
      s.publicKey,
      cek: cek,
    );
    final parts = jsonDecode(cipherJson) as Map<String, dynamic>;

    // 3) 上传密文（失败重注册一次）
    int serverId;
    try {
      serverId = await _api.createEntry(
        entryDate: date,
        ciphertext: parts['ciphertext'] as String,
        nonceContent: parts['nonce_content'] as String,
        encryptedCek: parts['encrypted_cek'] as String,
      );
    } on ApiException catch (e) {
      if (e.code == 401) {
        await _register();
        serverId = await _api.createEntry(
          entryDate: date,
          ciphertext: parts['ciphertext'] as String,
          nonceContent: parts['nonce_content'] as String,
          encryptedCek: parts['encrypted_cek'] as String,
        );
      } else {
        rethrow;
      }
    }

    // 4) 本地索引
    final entry = DiaryEntry(
      localId: _newLocalId(),
      serverId: serverId,
      date: date,
      payload: payload,
      cipherJson: cipherJson,
      updatedAt: now,
    );
    await _upsertLocal(
      localId: entry.localId,
      serverId: serverId,
      date: date,
      cipherJson: cipherJson,
      updatedAtMs: now.millisecondsSinceEpoch,
    );
    state = state.copyWith(
      entries: [entry, ...state.entries],
      highlightDate: now,
      toast: '已加密保存 · 每条独立密钥 ✓',
    );
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
    await _replacePayload(updated);
    _replaceLocal(updated);
    state = state.copyWith(
      entries: state.entries.map((e) => e.localId == entry.localId ? updated : e).toList(),
      toast: '评论已加密保存',
    );
  }

  Future<void> deleteEntry(DiaryEntry entry) async {
    final now = DateTime.now();
    final deleted = entry.copyWith(deleted: true, updatedAt: now);
    if (!_demo && entry.serverId != null) {
      try {
        await _api.deleteEntry(entry.serverId!);
      } on ApiException catch (e) {
        if (e.code == 401) {
          await _register();
          await _api.deleteEntry(entry.serverId!);
        } else {
          rethrow;
        }
      }
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

  /// 单个媒体：随机 CEK 端上加密上传 + CEK ECIES 包裹进载荷引用。
  Future<MediaRef> _encryptUploadMedia(MediaInput m, UnlockedSession s) async {
    final mCek = randomBytes(32);
    final mNonce = randomBytes(12);
    final blob = concat([
      mNonce,
      await aesGcmEncrypt(mCek, mNonce, m.bytes),
    ]);
    final up = await _api.uploadMedia(blob);
    final wrapped = await wrapCek(mCek, s.publicKey);
    return MediaRef(
      id: up.id,
      kind: m.kind,
      cekB64: b64Encode(wrapped),
      sec: m.sec,
    );
  }

  /// 长按编辑：改文本/心情/标签（可追加新媒体），整条重新加密替换（契约：编辑=整条替换）。
  Future<void> updateEntry(
    DiaryEntry entry, {
    required String text,
    required String? mood,
    required List<String> tags,
    List<MediaInput> newMedia = const [],
  }) async {
    final now = DateTime.now();
    final mediaRefs = [...entry.payload.media];
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
      for (final m in newMedia) {
        mediaRefs.add(await _encryptUploadMedia(m, s));
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
    await _replacePayload(updated);
    _replaceLocal(updated);
    state = state.copyWith(toast: '已更新 · 重新加密 ✓');
  }

  Future<void> _replacePayload(DiaryEntry entry) async {
    if (_demo || entry.serverId == null) return;
    final s = _session!;
    final cek = randomBytes(32);
    final cipherJson = await Envelope.encryptJson(
      utf8.encode(entry.payload.encode()),
      s.publicKey,
      cek: cek,
    );
    final parts = jsonDecode(cipherJson) as Map<String, dynamic>;
    Future<int> fn() => _api.replaceEntry(
          id: entry.serverId!,
          entryDate: entry.date,
          ciphertext: parts['ciphertext'] as String,
          nonceContent: parts['nonce_content'] as String,
          encryptedCek: parts['encrypted_cek'] as String,
        );
    try {
      await fn();
    } on ApiException catch (e) {
      if (e.code == 401) {
        await _register();
        await fn();
      } else {
        rethrow;
      }
    }
    await _upsertLocal(
      localId: entry.localId,
      serverId: entry.serverId,
      date: entry.date,
      cipherJson: cipherJson,
      updatedAtMs: entry.updatedAt.millisecondsSinceEpoch,
    );
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
  }

  /// 标签管理：新增预设标签（出现在撰写页建议里；1~16 字）。
  Future<void> addTagPreset(String tag) async {
    final t = tag.trim();
    if (t.isEmpty || t.length > 16) {
      throw const FormatException('标签需要 1~16 个字');
    }
    AppDefaults.tagPresets = {...AppDefaults.tagPresets, t}.toList()..sort();
    await _persistCfg();
  }

  /// 标签管理：移除预设标签（不影响已写入日记的标签）。
  Future<void> removeTagPreset(String tag) async {
    AppDefaults.tagPresets = AppDefaults.tagPresets
        .where((t) => t != tag)
        .toList(growable: false);
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
