// M3 live 集成测试：客户端 ↔ 127.0.0.1:9060 真后端全链路（02 §5 契约）。
// 2026-11-14 后端身份模型 v4：注册体 {userId=注册名, deviceNo, name, userKey=公钥}，
// 业务请求附 X-Diary-Pass 动态口令（kdf.diaryPass，公式已对活后端实测）。
// 后端未启动时自动 SKIP（联调归属会话 A：保持后端在跑即可，00 §3.2）。
// 运行：flutter test test/live/integration_live_test.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/e2ee/bytes.dart';
import 'package:diary_app/core/e2ee/envelope.dart';
import 'package:diary_app/core/e2ee/kdf.dart';
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

const _pubHex =
    '07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c';
const _privB64 = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';

Future<bool> _backendUp() async {
  try {
    final dio = ApiClient().dioProbe();
    final r =
        await dio.get('/actuator/health').timeout(const Duration(seconds: 3));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

String _today() {
  final t = DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

String _month() => _today().substring(0, 7);

void main() {
  ApiClient? api;
  final runId = DateTime.now().millisecondsSinceEpoch;
  final userId = 'live-$runId'; // 注册名：每次运行独立身份
  final deviceNo = 'flutter-live-$runId';

  setUpAll(() async {
    final up = await _backendUp();
    if (!up) {
      print('SKIP: 后端 127.0.0.1:9060 未启动（会话 A 负责运行）——M3 live 测试跳过');
      return;
    }
    api = ApiClient();
  });

  /// 注册（限流 429 退避重试两次——本地联调反复跑套件会撞；CI 无后端不走到这）。
  Future<DeviceRegResult> reg(
    ApiClient a, {
    required String userId,
    required String deviceNo,
    String name = 'flutter-live',
    String userKeyHex = _pubHex,
  }) async {
    for (var i = 0;; i++) {
      try {
        return await a.registerDevice(
          userId: userId,
          deviceNo: deviceNo,
          name: name,
          userKeyHex: userKeyHex,
        );
      } on ApiException catch (e) {
        if (e.code != 429 || i >= 2) rethrow;
        await Future<void>.delayed(Duration(seconds: 5 * (i + 1)));
      }
    }
  }

  test('M3-1 设备注册：注册名+密钥二元组 → token/deviceId；同 deviceNo 幂等', () async {
    final a = api;
    if (a == null) return;
    final r1 = await reg(a, userId: userId, deviceNo: deviceNo);
    expect(r1.token.length, 64);
    expect(r1.deviceId, greaterThan(0));
    a.token = r1.token;
    a.otpKey = _pubHex; // 此后所有业务请求自动附 X-Diary-Pass（回归口令头）

    final r2 =
        await reg(a, userId: userId, deviceNo: deviceNo, name: 'flutter-live-2');
    expect(r2.deviceId, r1.deviceId); // 幂等：同 deviceNo 更新不新建
    a.token = r2.token; // 重发 token
  });

  test('M3-2 发布真实密文 → 月列表原样返回 → 解密一致', () async {
    final a = api;
    if (a == null) return;
    final payload = EntryPayload(
      text: 'live 测试：端到端加密一句话。服务端只见密文。',
      time: '12:34',
      mood: 'happy',
      tags: ['联调', '测试'],
    );
    final cipherJson = await Envelope.encryptJson(
      utf8.encode(payload.encode()),
      hexDecode(_pubHex),
    );
    final parts = jsonDecode(cipherJson) as Map<String, dynamic>;

    final id = await a.createEntry(
      entryDate: _today(),
      ciphertext: parts['ciphertext'] as String,
      nonceContent: parts['nonce_content'] as String,
      encryptedCek: parts['encrypted_cek'] as String,
    );
    expect(id, greaterThan(0));

    final list = await a.fetchMonth(_month());
    final mine = list.where((e) => e.id == id).toList();
    expect(mine.length, 1);
    expect(mine.first.entryDate, _today());
    expect(mine.first.ciphertext, parts['ciphertext']); // 服务端原样返回

    final serverJson = jsonEncode({
      'ciphertext': mine.first.ciphertext,
      'nonce_content': mine.first.nonceContent,
      'encrypted_cek': mine.first.encryptedCek,
    });
    final plain = await Envelope.decrypt(serverJson, base64Decode(_privB64));
    final back = EntryPayload.decode(utf8.decode(plain));
    expect(back.text, payload.text);
    expect(back.tags, payload.tags);
    expect(back.mood, 'happy');
  });

  test('M3-3 编辑=整条替换（重新加密重传）', () async {
    final a = api;
    if (a == null) return;
    final payload = EntryPayload(text: '替换后的内容 v2', time: '23:00', mood: null);
    final parts = jsonDecode(await Envelope.encryptJson(
      utf8.encode(payload.encode()),
      hexDecode(_pubHex),
    )) as Map<String, dynamic>;

    final id = await a.createEntry(
      entryDate: _today(),
      ciphertext: parts['ciphertext'] as String,
      nonceContent: parts['nonce_content'] as String,
      encryptedCek: parts['encrypted_cek'] as String,
    );

    final payload2 = EntryPayload(text: '替换后的内容 v3', time: '23:05', mood: null);
    final p2 = jsonDecode(await Envelope.encryptJson(
      utf8.encode(payload2.encode()),
      hexDecode(_pubHex),
    )) as Map<String, dynamic>;
    final rid = await a.replaceEntry(
      id: id,
      entryDate: _today(),
      ciphertext: p2['ciphertext'] as String,
      nonceContent: p2['nonce_content'] as String,
      encryptedCek: p2['encrypted_cek'] as String,
    );
    expect(rid, id);

    final list = await a.fetchMonth(_month());
    final row = list.where((e) => e.id == id).toList();
    expect(row.length, 1);
    expect(row.first.ciphertext, p2['ciphertext']);
  });

  test('M3-4 sync 增量同步：含游标与列表', () async {
    final a = api;
    if (a == null) return;
    final r = await a.sync('1970-01-01T00:00:00');
    expect(r.cursor, isNotEmpty);
    expect(r.list, isNotEmpty);
  });

  test('M3-5 长度校验：nonce 11B / encryptedCek 91B → 拒绝', () async {
    final a = api;
    if (a == null) return;
    final badNonce = base64Encode(Uint8List.fromList(List.filled(11, 1)));
    final okCek = base64Encode(Uint8List.fromList(List.filled(92, 2)));
    await expectLater(
      a.createEntry(
        entryDate: _today(),
        ciphertext: base64Encode(Uint8List.fromList(List.filled(16, 3))),
        nonceContent: badNonce,
        encryptedCek: okCek,
      ),
      throwsA(isA<ApiException>()),
      reason: 'nonceContent 解码 11 字节应被拒',
    );
    final okNonce = base64Encode(Uint8List.fromList(List.filled(12, 1)));
    final badCek = base64Encode(Uint8List.fromList(List.filled(91, 2)));
    await expectLater(
      a.createEntry(
        entryDate: _today(),
        ciphertext: base64Encode(Uint8List.fromList(List.filled(16, 3))),
        nonceContent: okNonce,
        encryptedCek: badCek,
      ),
      throwsA(isA<ApiException>()),
      reason: 'encryptedCek 解码 91 字节应被拒',
    );
  });

  test('M3-6 媒体：端上加密上传 → 下载字节一致 → 解密回明文', () async {
    final a = api;
    if (a == null) return;
    // 媒体密文 blob = nonce12 ‖ AES-GCM(cipher+tag)（客户端媒体方案）
    final secret = utf8.encode('这是一张假图片的原始字节内容' * 8);
    final cek = randomBytes(32);
    final nonce = randomBytes(12);
    final blob = concat([nonce, await aesGcmEncrypt(cek, nonce, secret)]);

    final up = await a.uploadMedia(blob);
    expect(up.id, greaterThan(0));
    expect(up.sha256.length, 64);

    final down = await a.downloadMedia(up.id);
    expect(down.length, blob.length);
    var same = true;
    for (var i = 0; i < blob.length; i++) {
      if (down[i] != blob[i]) {
        same = false;
        break;
      }
    }
    expect(same, isTrue, reason: '下载密文应与上传字节一致');

    final plain =
        await aesGcmDecrypt(cek, down.sublist(0, 12), down.sublist(12));
    expect(utf8.decode(plain), utf8.decode(secret));
  });

  test('M3-7 调休：2026 有数据；无数据年份 500 壳', () async {
    final a = api;
    if (a == null) return;
    final h = await a.holidays(2026);
    expect(h.length, greaterThanOrEqualTo(10));
    // 后端已内置 2027 数据（2026-11-13 实测），无数据壳用远端空年份验证。
    await expectLater(
      a.holidays(2099),
      throwsA(predicate((e) => e is ApiException && e.code == 500)),
    );
  });

  test('M3-8 配置表：moods 6 行种子；tags 可增可查', () async {
    final a = api;
    if (a == null) return;
    final moods = await a.configMoods();
    expect(moods.length, 6);
    expect(moods.map((m) => m.moodKey),
        containsAll(['happy', 'love', 'angry', 'surprise', 'sad', 'tired']));

    final tagId = await a.saveTag(name: '联调标签', color: 'pink');
    expect(tagId, greaterThan(0));
    final tags = await a.configTags();
    expect(tags.any((t) => t.name == '联调标签'), isTrue);
  });

  test('M3-9 删除：月列表消失，sync 仍返回（deleted 标记）', () async {
    final a = api;
    if (a == null) return;
    final payload = EntryPayload(text: '待删除条目', time: '01:02', mood: null);
    final parts = jsonDecode(await Envelope.encryptJson(
      utf8.encode(payload.encode()),
      hexDecode(_pubHex),
    )) as Map<String, dynamic>;
    final id = await a.createEntry(
      entryDate: _today(),
      ciphertext: parts['ciphertext'] as String,
      nonceContent: parts['nonce_content'] as String,
      encryptedCek: parts['encrypted_cek'] as String,
    );
    await a.deleteEntry(id);

    final list = await a.fetchMonth(_month());
    expect(list.where((e) => e.id == id), isEmpty);

    final sync = await a.sync('1970-01-01T00:00:00');
    final gone = sync.list.where((e) => e.id == id).toList();
    expect(gone.length, 1, reason: 'sync 应含 deleted 条目');
    expect(gone.first.deleted, isTrue,
        reason: '契约缺口防御：sync DTO 需含 deleted 标记（02 §5.3）');
  });

  test('M3-10 鉴权：无 token → 401 壳', () async {
    final a = api;
    if (a == null) return;
    final anon = ApiClient();
    await expectLater(
      anon.fetchMonth(_month()),
      throwsA(predicate((e) => e is ApiException && e.code == 401)),
    );
  });

  test('M3-12 动态口令：错口令 → 401「动态口令」壳（含透明重试后仍失败）', () async {
    final a = api;
    if (a == null) return;
    final wrong = ApiClient();
    wrong.token = a.token;
    wrong.otpKey = 'ff' * 32; // 错误密钥 → 错误口令
    await expectLater(
      wrong.sync('1970-01-01T00:00:00'),
      throwsA(predicate((e) =>
          e is ApiException &&
          e.code == 401 &&
          e.message.contains('动态口令'))),
    );
    // 正确口令由 M3-4~M3-9 全程隐式回归（拦截器计算 X-Diary-Pass）
  });

  test('M3-13 多设备共享（②）：同注册名+同密钥+新设备号 → 各自登录、数据互通', () async {
    final a = api;
    if (a == null) return;
    // 设备 B：新 deviceNo，同 userId + 同 userKey（= 新设备登录语义）
    final b = ApiClient();
    final rb = await reg(b,
      userId: userId,
      deviceNo: 'flutter-live-b-$runId',
      name: 'flutter-live-b',
      userKeyHex: _pubHex,
    );
    expect(rb.deviceId, greaterThan(0));
    b.token = rb.token;
    b.otpKey = _pubHex;

    // B 全量拉取 → 能看到 A 发布的条目（数据按注册名共享）
    final syncB = await b.sync('1970-01-01T00:00:00');
    expect(syncB.list, isNotEmpty, reason: '设备 B 应同步到设备 A 的密文条目');
  });

  test('M3-14 冒名拒绝：同注册名 + 不同密钥 → 拒绝', () async {
    final a = api;
    if (a == null) return;
    final impostor = ApiClient();
    await expectLater(
      reg(
        impostor,
        userId: userId,
        deviceNo: 'flutter-live-x-$runId',
        userKeyHex: 'ab' * 32,
      ),
      throwsA(predicate((e) => e is ApiException && e.code == 404)),
      reason: '同注册名必须绑定同一密钥（身份二元组）',
    );
  });

  test('M3-11 Pushover：未配置 token → 500 壳（已配置则 200）', () async {
    final a = api;
    if (a == null) return;
    try {
      await a.notify(title: '一句话日记', message: 'Pushover live 测试（脱敏文案）');
      // 服务端已配置 PUSHOVER_TOKEN：200 通过
    } on ApiException catch (e) {
      expect(e.code, 500, reason: '未配置 PUSHOVER_TOKEN 时应为 500 壳');
      expect(e.message, contains('未配置'));
    }
  });

  // ---------- 晨 19 增量端点（stats/顺序契约、rename/rotate 缺口 #7、mood 缺口 #8） ----------

  /// 独立身份（互不污染计数/名单）。
  Future<ApiClient> fresh(String tag) async {
    final a = ApiClient();
    final r = await reg(a, userId: 'live-$tag-$runId', deviceNo: 'dev-$tag-$runId');
    a.token = r.token;
    a.otpKey = _pubHex;
    return a;
  }

  Future<int> create(ApiClient a, String time, String text) async {
    final payload = EntryPayload(text: text, time: time, mood: null);
    final cipherJson =
        await Envelope.encryptJson(utf8.encode(payload.encode()), hexDecode(_pubHex));
    final parts = jsonDecode(cipherJson) as Map<String, dynamic>;
    return a.createEntry(
      entryDate: _today(),
      ciphertext: parts['ciphertext'] as String,
      nonceContent: parts['nonce_content'] as String,
      encryptedCek: parts['encrypted_cek'] as String,
    );
  }

  test('M3-15 stats：total/streak/heatmap 稀疏+date ASC/perMonth（晨 19 对齐项）', () async {
    if (api == null) return; // 后端未启动（CI）：SKIP（约定对全部 live 项生效）
    final a = await fresh('st');
    await create(a, '08:00', 'stats 一');
    await create(a, '21:00', 'stats 二');
    final s = await a.stats();
    expect(s.total, 2, reason: '独立身份恰好两条');
    expect(s.streak, greaterThanOrEqualTo(1), reason: '今天有记录 → 锚点今天');
    expect(s.heatmap, isNotEmpty);
    for (final d in s.heatmap) {
      expect(d.count, greaterThan(0), reason: '稀疏：零值日不出现，客户端自填');
    }
    final dates = s.heatmap.map((d) => d.date).toList();
    expect(dates, equals(dates.toList()..sort()), reason: 'date ASC');
    expect(dates.last, _today(), reason: '窗口含今天');
    expect(s.perMonth.map((m) => m.month), contains(_month()));
  });

  test('M3-16 rename（缺口 #7）：改名 → 新名重注册同 userKey 成功', () async {
    if (api == null) return; // 后端未启动（CI）：SKIP
    final a = await fresh('rn');
    await a.rename('live-rn2-$runId');
    final b = ApiClient();
    final r = await b.registerDevice(
      userId: 'live-rn2-$runId',
      deviceNo: 'dev-rn2-$runId',
      name: 'flutter-live',
      userKeyHex: _pubHex,
    );
    expect(r.token.length, 64, reason: '数据空间已重键到新名');
  });

  test('M3-17 rotate（缺口 #7）：换 userKey 换 token → 新钥可写', () async {
    if (api == null) return; // 后端未启动（CI）：SKIP
    final a = await fresh('ro');
    final k2 = 'cd' * 32;
    final r2 = await a.rotate(userKeyHex: k2);
    expect(r2.token.length, 64);
    a.token = r2.token;
    a.otpKey = k2;
    final id = await create(a, '10:00', 'rotate 后新钥写入');
    expect(id, greaterThan(0), reason: '新 userKey 放行后业务可用');
  });

  test('M3-18 mood 写入/删除（缺口 #8）：saveMood 回读 → deleteMood 消失', () async {
    if (api == null) return; // 后端未启动（CI）：SKIP
    final a = await fresh('mo');
    final key = 'lm$runId'; // 1~16 位小写/数字/下划线（服务端校验）
    final id = await a.saveMood(moodKey: key, emoji: '🚀', color: '#34C759');
    expect(id, greaterThan(0));
    final moods = await a.configMoods();
    final mine = moods.where((m) => m.moodKey == key).toList();
    expect(mine.length, 1);
    expect(mine.single.emoji, '🚀');
    expect(mine.single.color, '#34C759');
    await a.deleteMood(key);
    final after = await a.configMoods();
    expect(after.where((m) => m.moodKey == key), isEmpty);
  });
}