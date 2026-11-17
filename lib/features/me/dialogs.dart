// 我的页弹层：锁定开关 / 更换主密钥 / 新设备登录 / 多设备共享说明 / 服务端地址 / 标签 / 心情 / 导出。
// 身份凭证（恢复词/派生密钥）只在引导页出现，保存后任何页面不再显示。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_icon.dart';
import '../../core/config/app_defaults.dart';
import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/errors.dart';

import '../../features/theme/tokens.dart';

Future<void> showInfoDialog(BuildContext context, String title, String body) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// App 图标切换（2026-11-16，iOS 备用图标机制）：点击即换，iOS 系统会弹确认框。
/// 「默认」= 恢复 Flutter 图标；成功后关弹窗（系统确认框随后自行弹出）。
Future<void> showAppIconDialog(BuildContext context) async {
  final current = await AppIcon.current();
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => _AppIconDialog(current: current),
  );
}

class _AppIconDialog extends StatefulWidget {
  final String? current;
  const _AppIconDialog({required this.current});

  @override
  State<_AppIconDialog> createState() => _AppIconDialogState();
}

class _AppIconDialogState extends State<_AppIconDialog> {
  // 打开时定格：成功即弹窗关闭，失败保持旧值
  late final String? _current = widget.current;
  String? _busy; // 正在设置的那格（null 格子用哨兵值，避免与「当前=null」混淆）
  String? _error;

  static const _defaultTile = '__default__';

  Future<void> _pick(String? name) async {
    setState(() => _busy = name ?? _defaultTile);
    try {
      await AppIcon.set(name);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = '设置失败：${friendlyError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    Widget tile(String? name, String label, String? asset) {
      final selected = name == _current || (name == null && _current == null);
      final busy = _busy == (name ?? _defaultTile);
      return Expanded(
        child: InkWell(
          onTap: busy ? null : () => _pick(name),
          borderRadius: BorderRadius.circular(12),
          child: Column(children: [
            Stack(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: selected ? Tokens.blue(b) : Tokens.sep(b),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: asset != null
                      ? Image.asset(asset, width: 56, height: 56,
                          fit: BoxFit.cover)
                      : Icon(Icons.flutter_dash,
                          size: 30, color: Tokens.label2(b)),
                ),
              ),
              if (selected)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(Icons.check_circle,
                      size: 18, color: Tokens.blue(b)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? Tokens.label(b) : Tokens.label2(b))),
            if (busy)
              const SizedBox(
                height: 2,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ]),
        ),
      );
    }

    return AlertDialog(
      title: const Text('App 图标'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('点击即更换，iOS 会弹确认框。',
            style: TextStyle(fontSize: 12, color: Tokens.label2(b))),
        const SizedBox(height: 14),
        Row(children: [
          tile(null, '默认', null),
          for (final (name, label, asset) in AppIcon.choices)
            tile(name, label, asset),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(fontSize: 12, color: Tokens.red(b))),
        ],
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }
}

/// 更换主密钥（仅重包裹私钥封套，数据零重加密）。
Future<void> showRekeyDialog(BuildContext context, WidgetRef ref) async {
  final old = TextEditingController();
  final next = TextEditingController();
  final next2 = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更换主密钥'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('仅重包裹私钥封套，历史数据无需重加密。', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          _passField(old, '当前口令'),
          _passField(next, '新口令（≥6 位）'),
          _passField(next2, '再次输入新口令'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () async {
            if (next.text.length < 6 || next.text != next2.text) {
              return;
            }
            try {
              await ref
                  .read(appSessionProvider.notifier)
                  .rekey(old.text, next.text);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                showInfoDialog(ctx, '更换失败', friendlyError(e));
              }
            }
          },
          child: const Text('确认更换'),
        ),
      ],
    ),
  );
}

Widget _passField(TextEditingController c, String hint) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        obscureText: true,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );

/// 自动上锁：关闭/1 分钟/5 分钟（03 §6）。
Future<void> showAutoLockDialog(BuildContext context, WidgetRef ref) async {
  final state = ref.read(appSessionProvider);
  await showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('自动上锁'),
      children: [
        for (final m in [0, 1, 5])
          SimpleDialogOption(
            onPressed: () async {
              await ref.read(appSessionProvider.notifier).setAutoLock(m);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Icon(
                  state.autoLockMin == m
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: m == state.autoLockMin
                      ? Tokens.blue(Theme.of(ctx).brightness)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(m == 0 ? '关闭' : '$m 分钟'),
              ],
            ),
          ),
      ],
    ),
  );
}

/// 新设备登录（②）：同一注册名 + 同一份恢复词（或派生密钥）→ 校验 → 全量同步。
/// 服务端校验身份二元组（同 userId 必须同 userKey），拒绝时 SnackBar 展示原因。
Future<void> showLoginIdentityDialog(
    BuildContext context, WidgetRef ref) async {
  final lockEnabled = ref.read(appSessionProvider).lockEnabled;
  final nameCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String? error;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('新设备登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入同一个注册名 + 同一份 12 词恢复词（或其派生密钥）。'
              '校验通过后本机自动同步全部加密数据并在本地解密。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textInputAction: TextInputAction.next, // 多字段弹窗键盘动作微调（§4.7）
              decoration: const InputDecoration(labelText: '注册名'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretCtrl,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '恢复词（12 词）或派生密钥',
                hintText: '粘贴同一份 12 个恢复词，或 64 位派生密钥',
              ),
            ),
            if (lockEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: '本机口令（≥6 位）'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              error ??
                  '登录将切换本机身份：当前身份的本地索引清空并重新同步'
                  '（旧密文不可读，数据仍在服务端，重新登录原身份可恢复）。',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: error == null ? null : const Color(0xFFFF453A)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              // 前置校验（弹窗内联）；正式登录弹窗后执行，错误走外层 SnackBar
              if (nameCtrl.text.trim().isEmpty) {
                setState(() => error = '请输入注册名');
                return;
              }
              if (secretCtrl.text.trim().isEmpty) {
                setState(() => error = '请输入恢复词或派生密钥');
                return;
              }
              if (lockEnabled && passCtrl.text.trim().length < 6) {
                setState(() => error = '口令不足 6 位');
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref.read(appSessionProvider.notifier).loginIdentity(
                      nameCtrl.text,
                      secretCtrl.text,
                      passcode: passCtrl.text.trim(),
                    );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('登录失败：${friendlyError(e)}')));
                }
              }
            },
            child: const Text('导入并同步'),
          ),
        ],
      ),
    ),
  );
}

/// 多设备共享说明（④）+ 关于动态口令（⑤）。
Future<void> showMultiDeviceDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('多设备共享'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '你的日记以端到端加密保存在服务器：服务器只见密文，'
            '解密密钥与解密结果只存在于你的设备上。每台设备独立登录、互不踢下线；'
            '数据按注册名共享，增删改全量同步。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text('关于动态口令',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            '每次请求会自动附带一个每 5 分钟变化的一次性口令'
            '（由你的密钥本地推算），防止他人截获令牌后冒用。'
            '它无需记忆、无需输入，全部自动完成。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
      ],
    ),
  );
}

/// 注销账号（本机）：二次确认后清除身份与本地索引，回到生成身份引导。
/// 服务端密文保留；恢复词不再展示 → 确认文案强提示先妥善保管。
Future<void> showLogoutDialog(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('注销账号'),
      content: const Text(
        '将清除本机身份密钥与全部本地数据索引并退出登录。'
        '服务端密文保留：凭同一注册名 + 12 词恢复词（或派生密钥）'
        '可在登录页重新找回。\n\n'
        '注意：恢复词与派生密钥只在创建时显示过一次，'
        '请确认已在别处妥善保存，否则注销后将无法再进入该身份。',
        style: TextStyle(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        TextButton(
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF453A)),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认注销'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(appSessionProvider.notifier).logout();
  }
}

/// 调色板 8 色序（AppDefaults.tagColorHex 的展示顺序）。
const _paletteOrder = [
  'blue',
  'green',
  'red',
  'orange',
  'purple',
  'gray',
  'pink',
  'cyan',
];

/// 心情编辑可选 emoji。
const _emojiChoices = [
  '😀', '😅', '😂', '🥰', '😍', '😎', '🥳', '😇',
  '🙃', '😢', '😭', '😤', '😠', '🤯', '😱', '🤒',
  '😴', '🤔', '😳', '🤐', '🚀', '🌈', '🔥', '🌙',
  '☕', '🍀', '⚡', '🎯',
];

/// 标签管理：标签库增删改查 + 8 色调色板（覆盖稳定哈希自动色，设备本地保存）。
Future<void> showTagConfigDialog(BuildContext context, WidgetRef ref) async {
  final addCtrl = TextEditingController();
  String? addError;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final state = ref.read(appSessionProvider);
        // 标签库（预设，初始含默认三项）∪ 实际日记出现过的标签
        final tags = <String>{
          ...AppDefaults.tagPresets,
          for (final e in state.entries)
            if (!e.deleted) ...e.payload.tags,
        }.toList()
          ..sort();
        return AlertDialog(
          title: const Text('标签管理'),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: addCtrl,
                        decoration: const InputDecoration(
                          labelText: '新增标签预设',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(appSessionProvider.notifier)
                              .addTagPreset(addCtrl.text);
                          addCtrl.clear();
                          setState(() => addError = null);
                        } on FormatException catch (e) {
                          setState(() => addError = e.message);
                        }
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
                if (addError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(addError!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFFF453A))),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: tags.isEmpty
                      ? const Center(child: Text('还没有标签'))
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final t in tags)
                                ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppDefaults.tagColor(t),
                                    ),
                                  ),
                                  title: Text('#$t',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppDefaults.tagColor(t))),
                                  subtitle: Text(
                                    AppDefaults.tagPresets.contains(t)
                                        ? '预设'
                                        : '来自日记',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: () => _showTagEditSheet(
                                      ctx, ref, t, setState),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        );
      },
    ),
  );
}

/// 单个标签编辑（底部弹层）：调色板选色 / 「自动」恢复哈希色 / 删除预设。
Future<void> _showTagEditSheet(
  BuildContext ctx,
  WidgetRef ref,
  String tag,
  void Function(void Function()) refreshDialog,
) async {
  final b = Theme.of(ctx).brightness;
  final isPreset = AppDefaults.tagPresets.contains(tag);
  await showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('标签颜色 · #$tag',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Tokens.label(b))),
            const SizedBox(height: 6),
            Text('不选即为自动色（同名标签永远同色）',
                style: TextStyle(fontSize: 12, color: Tokens.label2(b))),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _swatch(
                  null,
                  AppDefaults.tagColorOverrides[tag] == null,
                  '自动',
                  () async {
                    await ref
                        .read(appSessionProvider.notifier)
                        .setTagColor(tag, null);
                    refreshDialog(() {});
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                  key: const ValueKey('swatch-auto'),
                ),
                for (final cn in _paletteOrder)
                  _swatch(
                    Color(AppDefaults.tagColorHex[cn]!),
                    AppDefaults.tagColorOverrides[tag] == cn,
                    null,
                    () async {
                      await ref
                          .read(appSessionProvider.notifier)
                          .setTagColor(tag, cn);
                      refreshDialog(() {});
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    key: ValueKey('swatch-$cn'),
                  ),
              ],
            ),
            if (isPreset) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF453A)),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除该预设（不影响已写入日记的标签）'),
                  onPressed: () async {
                    await ref
                        .read(appSessionProvider.notifier)
                        .removeTagPreset(tag);
                    refreshDialog(() {});
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 18),
              Text('该标签来自已有日记：可改显示色；要移除请编辑对应日记的标签。',
                  style: TextStyle(fontSize: 12, color: Tokens.label3(b))),
            ],
          ],
        ),
      ),
    ),
  );
}

/// 调色板色块：null = 「自动」占位。
Widget _swatch(Color? color, bool selected, String? label, VoidCallback onTap,
    {Key? key}) {
  if (color == null) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
              color: selected
                  ? const Color(0xFF007AFF)
                  : const Color(0x338E8E93),
              width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label ?? '',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
      ),
    );
  }
  return GestureDetector(
    key: key,
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: selected
            ? Border.all(width: 2.5, color: Colors.white)
            : null,
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 8)]
            : null,
      ),
    ),
  );
}

/// 开启锁定保护：设置口令（≥6 位）。仅重包裹私钥，数据零重加密。
Future<String?> showSetPasscodeDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  String? result;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('开启锁定保护'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: '口令（≥6 位）'),
          ),
          const SizedBox(height: 8),
          const Text(
            '开启后：退出/超时需口令解锁，私钥改为口令包裹存储；关闭可随时免口令直进。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () {
            final v = ctrl.text.trim();
            if (v.length < 6) return; // 不足 6 位不关闭弹窗
            result = v;
            Navigator.pop(ctx);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result;
}

/// 服务端地址配置：所有接口调用拼接此地址，不区分构建环境。
Future<void> showServerBaseDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(appSessionProvider).serverBase;
  final ctrl = TextEditingController(text: current);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('服务端地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API 地址',
              hintText: 'http://127.0.0.1:9060',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '所有接口调用拼接此地址；切换后旧 token 作废，解锁状态会自动重注册并同步。\n接口文档：{地址}/doc.html',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () async {
            final value = ctrl.text;
            Navigator.pop(ctx);
            await ref.read(appSessionProvider.notifier).setServerBase(value);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 心情管理：默认 6 心情可改显示（emoji/名称/颜色），自定义心情可增删改查。
/// key 全局稳定——编辑只改显示，历史条目照常渲染；删除仅限自定义。
Future<void> showMoodConfigDialog(BuildContext context, WidgetRef ref) async {
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('心情管理'),
        content: SizedBox(
          width: double.maxFinite,
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final m in AppDefaults.allMoods)
                        ListTile(
                          dense: true,
                          leading: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: m.color.withValues(alpha: .16),
                            ),
                            child: Text(m.emoji,
                                style: const TextStyle(fontSize: 17)),
                          ),
                          title: Text(m.name),
                          subtitle: Text(
                            AppDefaults.moods.any((d) => d.key == m.key)
                                ? '默认'
                                : '自定义',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: m.color),
                          ),
                          onTap: () => _showMoodEditSheet(ctx, ref,
                              mood: m, refreshDialog: setState),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增心情'),
                  onPressed: () => _showMoodEditSheet(ctx, ref,
                      refreshDialog: setState),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    ),
  );
}

/// 单个心情编辑/新增（底部弹层）：emoji 选择 + 名称 + 调色板；自定义可删除。
Future<void> _showMoodEditSheet(
  BuildContext ctx,
  WidgetRef ref, {
  MoodCfg? mood,
  required void Function(void Function()) refreshDialog,
}) async {
  final b = Theme.of(ctx).brightness;
  final isNew = mood == null;
  final isCustom =
      mood != null && !AppDefaults.moods.any((d) => d.key == mood.key);
  final nameCtrl = TextEditingController(text: mood?.name ?? '');
  var emoji = mood?.emoji ?? _emojiChoices.first;
  var colorHex = mood?.colorHex ?? AppDefaults.tagColorHex['blue']!;
  String? error;
  await showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew ? '新增心情' : '编辑心情 · ${mood.name}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Tokens.label(b))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in _emojiChoices)
                    GestureDetector(
                      onTap: () => setSheet(() => emoji = e),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: e == emoji
                              ? Color(colorHex).withValues(alpha: .18)
                              : Colors.transparent,
                          border: Border.all(
                              color: e == emoji
                                  ? Color(colorHex)
                                  : Colors.transparent,
                              width: 1.5),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child:
                            Text(e, style: const TextStyle(fontSize: 19)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: '名称（1~8 字）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final cn in _paletteOrder)
                    _swatch(
                      Color(AppDefaults.tagColorHex[cn]!),
                      colorHex == AppDefaults.tagColorHex[cn],
                      null,
                      () => setSheet(
                          () => colorHex = AppDefaults.tagColorHex[cn]!),
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFFF453A))),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final notifier =
                            ref.read(appSessionProvider.notifier);
                        try {
                          if (isNew) {
                            await notifier.addMood(
                                nameCtrl.text, emoji, colorHex);
                          } else {
                            await notifier.updateMood(
                                mood.key, emoji, nameCtrl.text, colorHex);
                          }
                          refreshDialog(() {});
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        } on FormatException catch (e) {
                          setSheet(() => error = e.message);
                        }
                      },
                      child: Text(isNew ? '添加' : '保存'),
                    ),
                  ),
                  if (isCustom) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF453A)),
                      onPressed: () async {
                        await ref
                            .read(appSessionProvider.notifier)
                            .removeMood(mood.key);
                        refreshDialog(() {});
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                      child: const Text('删除'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 导出 Markdown（明文导出需解锁 + 二次确认，share_plus）。
Future<void> showExportDialog(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导出全部日记'),
      content:
          const Text('将生成明文 Markdown 并通过系统分享面板导出。\n明文导出有泄露风险，确定继续？'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定导出')),
      ],
    ),
  );
  if (ok != true) return;
  final state = ref.read(appSessionProvider);
  final sb = StringBuffer('# 一句话日记\n\n');
  for (final g in groupByDay(state.entries)) {
    sb.writeln('## ${g.key}\n');
    for (final e in g.value) {
      sb.writeln('- **${e.payload.time}** ${e.payload.text}');
      if (e.payload.tags.isNotEmpty) {
        sb.writeln('  标签：${e.payload.tags.map((t) => '#$t').join(' ')}');
      }
      if (e.payload.comments.isNotEmpty) {
        for (final c in e.payload.comments) {
          sb.writeln('  - 评论 ${c.who}：${c.text}（${c.time}）');
        }
      }
    }
    sb.writeln();
  }
  await SharePlus.instance.share(ShareParams(
    text: sb.toString(),
    title: '一句话日记.md',
  ));
}

/// 更改注册名（晨 19 §5.10，缺口 #7 端点已就绪）：强确认「旧名无法再登录」。
Future<void> showRenameIdentityDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController(text: ref.read(appSessionProvider).userId);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更改注册名'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('注册名是登录身份：旧名从此无法再登录，其他设备需用新名 + 原恢复词登录。',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: '新注册名',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () async {
            try {
              await ref
                  .read(appSessionProvider.notifier)
                  .renameIdentity(ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showInfoDialog(context, '更改失败', friendlyError(e));
              }
            }
          },
          child: const Text('确认更改'),
        ),
      ],
    ),
  );
}

/// 更换 12 词主密钥（晨 19 §5.4/§5.10）：全量重加密；成功后新词宫格展示，
/// barrierDismissible=false 必须点「我已抄写」才可离开。
Future<void> showRotateIdentityDialog(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更换 12 词主密钥'),
      content: const Text(
          '将生成新的 12 词恢复词，并把全部日记重加密到新密钥（媒体无需重传）。\n\n'
          '⚠ 旧恢复词立即作废；其他设备（持旧词）将无法再解密新数据。\n'
          '请准备纸笔抄写。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('开始更换')),
      ],
    ),
  );
  if (ok != true) return;
  if (!context.mounted) return;
  String passcode = '';
  if (ref.read(appSessionProvider).lockEnabled) {
    final ctrl = TextEditingController();
    passcode = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('输入锁定口令'),
            content: _passField(ctrl, '当前锁定口令'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('继续')),
            ],
          ),
        ) ??
        '';
    if (passcode.isEmpty) return;
  }
  if (!context.mounted) return;
  try {
    final words =
        await ref.read(appSessionProvider.notifier).rotateIdentity(passcode: passcode);
    final list = words.trim().split(RegExp(r'\s+'));
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('新恢复词 · 立即抄写'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, w) in list.indexed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}. $w',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('旧恢复词已作废。这 12 个词只展示这一次——\n丢失 = 永久丢失全部日记。',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('我已抄写')),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) showInfoDialog(context, '更换失败', friendlyError(e));
  }
}
