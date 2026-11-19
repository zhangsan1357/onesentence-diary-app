// 我的页：3 统计卡 + 安全组/通知组/配置组/数据组（01 §2.4，无 Linkey）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/app_icon.dart';

import '../../core/session/app_session.dart';
import '../../core/util/avatar_pool.dart';
import '../../core/util/errors.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/common.dart';
import 'dialogs.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);
    final notifier = ref.read(appSessionProvider.notifier);

    final (localTotal, tagCount) = totalAndTags(state.entries);
    // 服务端统计优先（§5.10），失败/离线回落本地计算（定义一致）
    final streak = state.demo
        ? 23
        : (state.stats?.streak ?? computeStreak(state.entries, DateTime.now()));
    final total = state.demo
        ? localTotal
        : (state.stats?.total ?? localTotal);
    final themeName = switch (state.theme) {
      ThemeSetting.auto => '跟随系统',
      ThemeSetting.light => '浅色',
      ThemeSetting.dark => '深色',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18, headerTopPad(context), 18, 0),
            child: Text('我的',
                style: TextStyle(
                    fontSize: 33,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                    color: Tokens.label(b))),
          ),
          const SizedBox(height: 14),
          // 3 统计卡
          Row(
            children: [
              for (final (n, v) in [
                ('$streak', '连续天数'),
                ('$total', '总条数'),
                ('$tagCount', '标签'),
              ])
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Tokens.card(b),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .04),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(n,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Tokens.label(b))),
                        const SizedBox(height: 2),
                        Text(v,
                            style: TextStyle(
                                fontSize: 11, color: Tokens.label2(b))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // 安全组（§5.14 重分组：锁定/解锁语义归一组）
          IosGroup(children: [
            IosRow(
              icon: Icons.enhanced_encryption_outlined,
              iconBg: Tokens.orange(b),
              title: '锁定保护',
              switchValue: state.lockEnabled,
              onSwitch: (v) async {
                if (v) {
                  final pass = await showSetPasscodeDialog(context);
                  if (pass != null) {
                    await notifier.setLockEnabled(true, passcode: pass);
                  }
                } else {
                  await notifier.setLockEnabled(false);
                }
              },
            ),
            IosRow(
              icon: Icons.timer_outlined,
              iconBg: Tokens.green,
              title: '自动上锁',
              value: state.autoLockMin == 0 ? '关闭' : '${state.autoLockMin} 分钟',
              onTap: () => showAutoLockDialog(context, ref),
            ),
            IosRow(
              icon: Icons.face,
              iconBg: const Color(0xFF5E5CE6),
              title: '面容 ID 解锁',
              value: state.bioUnlock ? '已开启' : null,
              valueColor: Tokens.green,
              switchValue: state.bioUnlock,
              onSwitch: state.demo
                  ? null
                  : (v) async {
                      try {
                        if (v) {
                          await notifier.enableBioUnlock();
                        } else {
                          await notifier.disableBioUnlock();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showInfoDialog(context, '面容 ID 解锁',
                              '设置失败：${friendlyError(e)}');
                        }
                      }
                    },
            ),
            IosRow(
              icon: Icons.key,
              iconBg: const Color(0xFF5E5CE6),
              title: '更换锁定口令',
              onTap: () => showRekeyDialog(context, ref),
            ),
          ]),
          // 身份组（§5.14 重分组：注册名/主密钥/新设备）
          IosGroup(children: [
            IosRow(
              icon: Icons.badge_outlined,
              iconBg: const Color(0xFF0A84FF),
              title: '更改注册名',
              value: state.userId,
              onTap: () => showRenameIdentityDialog(context, ref),
            ),
            IosRow(
              icon: Icons.vpn_key_outlined,
              iconBg: const Color(0xFFFF9500),
              title: '更换 12 词主密钥',
              onTap: () => showRotateIdentityDialog(context, ref),
            ),
            IosRow(
              icon: Icons.login,
              iconBg: const Color(0xFF34C759),
              title: '新设备登录',
              onTap: () => showLoginIdentityDialog(context, ref),
            ),
          ]),
          // 通知组
          IosGroup(children: [
            IosRow(
              icon: Icons.notifications_none,
              iconBg: const Color(0xFFFF3B30),
              title: '每日提醒',
              value: '21:30',
              switchValue: state.notifyEnabled,
              onSwitch: (v) => notifier.setNotify(v),
            ),
            IosRow(
              icon: Icons.notifications_active_outlined,
              iconBg: Tokens.orange(b),
              title: 'Pushover 服务端推送',
              value: '测试',
              onTap: () async {
                try {
                  await notifier.pushoverTest();
                } on ApiException catch (e) {
                  if (context.mounted) {
                    showInfoDialog(context, 'Pushover',
                        '${e.code == 500 ? "服务端未配置 PUSHOVER_TOKEN" : "发送失败"}：${e.message}');
                  }
                } catch (e) {
                  if (context.mounted) {
                    showInfoDialog(context, 'Pushover', '发送失败：${friendlyError(e)}');
                  }
                }
              },
            ),
          ]),
          // 配置组
          IosGroup(children: [
            IosRow(
              icon: Icons.dns_outlined,
              iconBg: const Color(0xFF34C759),
              title: '服务端地址',
              value: Uri.tryParse(state.serverBase)?.host ?? state.serverBase,
              onTap: () => showServerBaseDialog(context, ref),
            ),
            IosRow(
              icon: Icons.tag,
              iconBg: const Color(0xFF30B0C7),
              title: '标签管理',
              onTap: () => showTagConfigDialog(context, ref),
            ),
            IosRow(
              icon: Icons.emoji_emotions_outlined,
              iconBg: const Color(0xFFAF52DE),
              title: '心情管理',
              onTap: () => showMoodConfigDialog(context, ref),
            ),
            // 头像库更新进度（晨 19 §5.12）：预下载池后台仅 Wi-Fi 填充，
            // 天卡渲染只走本地（缺失默认人像）——本行纯查看，无操作
            ValueListenableBuilder<PoolProgress>(
              valueListenable: ref.watch(avatarPoolProvider).progress,
              builder: (context, p, _) => IosRow(
                icon: Icons.image_outlined,
                iconBg: const Color(0xFFFFCC00),
                title: '头像库',
                value: !p.enabled
                    ? '未启用'
                    : p.filled >= p.total
                        ? '已就绪 ${p.filled}/${p.total}'
                        : '更新中 ${p.filled}/${p.total}',
              ),
            ),
            // App 图标切换（2026-11-16，iOS 备用图标机制；web 预览不显示）
            if (AppIcon.supported)
              IosRow(
                icon: Icons.app_shortcut_outlined,
                iconBg: const Color(0xFFFF9500),
                title: 'App 图标',
                onTap: () => showAppIconDialog(context),
              ),
          ]),
          // 数据组
          IosGroup(children: [
            IosRow(
              icon: Icons.download_outlined,
              iconBg: Tokens.orange(b),
              title: '导出全部日记',
              onTap: () => showExportDialog(context, ref),
            ),
            IosRow(
              icon: Icons.lock,
              iconBg: const Color(0xFFFF2D55),
              title: '立即锁定',
              onTap: () => notifier.lock(),
            ),
            IosRow(
              icon: Icons.auto_awesome,
              iconBg: const Color(0xFF5856D6),
              title: '外观',
              value: themeName,
              onTap: () async {
                final order = ThemeSetting.values;
                final next =
                    order[(order.indexOf(state.theme) + 1) % order.length];
                await notifier.setTheme(next);
              },
            ),
            IosRow(
              icon: Icons.logout,
              iconBg: const Color(0xFFFF453A),
              title: '注销账号',
              onTap: () => showLogoutDialog(context, ref),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
