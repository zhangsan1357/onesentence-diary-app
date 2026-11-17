// 头像预下载池·IO 实现（iOS/桌面）：Application Support/avatarpool/ 落盘，
// 后台静默分批下载（并发 3 / 批 20 / 批间隔 2~5s 抖动 / 单张超时 8s / 失败 ≤3 次
// 跳过下次启动再巡检 / 非 Wi-Fi 批间等待重查——connectivity_plus）。
// 断点续传 = 文件即进度（晨 18 简化：文件系统本身就是状态，进程被杀无损坏）。
// 池是纯增强：任何失败静默（渲染走默认人像，§5.12），绝不影响主流程。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'avatar_pool_core.dart';

abstract class AvatarPool {
  /// 幂等：种子就绪后启动填充循环（会话内单飞；stop 后可再 start）。
  Future<void> start();

  /// 停止循环（生命周期/测试）。
  void stop();

  /// 文件存在 → 绝对路径（同步 exists，µs 级）；否则 null（渲染走默认人像）。
  String? pathFor(int index);

  /// 池进度（§5.12 设置页查看）。
  ValueNotifier<PoolProgress> get progress;
}

AvatarPool createAvatarPool() => IoAvatarPool();

class IoAvatarPool implements AvatarPool {
  final Future<List<int>> Function(String url) fetch;
  final Future<bool> Function() isWifi;
  final Future<Directory?> Function() resolveDir;
  final int size;
  final int batchSize;
  final int concurrency;
  final int maxAttempts;
  final Duration noWifiWait;
  final Duration itemTimeout;
  final Duration Function() batchGap;
  final Random rng;

  bool _running = false;
  bool _stopped = false;
  List<int>? _seeds;
  Directory? _dir;
  final _attempts = <int, int>{};

  /// 池进度（§5.12 设置页查看）：初始「未启用」，start 成功进入填充即启用
  ///（enabled=true）；start 时目录一次扫描计初值（文件即进度），fill 每张
  /// 成功 +1。PoolProgress const 相等 → 未变化不重刷。
  @override
  final ValueNotifier<PoolProgress> progress =
      ValueNotifier<PoolProgress>(const PoolProgress(
          filled: 0, total: kAvatarPoolSize, enabled: false));

  void _bumpFilled(int filled) =>
      progress.value = PoolProgress(filled: filled, total: size, enabled: true);

  /// 注入点均为测试预留（默认实现为真实依赖）。
  IoAvatarPool({
    this.fetch = _defaultFetch,
    this.isWifi = _defaultIsWifi,
    this.resolveDir = _defaultDir,
    this.size = kAvatarPoolSize,
    this.batchSize = 20,
    this.concurrency = 3,
    this.maxAttempts = 3,
    this.noWifiWait = const Duration(seconds: 60),
    this.itemTimeout = const Duration(seconds: 8),
    Duration Function()? batchGap,
    Random? rng,
  })  : batchGap = batchGap ?? _defaultGap,
        rng = rng ?? Random();

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _stopped = false;
    try {
      final dir = await resolveDir();
      if (dir == null) {
        // path_provider 不可用（测试/平台异常）→ 静默禁用（进度行显「未启用」）
        progress.value = PoolProgress(filled: 0, total: size, enabled: false);
        return;
      }
      _dir = dir;
      if (!await dir.exists()) await dir.create(recursive: true);
      _seeds = await _ensureSeeds(dir);
      // 进度初值：一次目录扫描（文件即进度，无需重下载校验）
      _bumpFilled(_countFilled(dir));
      await _fill();
    } catch (_) {
      progress.value = PoolProgress(filled: 0, total: size, enabled: false);
      // 池失败不影响主流程（渲染走默认人像）
    } finally {
      _running = false;
    }
  }

  @override
  void stop() {
    _stopped = true;
  }

  /// 已就绪张数（av-*.png 计数，.tmp 半成品不算）。
  int _countFilled(Directory dir) {
    var n = 0;
    for (final e in dir.listSync()) {
      if (e is File && e.path.endsWith('.png')) n++;
    }
    return n;
  }

  @override
  String? pathFor(int index) {
    final dir = _dir;
    if (dir == null || index < 0 || index >= size) return null;
    final p = '${dir.path}${Platform.pathSeparator}av-$index.png';
    return File(p).existsSync() ? p : null;
  }

  /// 种子清单：seeds.json 持久化（二次启动复用，不重生成——随机调用的取值空间
  /// 一旦确定就固定，避免已下载文件与清单错位）。
  Future<List<int>> _ensureSeeds(Directory dir) async {
    final f = File('${dir.path}${Platform.pathSeparator}seeds.json');
    if (await f.exists()) {
      try {
        final list =
            (jsonDecode(await f.readAsString()) as List).cast<int>().toList();
        if (list.length == size) return list;
      } catch (_) {
        // 坏清单 → 重新生成覆盖
      }
    }
    final set = <int>{};
    while (set.length < size) {
      set.add(kQqMin + rng.nextInt(kQqMax - kQqMin + 1)); // 双闭区间（后端同款）
    }
    final seeds = set.toList();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(seeds), flush: true);
    await tmp.rename(f.path); // 原子写
    return seeds;
  }

  Future<void> _fill() async {
    final seeds = _seeds!;
    final sep = Platform.pathSeparator;
    var filled = progress.value.filled;
    // 多轮全池巡检：失败项下一轮重试（≤maxAttempts 封顶），一整轮无可做之事
    //（全部已下载/全部封顶）即收束——遗留项等下次启动再巡检。
    for (var pass = 0; pass < maxAttempts && !_stopped; pass++) {
      var work = 0;
      for (var i = 0; i < seeds.length && !_stopped; i += batchSize) {
        if (!await isWifi()) {
          // 蜂窝/无网：批间等待重查（设计：仅 Wi-Fi 填充）
          await Future<void>.delayed(noWifiWait);
          i -= batchSize;
          continue;
        }
        final end = min(i + batchSize, seeds.length);
        var cursor = i;
        Future<void> worker() async {
          while (cursor < end && !_stopped) {
            final idx = cursor++;
            if ((_attempts[idx] ?? 0) >= maxAttempts) continue;
            final f = File('${_dir!.path}$sep' 'av-$idx.png');
            if (await f.exists()) continue; // 文件即进度：已下载跳过
            work++;
            try {
              final bytes = await fetch(avatarPoolUrl('${seeds[idx]}@qq.com'))
                  .timeout(itemTimeout);
              if (bytes.isEmpty) throw const FormatException('空图');
              final tmp = File('${f.path}.tmp');
              await tmp.writeAsBytes(bytes, flush: true);
              await tmp.rename(f.path); // 原子写：进程被杀不留半张
              _bumpFilled(++filled); // §5.12：每张成功即上报（设置页实时可见）
            } catch (_) {
              _attempts[idx] = (_attempts[idx] ?? 0) + 1;
            }
          }
        }
        await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
        if (i + batchSize < seeds.length && !_stopped) {
          await Future<void>.delayed(batchGap()); // 2~5s 抖动，低速率静默
        }
      }
      if (work == 0) break;
    }
  }

  static Future<List<int>> _defaultFetch(String url) async {
    final dio = Dio();
    try {
      final r = await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes));
      return r.data ?? const [];
    } finally {
      dio.close();
    }
  }

  static Future<bool> _defaultIsWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true; // 检测不可用 → 保守放行（不阻塞填充）
    }
  }

  static Future<Directory?> _defaultDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}avatarpool');
    } catch (_) {
      return null;
    }
  }

  static Duration _defaultGap() =>
      Duration(milliseconds: 2000 + Random().nextInt(3000));
}
