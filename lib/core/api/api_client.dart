// API 客户端：02 手册 §5 冻结契约的客户端实现（只读契约，字段名严格一致）。
// 2026-11-14 后端身份模型演进（契约缺口记录见 PROGRESS.md）：
//   注册体 {userId=注册名, deviceNo, name=设备名, userKey=公钥 hex}；
//   每个业务请求附动态口令头 X-Diary-Pass = SHA-256(userKey:窗号) 前 8 位（5 分钟窗），
//   401 且报错含「动态口令」→ 窗口边界竞态，透明重试一次（无需重新注册）。
// 响应壳 CommonResult{code,message,data}：200 成功；401 未登录；404 参数校验失败；500 业务失败。
import 'package:dio/dio.dart';

import '../e2ee/kdf.dart';

/// 默认服务端地址（客户端可在「我的 → 服务端地址」运行时改，不用区分构建环境）。
const apiBase = 'http://127.0.0.1:9060';

/// 服务器业务异常（带壳内 message）。
class ApiException implements Exception {
  final int code;
  final String message;
  ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException($code, $message)';
}

/// 设备注册响应。
class DeviceRegResult {
  final String token;
  final int deviceId;
  DeviceRegResult({required this.token, required this.deviceId});
}

/// 服务端条目 DTO（camelCase，02 §5.2）。
class ServerEntry {
  final int id;
  final String entryDate;
  final String ciphertext;
  final String nonceContent;
  final String encryptedCek;
  final int payloadSize;
  final String createdAt;
  final String updatedAt;
  // 契约增量（2026-11-15）：随机头像 URL——响应时现生成、不落库、每次请求都不同。
  // 客户端不用于展示（web 受 CORS 限制、真机受网络波动，两轮均渲染成灰色占位），
  // 头像改由本地 SeedAvatar 确定性生成；字段保留仅文档化契约。
  final String? avatar;
  // 契约缺口防御：sync 列表含 deleted 条目（02 §5.3），字段级定义未列出该字段，
  // 按可选字段兼容（bool/int 均可）。
  final bool deleted;

  ServerEntry({
    required this.id,
    required this.entryDate,
    required this.ciphertext,
    required this.nonceContent,
    required this.encryptedCek,
    required this.payloadSize,
    required this.createdAt,
    required this.updatedAt,
    this.avatar,
    this.deleted = false,
  });

  factory ServerEntry.fromJson(Map<String, dynamic> j) {
    final d = j['deleted'];
    return ServerEntry(
      id: (j['id'] as num).toInt(),
      entryDate: j['entryDate'] as String,
      ciphertext: j['ciphertext'] as String? ?? '',
      nonceContent: j['nonceContent'] as String? ?? '',
      encryptedCek: j['encryptedCek'] as String? ?? '',
      payloadSize: (j['payloadSize'] as num?)?.toInt() ?? 0,
      createdAt: j['createdAt'] as String? ?? '',
      updatedAt: j['updatedAt'] as String? ?? '',
      avatar: j['avatar'] as String?,
      deleted: d is bool ? d : (d is num ? d != 0 : false),
    );
  }

  Map<String, dynamic> toPostJson() => {
        'entryDate': entryDate,
        'ciphertext': ciphertext,
        'nonceContent': nonceContent,
        'encryptedCek': encryptedCek,
      };
}

class SyncResult {
  final String cursor;
  final List<ServerEntry> list;
  SyncResult({required this.cursor, required this.list});
}

class TagCfg {
  final int id;
  final String name;
  final String color;
  final int sort;
  TagCfg({required this.id, required this.name, required this.color, required this.sort});

  factory TagCfg.fromJson(Map<String, dynamic> j) => TagCfg(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        color: j['color'] as String? ?? 'blue',
        sort: (j['sort'] as num?)?.toInt() ?? 0,
      );
}

class MoodCfgServer {
  final String moodKey;
  final String emoji;
  final String color;
  final int sort;
  MoodCfgServer({required this.moodKey, required this.emoji, required this.color, required this.sort});

  factory MoodCfgServer.fromJson(Map<String, dynamic> j) => MoodCfgServer(
        moodKey: j['moodKey'] as String,
        emoji: j['emoji'] as String,
        color: j['color'] as String,
        sort: (j['sort'] as num?)?.toInt() ?? 0,
      );
}

class ApiClient {
  final Dio _dio;

  /// 当前服务端地址：所有接口调用拼接此地址（默认编译常量，可运行时切换）。
  String base;

  ApiClient({String? base, Dio? dio})
      : base = base ?? apiBase,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: base ?? apiBase,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = token;
        if (t != null) options.headers['Authorization'] = 'Bearer $t';
        // 动态口令：每次请求实时推算（5 分钟窗），userKey = 注册时的公钥 hex
        final k = otpKey;
        if (t != null && k != null && k.isNotEmpty) {
          options.headers['X-Diary-Pass'] = diaryPass(k);
        }
        handler.next(options);
      },
    ));
  }

  String? token;

  /// 动态口令的推算密钥（= 注册时上报的 userKey，会话层在解锁/注册后设置）。
  String? otpKey;

  /// 运行时切换服务端地址（我的页 → 服务端地址）。
  void setBase(String url) {
    base = url;
    _dio.options.baseUrl = url;
  }

  /// 测试探针：裸 dio（用于健康检查等非契约调用）。
  Dio dioProbe() => _dio;

  /// 壳解包：code==200 → data；否则抛 ApiException。
  dynamic _unwrap(Response resp) {
    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException(-1, '响应壳格式异常');
    }
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 200) {
      throw ApiException(code, body['message'] as String? ?? '未知错误');
    }
    return body['data'];
  }

  /// 统一执行：后端把 HTTP 状态码设为壳内 code（401/404/500），
  /// Dio 默认 validateStatus 会在解包前抛 DioException——
  /// 带响应体的错误转壳解包（→ ApiException），网络层错误原样抛。
  /// 动态口令 401（窗口边界竞态）：重算口令重试一次；其余错误直接上抛。
  Future<dynamic> _run(Future<Response> Function() req) async {
    try {
      return await _attempt(req);
    } on ApiException catch (e) {
      if (e.code == 401 && e.message.contains('动态口令')) {
        return _attempt(req);
      }
      rethrow;
    }
  }

  Future<dynamic> _attempt(Future<Response> Function() req) async {
    Response r;
    try {
      r = await req();
    } on DioException catch (e) {
      if (e.response == null) rethrow;
      return _unwrap(e.response!);
    }
    return _unwrap(r);
  }

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get(path, queryParameters: query));

  Future<dynamic> _post(String path, Object? data) =>
      _run(() => _dio.post(path, data: data));

  // ---------- §5.1 设备注册（匿名）----------
  // 2026-11-14 演进：userId=注册名（终身不变），userKey=公钥 hex（64 位），
  // name=设备展示名。多设备 = 同 userId+同 userKey+各自 deviceNo，互不踢下线。
  Future<DeviceRegResult> registerDevice({
    required String userId,
    required String deviceNo,
    required String name,
    required String userKeyHex,
  }) async {
    final data = await _post('/api/v1/diary/device/register', {
      'userId': userId,
      'deviceNo': deviceNo,
      'name': name,
      'userKey': userKeyHex,
    });
    return DeviceRegResult(
      token: data['token'] as String,
      deviceId: (data['deviceId'] as num).toInt(),
    );
  }

  // ---------- §5.2 密文日记 ----------
  Future<List<ServerEntry>> fetchMonth(String month) async {
    final data = await _get('/api/v1/diary/entries', query: {'month': month});
    return ((data as Map<String, dynamic>)['list'] as List)
        .map((e) => ServerEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> createEntry({
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
    final data = await _post('/api/v1/diary/entries', {
      'entryDate': entryDate,
      'ciphertext': ciphertext,
      'nonceContent': nonceContent,
      'encryptedCek': encryptedCek,
    });
    return (data['id'] as num).toInt();
  }

  /// 编辑 = 整条替换（重新加密全量重传）。
  Future<int> replaceEntry({
    required int id,
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
    final data = await _post('/api/v1/diary/entries/$id', {
      'entryDate': entryDate,
      'ciphertext': ciphertext,
      'nonceContent': nonceContent,
      'encryptedCek': encryptedCek,
    });
    return (data['id'] as num).toInt();
  }

  Future<void> deleteEntry(int id) async {
    await _run(() => _dio.delete('/api/v1/diary/entries/$id')); // data=null，仅校验壳
  }

  // ---------- §5.3 增量同步 ----------
  Future<SyncResult> sync(String sinceIso) async {
    final data = await _get('/api/v1/diary/sync', query: {'since': sinceIso});
    return SyncResult(
      cursor: (data as Map<String, dynamic>)['cursor'] as String,
      list: (data['list'] as List)
          .map((e) => ServerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ---------- §5.4 媒体 ----------
  Future<({int id, int size, String sha256})> uploadMedia(
      List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'blob.bin'),
    });
    final data = await _run(() => _dio.post('/api/v1/diary/media', data: form))
        as Map<String, dynamic>;
    return (
      id: (data['id'] as num).toInt(),
      size: (data['size'] as num?)?.toInt() ?? 0,
      sha256: data['sha256'] as String? ?? '',
    );
  }

  Future<List<int>> downloadMedia(int id) async {
    final r = await _dio.get<List<int>>(
      '/api/v1/diary/media/$id',
      options: Options(responseType: ResponseType.bytes),
    );
    return r.data ?? const [];
  }

  // ---------- §5.5 调休 / 配置 / 通知 ----------
  Future<List<Map<String, dynamic>>> holidays(int year) async {
    final data = await _get('/api/v1/diary/holidays', query: {'year': year});
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<TagCfg>> configTags() async {
    final data = await _get('/api/v1/diary/config/tags');
    return (data as List).map((e) => TagCfg.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> saveTag({required String name, required String color}) async {
    final data = await _post('/api/v1/diary/config/tags', {
      'name': name,
      'color': color,
    });
    return (data['id'] as num).toInt();
  }

  Future<List<MoodCfgServer>> configMoods() async {
    final data = await _get('/api/v1/diary/config/moods');
    return (data as List)
        .map((e) => MoodCfgServer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 心情写入（晨 19 §5.9，缺口 #8 提案）：镜像 saveTag——同 moodKey=更新幂等。
  /// 端点未上线前调用失败由调用方静默吞掉（推送先行模式，端点上线即生效）。
  Future<int> saveMood({
    required String moodKey,
    required String emoji,
    required String color,
  }) async {
    final data = await _post('/api/v1/diary/config/moods', {
      'moodKey': moodKey,
      'emoji': emoji,
      'color': color,
    });
    return (data['id'] as num).toInt();
  }

  Future<void> deleteMood(String moodKey) async {
    await _post('/api/v1/diary/config/moods/delete', {'moodKey': moodKey});
  }

  Future<void> notify({required String title, required String message}) async {
    await _post('/api/v1/diary/notify', {'title': title, 'message': message});
  }
}
