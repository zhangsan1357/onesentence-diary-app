// 面容 ID 解锁桥：私钥以 biometryCurrentSet 访问控制存 iOS Keychain
// （flutter_secure_storage，生物特征集变更时钥匙串项自动失效，属平台安全语义）。
// 生物识别通过后取私钥直接建会话——面容即解锁，无需再输口令；口令路径保留为回退。
// web/桌面 available() 返回 false（完整功能仅真机 iOS/Android）。
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

abstract class BioVault {
  /// 平台支持且设备具备可用生物识别。
  Future<bool> available();

  /// 弹出系统生物识别（Face ID / 指纹）验证。
  Future<bool> authenticate(String reason);

  /// 私钥（b64）存入生物识别保护的钥匙串。
  Future<void> savePriv(String privB64);

  /// 读取私钥存档（无存档/生物特征集已变更 → null）。
  Future<String?> readPriv();

  Future<void> deletePriv();
}

class BioVaultImpl implements BioVault {
  static const _key = 'bio.priv';
  final FlutterSecureStorage _store = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> savePriv(String privB64) =>
      _store.write(key: _key, value: privB64);

  @override
  Future<String?> readPriv() => _store.read(key: _key);

  @override
  Future<void> deletePriv() => _store.delete(key: _key);
}
