// App 图标切换（2026-11-16）：弹窗选项/当前勾选 + 通道调用（含恢复默认的空串映射）。
// MethodChannel mock：不依赖原生侧，真机行为由 AppDelegate.swift 的 AppIconPlugin 承担。
import 'package:diary_app/features/me/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.icon');
  final calls = <MethodCall>[];
  String? current;

  setUp(() {
    calls.clear();
    current = null;
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        if (call.method == 'get') return current;
        if (call.method == 'set') {
          final name = (call.arguments as Map)['name'] as String;
          current = name.isEmpty ? null : name;
        }
        return null;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppIconDialog(ctx),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('弹窗：默认 + 三个样例 + 当前项勾选', (tester) async {
    current = 'AppIconPatrick';
    await open(tester);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('暗夜少女'), findsOneWidget);
    expect(find.text('派大星'), findsOneWidget);
    expect(find.text('海绵宝宝'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: '仅当前项一个勾');
    expect(calls.map((c) => c.method), contains('get'),
        reason: '打开时查询了当前图标');
  });

  testWidgets('点击样例：通道收到 set + 弹窗关闭（系统确认框由 iOS 弹出）', (tester) async {
    await open(tester);
    await tester.tap(find.text('海绵宝宝'));
    await tester.pumpAndSettle();
    final setCall = calls.lastWhere((c) => c.method == 'set');
    expect(setCall.arguments, {'name': 'AppIconSponge'});
    expect(find.text('App 图标'), findsNothing, reason: '成功后自动关闭');
  });

  testWidgets('点击默认：name 传空串（原生映射 setAlternateIconName(nil)）', (tester) async {
    current = 'AppIconSponge';
    await open(tester);
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();
    final setCall = calls.lastWhere((c) => c.method == 'set');
    expect(setCall.arguments, {'name': ''});
    expect(find.text('App 图标'), findsNothing);
  });
}
