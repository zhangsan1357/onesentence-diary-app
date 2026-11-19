// 头像预下载池（晨 18 §2.7 v4）：后端同款随机 QQ 邮箱枚举（黄金向量钉死）+
// 种子持久化 + 分批下载调度（幂等/失败重试计数）+ Wi-Fi 门 + 渲染两分支。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:diary_app/core/util/avatar_pool.dart';
import 'package:diary_app/widgets/day_card_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tmpDir() => Directory.systemTemp.createTempSync('avatarpool_test');

IoAvatarPool _pool({
  required Directory dir,
  Future<List<int>> Function(String url)? fetch,
  Future<bool> Function()? isWifi,
  int size = 12,
  int batchSize = 5,
  int concurrency = 3,
  int maxAttempts = 3,
  Duration noWifiWait = const Duration(milliseconds: 10),
}) {
  return IoAvatarPool(
    fetch: fetch ?? ((_) async => [1, 2, 3]),
    isWifi: isWifi ?? (() async => true),
    resolveDir: (() async => dir),
    size: size,
    batchSize: batchSize,
    concurrency: concurrency,
    maxAttempts: maxAttempts,
    noWifiWait: noWifiWait,
    batchGap: () => Duration.zero, // 测试零间隔
  );
}

void main() {
  test('黄金向量：md5(798969707@qq.com) 与后端 AvatarUtil 示例逐字一致 + URL 形态', () {
    expect(
      avatarPoolUrl('798969707@qq.com'),
      'https://cn.cravatar.com/avatar/dedf817b2bf150463aca1693856ad6e8.png?s=184',
    );
  });

  test('indexFor：确定性（同 key 同格）+ 范围 [0, size)', () {
    final a = avatarPoolIndex('42|2026-11-17');
    expect(avatarPoolIndex('42|2026-11-17'), a);
    expect(avatarPoolIndex('42|2026-11-17'), inInclusiveRange(0, kAvatarPoolSize - 1));
    // 换盐即换格（随机调用语义；两 key 全等的概率 1/10000，断言不同即盐生效）
    expect(avatarPoolIndex('43|2026-11-17'), isNot(a));
  });

  test('种子生成：数量/唯一/双闭区间 + seeds.json 持久化（二次启动复用不重生成）', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final pool = _pool(dir: dir, size: 50);
    await pool.start();
    final f = File('${dir.path}${Platform.pathSeparator}seeds.json');
    expect(f.existsSync(), isTrue);
    final seeds = (jsonDecode(f.readAsStringSync()) as List).cast<int>();
    expect(seeds.length, 50);
    expect(seeds.toSet().length, 50, reason: '唯一');
    for (final q in seeds) {
      expect(q, inInclusiveRange(kQqMin, kQqMax), reason: '后端同款双闭区间');
    }
    // 二次启动（新实例同目录）：种子清单复用
    final pool2 = _pool(dir: dir, size: 50);
    await pool2.start();
    final seeds2 = (jsonDecode(f.readAsStringSync()) as List).cast<int>();
    expect(seeds2, seeds, reason: '不重生成——随机取值空间一旦确定就固定');
  });

  test('批次下载：全部落盘 + 幂等（已下载不再拉）+ 失败重试计数封顶', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final seeds = List<int>.generate(12, (i) => kQqMin + i); // 预置已知种子
    File('${dir.path}${Platform.pathSeparator}seeds.json')
        .writeAsStringSync(jsonEncode(seeds));
    final failUrl = avatarPoolUrl('${seeds[3]}@qq.com');
    final calls = <String>[];
    final pool = _pool(
      dir: dir,
      fetch: (u) async {
        calls.add(u);
        if (u == failUrl) throw Exception('cdn 500');
        return [9, 9, 9];
      },
      maxAttempts: 2,
    );
    await pool.start();
    expect(calls.where((u) => u == failUrl).length, 2, reason: '重试 ≤2 次封顶');
    expect(calls.length, 13, reason: '11 张成功各 1 次 + 失败项 2 次');
    final pngs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .length;
    expect(pngs, 11, reason: '失败项无文件（原子写不落半张）');
    // 幂等：新实例同目录，成功项不再拉，仅失败项再试（实例间重试计数重置）
    calls.clear();
    final pool2 = _pool(
      dir: dir,
      fetch: (u) async {
        calls.add(u);
        return [7];
      },
      maxAttempts: 1,
    );
    await pool2.start();
    expect(calls, [failUrl], reason: '文件即进度：只有失败项再巡检');
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).length,
      12,
      reason: '失败项补齐',
    );
  });

  test('并发上限：同一时刻在途请求数 ≤ concurrency', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    var inflight = 0;
    var peak = 0;
    final pool = _pool(
      dir: dir,
      size: 10,
      batchSize: 10,
      concurrency: 3,
      fetch: (_) async {
        inflight++;
        peak = max(peak, inflight);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inflight--;
        return [1];
      },
    );
    await pool.start();
    expect(peak, inInclusiveRange(1, 3), reason: '并发 3 上限');
    expect(peak, 3, reason: '批内确实并行到上限');
  });

  test('Wi-Fi 门：非 Wi-Fi 不发起任何下载，stop 后循环退出', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    var calls = 0;
    final pool = _pool(
      dir: dir,
      isWifi: () async => false,
      fetch: (_) async {
        calls++;
        return [1];
      },
    );
    final run = pool.start(); // 循环将停在 Wi-Fi 门等待
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 0, reason: '非 Wi-Fi：一次都不拉');
    pool.stop();
    await run.timeout(const Duration(seconds: 2),
        onTimeout: () => throw StateError('stop 后循环未退出'));
  });

  test('pathFor：文件存在返回路径，越界/未就绪返回 null', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final pool = _pool(dir: dir, size: 5, fetch: (_) async => throw Exception('全失败'));
    expect(pool.pathFor(0), isNull, reason: 'start 前未就绪');
    await pool.start(); // 全部下载失败 → 目录里只有我手写的文件
    File('${dir.path}${Platform.pathSeparator}av-2.png').writeAsBytesSync([1]);
    expect(pool.pathFor(2), isNotNull);
    expect(pool.pathFor(1), isNull);
    expect(pool.pathFor(-1), isNull);
    expect(pool.pathFor(5), isNull, reason: '越界');
  });

  testWidgets('渲染（§5.12）：池文件命中走 Image.file，缺失默认人像（零网络）', (tester) async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final hit = File('${dir.path}${Platform.pathSeparator}av-0.png');
    hit.writeAsBytesSync(kPng1x1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayCardAvatar(poolPath: hit.path, size: 56),
      ),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget, reason: '池命中本地直读');
    expect(find.byIcon(Icons.person), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayCardAvatar(poolPath: null, size: 56),
      ),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.person), findsOneWidget, reason: '缺失无 URL → 默认人像占位');
  });

  testWidgets('渲染（§5.14）：缺失有回落 URL → 挂载触发 ensure 补池；命中不触发', (tester) async {
    var ensured = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayCardAvatar(
            poolPath: null, url: 'https://x/y.png', ensure: () => ensured++, size: 56),
      ),
    ));
    await tester.pump();
    expect(ensured, 1, reason: '未命中挂载即补池（fire-and-forget，幂等）');
    // 命中本地文件 → 不触发
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayCardAvatar(
            poolPath: '/x/av-0.png', url: 'https://x/y.png', ensure: () => ensured++, size: 56),
      ),
    ));
    await tester.pump();
    expect(ensured, 1, reason: '池命中零网络零补写');
  });

  test('urlForIndex（§5.14 按需回落）：种子就绪 → cravatar URL；未启动/越界 → null', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final seeds = List<int>.generate(5, (i) => kQqMin + i); // 已知种子
    File('${dir.path}${Platform.pathSeparator}seeds.json')
        .writeAsStringSync(jsonEncode(seeds));
    final pool = _pool(dir: dir, size: 5, fetch: (_) async => throw Exception('填充失败'));
    expect(pool.urlForIndex(0), isNull, reason: 'start 前（种子未装载）→ null');
    await pool.start();
    expect(pool.urlForIndex(0), avatarPoolUrl('${seeds[0]}@qq.com'));
    expect(pool.urlForIndex(4), avatarPoolUrl('${seeds[4]}@qq.com'));
    expect(pool.urlForIndex(5), isNull, reason: '越界');
    expect(pool.urlForIndex(-1), isNull);
  });

  test('ensureIndex（§5.14 按需补一张）：下载原子入池 + 已有跳过 + 幂等去重', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final seeds = List<int>.generate(4, (i) => kQqMin + i);
    File('${dir.path}${Platform.pathSeparator}seeds.json')
        .writeAsStringSync(jsonEncode(seeds));
    final urls = <String>[];
    var failAll = true; // 填充期全失败（池空），按需路径再放开
    final pool = _pool(
      dir: dir,
      size: 4,
      fetch: (url) async {
        if (failAll) throw Exception('填充期失败');
        urls.add(url);
        if (url == avatarPoolUrl('${seeds[1]}@qq.com')) throw Exception('该格失败');
        return kPng1x1;
      },
      maxAttempts: 1,
    );
    await pool.start();
    expect(pool.pathFor(0), isNull, reason: '填充循环全失败 → 池空');
    failAll = false;
    await pool.ensureIndex(0);
    expect(pool.pathFor(0), isNotNull, reason: '按需下载入池（原子写）');
    expect(urls, contains(avatarPoolUrl('${seeds[0]}@qq.com')));
    expect(File(pool.pathFor(0)!).readAsBytesSync(), kPng1x1);
    final filled = pool.progress.value.filled;
    // 已有文件 → 直接跳过（不再拉）
    await pool.ensureIndex(0);
    expect(urls.where((u) => u == avatarPoolUrl('${seeds[0]}@qq.com')).length, 1,
        reason: '文件即进度：已入池不重拉');
    // 失败格 → 静默（不抛、不落盘）
    await pool.ensureIndex(1);
    expect(pool.pathFor(1), isNull);
    expect(pool.progress.value.filled, filled, reason: '失败不计数');
  });

  test('进度（§5.12）：初值=目录扫描，每张成功 +1，失败不动', () async {
    final dir = _tmpDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    // 预置 2 张已就绪 + 1 个 .tmp 半成品（不算）
    File('${dir.path}${Platform.pathSeparator}av-0.png').writeAsBytesSync([1]);
    File('${dir.path}${Platform.pathSeparator}av-1.png').writeAsBytesSync([1]);
    File('${dir.path}${Platform.pathSeparator}av-2.png.tmp').writeAsBytesSync([1]);
    final pool = _pool(dir: dir, size: 4, batchSize: 4, concurrency: 4);
    await pool.start();
    final p = pool.progress.value;
    expect(p.enabled, isTrue);
    expect(p.filled, 4, reason: '初值 2（tmp 不算）+ 本次成功 2（另 2 格已由预置占用索引）');
  });
}

const kPng1x1 = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
