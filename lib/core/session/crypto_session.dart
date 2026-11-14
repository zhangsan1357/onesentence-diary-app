// 身份与密钥封装（2026-11-14 后端身份模型）：12 恢复词（或其派生密钥 hex）→ 确定性 X25519 身份。
// 注册名（userId）终身不变、多设备共用；deviceNo 每设备随机生成（不复用旧设备号）。
// 服务端身份二元组 = (userId 注册名, userKey=公钥)：同词同注册名的新设备注册 → 同一数据空间。
// 私钥不出设备：Argon2id(口令, 盐) → 主密钥 → AES-GCM 包裹私钥；盐只存本地，不上传。

import 'dart:typed_data';

import '../e2ee/bytes.dart';

import '../e2ee/kdf.dart';
import 'recovery_words.dart';

/// 封装后的私钥存放结构（本地 KV，各字段 b64/hex）。
class KeystoreData {
  final String saltB64; // 16B
  final String wrappedPrivB64; // cipher+tag（私钥 32B）
  final String wrapNonceB64; // 12B
  final String publicKeyHex; // 64 hex（= 注册到服务端的 userKey）
  final String deviceNo; // 每设备随机 UUID v4（不复用旧设备号）
  final String userId; // 注册名（终身不变；空 = 存量 keystore 待补设）
  final String recoveryCode; // 身份文本（12 词短语或派生密钥 hex，用户保管）

  const KeystoreData({
    required this.saltB64,
    required this.wrappedPrivB64,
    required this.wrapNonceB64,
    required this.publicKeyHex,
    required this.deviceNo,
    required this.userId,
    required this.recoveryCode,
  });
}

class UnlockedSession {
  final KeystoreData keystore;
  final Uint8List privateKey; // 仅内存，lock() 即丢弃
  final Uint8List publicKey;

  const UnlockedSession({
    required this.keystore,
    required this.privateKey,
    required this.publicKey,
  });
}

const _kvSalt = 'ks.salt';
const _kvWrapped = 'ks.wrapped';
const _kvNonce = 'ks.nonce';
const _kvPub = 'ks.pub';
const _kvDeviceNo = 'ks.deviceNo';
const _kvUserId = 'ks.userId';
const _kvRecovery = 'ks.recovery';

String kvSalt = _kvSalt;
String kvWrapped = _kvWrapped;
String kvNonce = _kvNonce;
String kvPub = _kvPub;
String kvDeviceNo = _kvDeviceNo;
String kvRecovery = _kvRecovery;

/// 注销本机身份（logout）时需清除的 keystore KV 键。
const keystoreKvKeys = [
  'ks.salt',
  'ks.wrapped',
  'ks.nonce',
  'ks.pub',
  'ks.deviceNo',
  'ks.userId',
  'ks.recovery',
];

/// 身份文本 → 确定性会话：
/// 64 位 hex → 直接作为 seed；12 词短语 → 必须通过 BIP39 校验，seed = SHA-256(规范短语)。
/// deviceNo 每次调用随机生成（createIdentity/loginIdentity 各自落盘一次，此后从 KV 复用）；
/// userId = 注册名，随 keystore 持久化并携带到注册接口。
Future<UnlockedSession> sessionFromIdentity(
  String text, {
  String? deviceNo,
  String userId = '',
}) async {
  final t = text.trim();
  final Uint8List seed;
  if (RecoveryWords.looksLikeHexKey(t)) {
    seed = hexDecode(t);
  } else {
    RecoveryWords.validate(t);
    seed = RecoveryWords.phraseToSeed(t);
  }
  final pair = await x25519KeyPairFromSeed(seed); // 32B seed
  final priv = Uint8List.fromList(await pair.extractPrivateKeyBytes());
  final pub = Uint8List.fromList((await pair.extractPublicKey()).bytes);
  final ks = KeystoreData(
    saltB64: '',
    wrappedPrivB64: b64Encode(priv),
    wrapNonceB64: '',
    publicKeyHex: hexEncode(pub),
    deviceNo: deviceNo ?? _newUuid(),
    userId: userId,
    recoveryCode: t,
  );
  return UnlockedSession(keystore: ks, privateKey: priv, publicKey: pub);
}

/// 每设备随机 UUID v4（不复用旧设备号）。
String _newUuid() {
  final b = randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40; // v4
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = hexEncode(b);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// 从 KV 表读取 keystore（缺失 → null = 未初始化）。
KeystoreData? readKeystore(String? Function(String key) get) {
  final salt = get(_kvSalt);
  final wrapped = get(_kvWrapped);
  final nonce = get(_kvNonce);
  final pub = get(_kvPub);
  if (salt == null || wrapped == null || nonce == null || pub == null) {
    return null;
  }
  return KeystoreData(
    saltB64: salt,
    wrappedPrivB64: wrapped,
    wrapNonceB64: nonce,
    publicKeyHex: pub,
    deviceNo: get(_kvDeviceNo) ?? '',
    userId: get(_kvUserId) ?? '',
    recoveryCode: get(_kvRecovery) ?? '',
  );
}

/// 口令解锁；口令错误抛 StateError('bad-passcode')。
Future<UnlockedSession> unlockKeystore(
    KeystoreData ks, String passcode) async {
  final salt = b64Decode(ks.saltB64);
  final master = await argon2idKey(passcode, salt);
  final priv = await aesGcmDecrypt(
    master,
    b64Decode(ks.wrapNonceB64),
    b64Decode(ks.wrappedPrivB64),
  );
  return UnlockedSession(
    keystore: ks,
    privateKey: priv,
    publicKey: hexDecode(ks.publicKeyHex),
  );
}

/// 免口令模式（锁定保护关闭）：私钥明文存本机 KV——复用 wrappedPrivB64 字段，
/// salt/nonce 留空。端到端加密对服务端仍成立（公钥包裹照旧，私钥不出设备）。

/// 免口令恢复会话（wrapNonce 为空 = 明文模式，无 Argon2id，启动瞬时完成）。
UnlockedSession sessionFromPlain(KeystoreData ks) {
  assert(ks.wrapNonceB64.isEmpty, '非明文 keystore 需走口令解锁');
  final priv = b64Decode(ks.wrappedPrivB64);
  return UnlockedSession(
    keystore: ks,
    privateKey: priv,
    publicKey: hexDecode(ks.publicKeyHex),
  );
}

/// 把当前会话转成免口令 keystore（关闭锁定时落盘，身份字段原样保留）。
KeystoreData plainFromSession(UnlockedSession s) => KeystoreData(
      saltB64: '',
      wrappedPrivB64: b64Encode(s.privateKey),
      wrapNonceB64: '',
      publicKeyHex: s.keystore.publicKeyHex,
      deviceNo: s.keystore.deviceNo,
      userId: s.keystore.userId,
      recoveryCode: s.keystore.recoveryCode,
    );

/// 更换主密钥：仅重包裹私钥封套，数据零重加密（03 §2.2 第 6 条）。
Future<KeystoreData> rekeyKeystore(
    UnlockedSession session, String newPasscode) async {
  final salt = randomBytes(16);
  final master = await argon2idKey(newPasscode, salt);
  final nonce = randomBytes(12);
  final wrapped = await aesGcmEncrypt(master, nonce, session.privateKey);
  return KeystoreData(
    saltB64: b64Encode(salt),
    wrappedPrivB64: b64Encode(wrapped),
    wrapNonceB64: b64Encode(nonce),
    publicKeyHex: session.keystore.publicKeyHex,
    deviceNo: session.keystore.deviceNo,
    userId: session.keystore.userId,
    recoveryCode: session.keystore.recoveryCode,
  );
}

/// 把 keystore 拆成 KV 写入项。
Map<String, String> keystoreToKv(KeystoreData ks) => {
      _kvSalt: ks.saltB64,
      _kvWrapped: ks.wrappedPrivB64,
      _kvNonce: ks.wrapNonceB64,
      _kvPub: ks.publicKeyHex,
      _kvDeviceNo: ks.deviceNo,
      _kvUserId: ks.userId,
      _kvRecovery: ks.recoveryCode,
    };
