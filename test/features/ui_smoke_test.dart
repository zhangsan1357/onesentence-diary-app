// UI 冒烟测试：demo 数据驱动全页面（M2-b 的结构/行为验证）+ 身份引导页/同步横幅（2026-11-14）。


import 'package:diary_app/core/config/app_defaults.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/features/compose/compose_page.dart';
import 'package:diary_app/features/onboarding/onboarding_page.dart';
import 'package:diary_app/main.dart';
import 'package:diary_app/widgets/animal_avatar.dart';
import 'package:diary_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  // mockup v2 手机视口（390×844，dpr=1）——与真实 iPhone 逻辑尺寸一致
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: DiaryApp()));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  // 标签/心情显示配置是全局静态表：测试间复位，避免改色用例污染后续用例
  setUp(() {
    AppDefaults.tagColorOverrides = {};
    AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    AppDefaults.serverMoods = const [];
  });
  tearDown(() {
    AppDefaults.tagColorOverrides = {};
    AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    AppDefaults.serverMoods = const [];
  });

  testWidgets('feed：标题/空今日卡/长文折叠/评论徽标渲染', (tester) async {
    await _pumpHome(tester);
    // 页面标题 + tab 标签各一个
    expect(find.text('时光'), findsNWidgets(2));
    // demo 数据里没有"今天"的条目 → 空卡（输入入口与底部发布键重复，已移除）
    expect(find.text('今天还没写点什么'), findsOneWidget);
    expect(find.text('写一条'), findsNothing);
    // 长文折叠按钮（11-12 那条远超 6 行）
    expect(find.text('展开全文'), findsWidgets);
    // 评论数徽标（11-12 首条 2 条评论）
    expect(find.text('2'), findsWidgets);
    // 时间等宽前缀
    expect(find.text('21:14'), findsOneWidget);
    // 天卡片日期盒（11-12 与 11-11 两张卡）
    expect(find.text('12'), findsWidgets);
    expect(find.textContaining('年11月'), findsNWidgets(2));
  });

  testWidgets('feed：评论展开——本地头像渲染 + 时间标准格式（存量 HH:mm 补条目日期）',
      (tester) async {
    await _pumpHome(tester);
    // 天卡头像（§5.12 本地化 v5）：测试环境池无文件 → 默认人像，11-12 与 11-11 两张卡
    expect(find.byIcon(Icons.person), findsNWidgets(2));
    // 展开首条（11-12，2 条评论）的评论列表
    await tester.tap(find.byIcon(Icons.mode_comment_outlined).first);
    await tester.pumpAndSettle();
    // 每条评论一个动物头像（2 天卡默认人像 + 2 评论 AnimalAvatar）
    expect(find.byIcon(Icons.person), findsNWidgets(2));
    expect(find.byType(AnimalAvatar), findsNWidgets(2));
    // 存量 HH:mm 评论补条目日期 → 标准格式
    expect(find.text('2026-11-12 21:30'), findsOneWidget);
    expect(find.text('2026-11-12 22:05'), findsOneWidget);
  });

  testWidgets('feed：展开全文切换', (tester) async {
    await _pumpHome(tester);
    final btn = find.text('展开全文').first;
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    await tester.tap(find.text('收起').first);
    await tester.pumpAndSettle();
    expect(find.text('展开全文'), findsWidgets);
  });

  testWidgets('feed：下拉刷新头——拖拽出现箭头（仿原生：拉距旋转→松手转圈→已同步）',
      (tester) async {
    await _pumpHome(tester);
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60)); // 越过触发距离 90 → armed
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget,
        reason: '拖拽阶段应显示旋转箭头');
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle(); // demo 同步即时完成 → 刷新头收回
  });

  testWidgets('feed：关键词搜索（正文/标签命中 + 无结果态 + 关闭还原）', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.search_outlined), warnIfMissed: false);
    await tester.pumpAndSettle();
    // 正文命中：光棍节（11-11 那条）→ 其余条目不再显示
    await tester.enterText(
        find.widgetWithText(TextField, '搜索关键词（正文 / 标签）'), '光棍节');
    await tester.pumpAndSettle();
    expect(find.textContaining('光棍节'), findsWidgets);
    expect(find.textContaining('多肉'), findsNothing);
    // 标签命中：摄影（11-08 那条正文是多肉换盆，仅标签含摄影）
    await tester.enterText(
        find.widgetWithText(TextField, '搜索关键词（正文 / 标签）'), '摄影');
    await tester.pumpAndSettle();
    expect(find.textContaining('多肉'), findsWidgets);
    // 无结果态
    await tester.enterText(
        find.widgetWithText(TextField, '搜索关键词（正文 / 标签）'), '不存在的词xyz');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到'), findsOneWidget);
    // 清空 + 关闭搜索 → 还原全量（断言首屏内的卡片；懒加载列表折叠线下不构建）
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('烤红薯'), findsWidgets);
    await tester.tap(find.byIcon(Icons.search_outlined), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '搜索关键词（正文 / 标签）'), findsNothing);
  });

  testWidgets('长按日记 → 删除（二次确认 → 条目消失）', (tester) async {
    await _pumpHome(tester);
    await tester.longPress(find.text('21:14'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('编辑'), findsOneWidget);
    // 删除按钮在编辑页底部（滚动到折叠线下）
    await tester.scrollUntilVisible(find.text('删除这条日记'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('删除这条日记'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // 二次确认弹窗：先取消不删（弹窗「取消」与顶栏「取消」重名 → 限定弹窗子树）
    expect(find.text('删除这条日记'), findsNWidgets(2)); // 页内按钮 + 弹窗标题
    await tester.tap(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('取消')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    // 再次删除并确认
    await tester.tap(find.text('删除这条日记'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('已删除'), findsOneWidget);
    // 回时光流：21:14 那条不再出现
    expect(find.text('21:14'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('日历：翻月 + 休班徽章 + 统计', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.textContaining('本月'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    // 翻到 2026-10：有国庆休与调休班
    await tester.tap(find.byIcon(Icons.chevron_left), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('休'), findsWidgets);
    expect(find.text('班'), findsOneWidget);
  });

  testWidgets('回忆：hero 连续天数 + 随机翻一条', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.history), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('那些被留下的话'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    expect(find.text('天\n连续记录'), findsOneWidget);
    expect(find.text('换一条'), findsOneWidget);
    // 随机翻一条切换（mockup POOL 第 2 条）
    await tester.tap(find.text('换一条'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('食堂阿姨'), findsOneWidget);
  });

  testWidgets('我的：统计与分组行', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.account_circle_outlined),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    // §5.14 非功能解释行删除（端到端加密/多设备共享信息弹窗行）
    expect(find.text('端到端加密'), findsNothing);
    expect(find.text('多设备共享'), findsNothing);
    expect(find.text('锁定保护'), findsOneWidget);
    // 身份凭证保存后不再展示（2026-11-14 调整）：恢复词行已移除
    expect(find.text('恢复词'), findsNothing);
    expect(find.text('新设备登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
    expect(find.text('更改注册名'), findsOneWidget); // 晨 19 §5.10 入口打开
    expect(find.text('更换 12 词主密钥'), findsOneWidget);
    expect(find.text('更换锁定口令'), findsOneWidget,
        reason: '原「更换主密钥」行澄清（重包裹封套不换钥）');
    expect(find.text('自动上锁'), findsOneWidget);
    expect(find.text('每日提醒'), findsOneWidget);
    expect(find.text('Pushover 服务端推送'), findsOneWidget);
    expect(find.text('标签管理'), findsOneWidget);
    expect(find.text('心情管理'), findsOneWidget);
    // 头像库进度行（§5.12）：测试/web 环境池禁用 → 「未启用」
    expect(find.text('头像库'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);
    expect(find.text('导出全部日记'), findsOneWidget);
    expect(find.text('立即锁定'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    // §5.14：底部脚注删除
    expect(find.textContaining('一句话日记 v2'), findsNothing);
  });

  testWidgets('发布流：FAB 打开 → 心情反选 → 标签回车 → 发布态', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.edit).last, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('写一条'), findsOneWidget); // 仅发布页标题（空卡入口已去重）
    expect(find.text('此刻的心情'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.textContaining('端到端加密'), findsOneWidget);
    // 心情选择/反选（选中后再次点击取消）
    await tester.tap(find.text('开心'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开心'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // 可点选标签 chips：默认模板 + demo 条目里的云端标签（点按即选，无需键盘）
    // （限定发布页子树——身后 feed 的 TagChip 同名文本不参与计数）
    final compose = find.byType(ComposePage);
    expect(
        find.descendant(of: compose, matching: find.text('#吐槽')),
        findsOneWidget); // 默认模板（demo 条目已含 → 去重）
    expect(
        find.descendant(of: compose, matching: find.text('#工作')),
        findsOneWidget);
    await tester.tap(
        find.descendant(of: compose, matching: find.text('#趣事')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: compose, matching: find.text('#趣事')),
        findsNWidgets(2)); // 建议 chip + 已选 chip
    await tester.tap(
        find.descendant(of: compose, matching: find.text('#趣事')).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: compose, matching: find.text('#趣事')),
        findsOneWidget); // 再点取消
    // 文本输入框补录新标签（done 动作添加）
    final tagField = find.widgetWithText(TextField, '新标签（可选）');
    await tester.tap(tagField);
    await tester.pumpAndSettle();
    await tester.enterText(tagField, '测试标签');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('#测试标签'), findsOneWidget);
    // 正文输入后发布文案仍在（可点态由颜色控制）
    await tester.enterText(
        find.widgetWithText(TextField, '今天怎么样？写点什么……'), '今天写一句话。');
    await tester.pumpAndSettle();
    expect(find.text('发布'), findsOneWidget);
  });

  testWidgets('TagChip：同名标签同色（哈希稳定）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: TagChip('工作'))),
    ));
    expect(find.text('#工作'), findsOneWidget);
  });

  testWidgets('我的：标签管理弹层（web const 列表排序崩溃回归）', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.account_circle_outlined),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签管理'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // defaultTags（const 列表）排序后渲染为行列表（非懒加载，全部可查）
    expect(find.text('#吐槽'), findsOneWidget);
    expect(find.text('#趣事'), findsOneWidget);
    expect(find.text('#流水账'), findsOneWidget);
    await tester.tap(find.text('知道了'), warnIfMissed: false);
    await tester.pumpAndSettle();
  });

  testWidgets('我的：标签调色板改色（覆盖稳定哈希）+ 心情管理列表', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.account_circle_outlined),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签管理'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // 进 #吐槽 编辑弹层 → 选粉色 → 弹层关闭，列表行颜色即时更新
    await tester.tap(find.text('#吐槽'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('swatch-auto')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swatch-pink')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    final t = tester.widget<Text>(find.text('#吐槽'));
    expect(t.style!.color, const Color(0xFFFF2D55), reason: '粉色覆盖生效');
    await tester.tap(find.text('知道了'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // 心情管理：默认 6 心情 + 新增入口
    await tester.tap(find.text('心情管理'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('开心'), findsOneWidget);
    expect(find.text('新增心情'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    await tester.tap(find.text('知道了'), warnIfMissed: false);
    await tester.pumpAndSettle();
  });

  testWidgets('身份引导：生成身份页（12 宫格优先/随机生成/黄金向量/注册名校验/创建/模式切换）',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? createdSecret;
    String? createdName;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingPage(
        mode: OnboardingMode.create,
        onCreate: (secret, name) async {
          createdSecret = secret;
          createdName = name;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('首次启动 · 生成身份'), findsOneWidget);
    expect(find.textContaining('丢失后将无法找回本机日记'), findsOneWidget);
    // 默认 12 宫格逐格输入（统一入口）：12 宫格 + 注册名 = 13 个输入框，
    // 未就绪时派生密钥为占位提示，旧的「自动生成/手动切换」入口已移除
    expect(find.byType(TextField).evaluate().length, 13);
    expect(find.text('恢复词有效后自动生成'), findsOneWidget);
    expect(find.byKey(const ValueKey('derived-key')), findsNothing);
    expect(find.text('已有恢复词？手动输入 12 词'), findsNothing);
    expect(find.text('改用自动生成的恢复词'), findsNothing);
    // 随机生成：12 词填入宫格 → 派生密钥同屏出现（64 hex）
    await tester.scrollUntilVisible(find.text('随机生成 12 词'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('随机生成 12 词'), warnIfMissed: false);
    await tester.pumpAndSettle();
    final genFirst =
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(genFirst, isNotEmpty, reason: '随机生成的第 1 词应填入第 1 格');
    final keyGen = tester
        .widget<SelectableText>(find.byKey(const ValueKey('derived-key')))
        .data!;
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(keyGen), isTrue, reason: keyGen);
    // 黄金向量：逐格输入 → 派生密钥切换为对应 seed
    const golden = '的 的 的 的 的 的 的 的 的 的 的 在';
    final goldenWords = golden.split(' ');
    for (var i = 0; i < 12; i++) {
      await tester.enterText(find.byType(TextField).at(i), goldenWords[i]);
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('derived-key')))
          .data,
      '7571379a07dc7c0f699665f43477353c89aa80036f9b66a33e79cbce612cd1e2',
    );
    // 注册名为空 → 按钮禁用（onCreate 不触发）
    await tester.scrollUntilVisible(find.text('创建身份'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('创建身份'), warnIfMissed: false);
    await tester.pump();
    expect(createdName, isNull);
    // 输入注册名 → 创建回调收到逐格拼接短语
    await tester.enterText(find.widgetWithText(TextField, '注册名'), '测试用户');
    await tester.pump();
    await tester.scrollUntilVisible(find.text('创建身份'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('创建身份'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(createdName, '测试用户');
    expect(createdSecret, golden);
    // 切到「新设备登录」模式
    await tester.scrollUntilVisible(find.text('已有身份？在新设备登录'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('已有身份？在新设备登录'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('同一身份，随处同步'), findsOneWidget);
    expect(find.text('导入并同步'), findsOneWidget);
    // 返回生成身份
    await tester.tap(find.text('返回 · 生成新身份'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('首次启动 · 生成身份'), findsOneWidget);
  });

  testWidgets('身份引导：补设注册名页（存量身份一次性设置）', (tester) async {
    String? setName;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingPage(
        mode: OnboardingMode.nameOnly,
        onSetName: (name) async => setName = name,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('起一个注册名'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '注册名'), '老用户');
    await tester.pump();
    await tester.tap(find.text('完成设置'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(setName, '老用户');
  });

  testWidgets('feed：同步失败横幅（口令过期文案 + 忽略）', (tester) async {
    await _pumpHome(tester);
    final ctx = tester.element(find.text('时光').first);
    final container = ProviderScope.containerOf(ctx, listen: false);
    container.read(appSessionProvider.notifier).state = container
        .read(appSessionProvider)
        .copyWith(syncError: '动态口令无效或已过期（请检查系统时间是否准确）');
    await tester.pumpAndSettle();
    expect(find.text('同步失败 · 口令过期'), findsOneWidget);
    expect(find.textContaining('本机系统时间是否准确'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    // 忽略 → 横幅消失
    await tester.tap(find.text('忽略'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('同步失败 · 口令过期'), findsNothing);
  });

  testWidgets('ToastHost：挂载即有消息 → 1.9s 后自动关闭（修登录 toast 常驻）',
      (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ToastHost(
            message: '身份已登录 · 同步中',
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    ));
    expect(find.text('身份已登录 · 同步中'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(dismissed, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(dismissed, 1, reason: '挂载即调度关闭（此前仅 didUpdateWidget 调度导致常驻）');
  });

  testWidgets('ToastHost：消息切换重置定时器（旧定时作废，不提前关新消息）',
      (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ToastHost(message: 'A', onDismiss: () => dismissed++),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ToastHost(message: 'B', onDismiss: () => dismissed++),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(dismissed, 0, reason: 'A 的旧定时器已被取消');
    expect(find.text('B'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    expect(dismissed, 1);
  });

  testWidgets('ToastHost：挂载时无消息 → 不调度、不回调', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ToastHost(message: null, onDismiss: () => dismissed++),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 3));
    expect(dismissed, 0);
  });

  testWidgets('长按日记 → 编辑预填 → 保存（整条重加密替换）', (tester) async {
    await _pumpHome(tester);
    // 首条 demo 条目的时间前缀（11-12 · 21:14）
    await tester.longPress(find.text('21:14'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    // 预填 = 被长按条目的正文（动态取，避免 demo 文案耦合）
    final ctx = tester.element(find.text('21:14'));
    final target = ProviderScope.containerOf(ctx, listen: false)
        .read(appSessionProvider)
        .entries
        .firstWhere((e) => e.payload.time == '21:14')
        .payload
        .text;
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    expect(tf.controller!.text, target);
    // 保存（demo 模式本地替换 + toast）
    await tester.tap(find.text('保存'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('已更新'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // toast 自动关闭 Timer 走完
  });

  testWidgets('主题：三档循环切换 浅色→深色→跟随', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.byIcon(Icons.account_circle_outlined),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    // 外观行在页面底部，先滚动到可见
    await tester.scrollUntilVisible(
      find.text('外观'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('浅色'), findsOneWidget);
    expect(
        Theme.of(tester.element(find.text('外观'))).brightness,
        Brightness.light);
    await tester.tap(find.text('外观'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('深色'), findsOneWidget);
    expect(
        Theme.of(tester.element(find.text('外观'))).brightness,
        Brightness.dark);
  });
}
