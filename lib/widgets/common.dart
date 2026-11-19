// 共享组件：8 色光晕天卡片、标签 chip、心情、录音胶囊、iOS 行、toast。
import 'dart:async';
import 'dart:math' show max, min, sqrt;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/config/app_defaults.dart';
import '../core/model/diary_entry.dart';
import '../features/theme/tokens.dart';

/// 天卡片：白卡 + 8 色光晕（blur 60px≈sigma30；透明度按深浅色取 Tokens.glow*Opacity）。
/// 浅色常态必须接近白色（01 §4.1：ΔRGB≤~12/255）；深色按用户要求同样显色。
class GlowDayCard extends StatefulWidget {
  final int glowIndex; // 1..8
  final bool highlighted; // 日历跳转/新发布：仅日期数字变组色
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onExpandToggle;

  const GlowDayCard({
    super.key,
    required this.glowIndex,
    required this.child,
    this.highlighted = false,
    this.padding = EdgeInsets.zero,
    this.onExpandToggle,
  });

  @override
  State<GlowDayCard> createState() => _GlowDayCardState();
}

class _GlowDayCardState extends State<GlowDayCard> {
  bool _hot = false; // 悬停/长按

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final idx = (widget.glowIndex - 1) % 8;
    final (anchor, color, hoverColor) = Tokens.glowAnchors[idx];
    final baseOpacity = Tokens.glowBaseOpacity(b);
    final hotOpacity = Tokens.glowHotOpacity(b);

    Widget glow = LayoutBuilder(
      builder: (context, cons) {
        // 原版 CSS: radial-gradient(circle at 锚点, 色, transparent 120%)——transparent
        // 落在最远角距离的 1.2 倍处（radial 默认 farthest-corner 基准），光晕铺满整卡
        // （test.html 修复2 注释：半径超过对角线，卡片很高时底部也有淡色）。
        // Flutter RadialGradient.radius 以最短边为基准 → 按比例换算，否则卡内提前衰减、卡片失色。
        final w = cons.maxWidth, h = cons.maxHeight;
        final farthest = sqrt(w * w + h * h);
        final radius = 1.2 * farthest / min(w, h);
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: anchor,
              radius: radius,
              colors: [_hot ? hoverColor : color, Colors.transparent],
              stops: const [0, 1],
            ),
          ),
        );
      },
    );
    glow = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: glow,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => setState(() => _hot = true),
        onLongPressEnd: (_) => setState(() => _hot = false),
        child: AnimatedScale(
          scale: 1,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            transform: _hot
                ? (Matrix4.translationValues(0, -5, 0))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: Tokens.card(b),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _hot
                      ? (b == Brightness.light
                          ? Colors.black.withValues(alpha: .08)
                          : Colors.black.withValues(alpha: .5))
                      : Colors.black.withValues(alpha: .05),
                  blurRadius: _hot ? 12 : 2,
                  offset: _hot ? const Offset(0, 6) : const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  // 光晕层铺满（不参与内容布局）
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _hot ? hotOpacity : baseOpacity,
                        duration: const Duration(milliseconds: 400),
                        child: glow,
                      ),
                    ),
                  ),
                  // 内容层：非 Positioned，撑开卡片高度
                  IgnorePointer(
                    ignoring: false,
                    child: Padding(
                      padding: widget.padding,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签 chip：`#名字`，颜色 = 8 色稳定哈希（传入 seed 时 = 标签名+正文动态色），
/// 底色 = 色 22 alpha。
class TagChip extends StatelessWidget {
  final String name;
  final String? seed; // 动态色种子（正文）：同一标签在不同条目呈现不同颜色
  final VoidCallback? onDelete;
  final bool compact;

  const TagChip(this.name,
      {super.key, this.onDelete, this.compact = false, this.seed});

  @override
  Widget build(BuildContext context) {
    final c = AppDefaults.tagColorOf(name, seed: seed);
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(compact ? 8 : 7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$name',
            style: TextStyle(
              fontSize: compact ? 12 : 11,
              fontWeight: FontWeight.w600,
              color: c,
              height: 1.2,
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 5),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close, size: 12, color: c.withValues(alpha: .55)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 心情 emoji（feed 条目脚注）。
class MoodEmoji extends StatelessWidget {
  final String? moodKey;
  final double size;

  const MoodEmoji({super.key, required this.moodKey, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (moodKey == null) return SizedBox(width: size, height: size);
    return Text(
      AppDefaults.moodOf(moodKey!).emoji,
      style: TextStyle(fontSize: size, height: 1),
    );
  }
}

/// 录音条：波形胶囊（mockup 装饰波形：2n→11px、3n→15px、其余 5px）。
class WavePill extends StatelessWidget {
  final int seconds;
  final VoidCallback? onTap;
  final bool recording; // 录音中：红底白点闪烁
  final bool compact;

  const WavePill({
    super.key,
    required this.seconds,
    this.onTap,
    this.recording = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: recording ? Tokens.red(b) : Tokens.fill(b),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recording) ...[
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  Icons.play_arrow,
                  size: 13,
                  color: Tokens.blue(b),
                ),
                const SizedBox(width: 8),
              ],
              if (!recording) _bars(b),
              const SizedBox(width: 8),
              Text(
                '0:${seconds.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 12,
                  color: recording ? Colors.white : Tokens.label(b),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bars(Brightness b) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 1; i <= 8; i++)
          Container(
            width: 2.5,
            height: i % 2 == 0 ? 11 : (i % 3 == 0 ? 15 : 5),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: Tokens.blue(b),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// iOS 风格行（我的页）：icon 方块 + 标题 + 值/箭头或开关。
class IosRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String? value;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;
  final VoidCallback? onTap;
  final Color? valueColor;
  final Widget? trailing;

  const IosRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.title,
    this.value,
    this.switchValue,
    this.onSwitch,
    this.onTap,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final row = Row(
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: Tokens.label(b)),
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Tokens.label2(b),
              fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        if (switchValue case final v?)
          Switch(value: v, onChanged: onSwitch),
        ?trailing,
        if (onTap != null && switchValue == null)
          Icon(Icons.chevron_right, size: 18, color: Tokens.label3(b)),
      ],
    );
    if (onTap == null && onSwitch == null) return row;
    return InkWell(
      onTap: onTap,
      child: row,
    );
  }
}

/// 页面大标题顶距（2026-11-16 真机反馈）：岛/刘海机取状态栏安全区+12，
/// 无刘海环境（web 预览 0）保持原 64 设计值——四个 tab 页大标题统一使用。
/// 待同步标记（晨 15 用户拍板 * 指针式）：显示层注入，绝不写入载荷——
/// 编辑预填/搜索/导出全消费原始 payload，标记永不污染数据。
/// 橙色与页头「N 条待同步」徽标同色，语义一致（橙星 = 这条还没上云）。
List<InlineSpan> pendingMark(bool pending, Brightness b) => [
      if (pending)
        TextSpan(
          text: '*',
          style: TextStyle(
              color: Tokens.orange(b), fontWeight: FontWeight.w800),
        ),
    ];

double headerTopPad(BuildContext context) {
  final t = MediaQuery.paddingOf(context).top + 12;
  return max(t, 64);
}

/// 分组容器（我的页 .od2-grp）。
class IosGroup extends StatelessWidget {
  final List<Widget> children;

  const IosGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        color: Tokens.card(b),
        borderRadius: BorderRadius.circular(13),
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
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: .5, color: Tokens.sep(b), indent: 14, endIndent: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 行包装（垂直 padding）。
class RowPad extends StatelessWidget {
  final Widget child;
  const RowPad(this.child, {super.key});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), child: child);
}

/// 全局 toast（§5.14 提示语上浮：顶部黑胶囊 1.9s——原 mockup 底部位弃用）。
class ToastHost extends StatefulWidget {
  final String? message;
  final VoidCallback? onDismiss;

  const ToastHost({super.key, this.message, this.onDismiss});

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 挂载即有消息也要调度关闭（登录/创建身份的 toast 与路由切换同帧发生，
    // ToastHost 以非空 message 挂载，didUpdateWidget 不会触发 → 否则常驻不消失）
    if (widget.message != null) _scheduleDismiss();
  }

  @override
  void didUpdateWidget(covariant ToastHost old) {
    super.didUpdateWidget(old);
    if (widget.message != null && widget.message != old.message) {
      _scheduleDismiss();
    }
  }

  void _scheduleDismiss() {
    _timer?.cancel(); // 新消息到达时作废旧定时器，避免上一条提前关掉这一条
    _timer = Timer(const Duration(milliseconds: 1900), () => widget.onDismiss?.call());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 顶部悬浮：状态栏/刘海高度 + 呼吸间距（§5.14 提示语上浮）
    final topInset = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.message == null ? 0 : 1,
        duration: const Duration(milliseconds: 300),
        child: Container(
          margin: EdgeInsets.only(top: topInset + 8),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: const Color(0xF018181C),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            widget.message ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// 图片九宫格（≤9，超出末格 +N）。
class ImageGrid extends StatelessWidget {
  final List<MediaRef> images;
  final void Function(MediaRef)? onOpen;

  const ImageGrid({super.key, required this.images, this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final extra = images.length - 9;
    final showCount = images.length > 9 ? 9 : images.length;
    const gradients = [
      [Color(0xFFFFB199), Color(0xFFFF0844)],
      [Color(0xFF5EFCE8), Color(0xFF736EFE)],
      [Color(0xFFF9D423), Color(0xFFFF4E50)],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: showCount,
        itemBuilder: (context, i) {
          if (i == 8 && extra > 0) {
            return Container(
              decoration: BoxDecoration(
                color: Tokens.fill(Theme.of(context).brightness),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Tokens.label2(Theme.of(context).brightness),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }
          final img = images[i];
          final real = img.cekB64.isNotEmpty;
          final g = gradients[(i + img.id) % gradients.length];
          return GestureDetector(
            // 只有真实媒体（有密钥引用）可点开查看器；demo/未冲正占位不响应（§5.3）
            onTap: real && onOpen != null ? () => onOpen!(img) : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: real
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: g,
                      ),
                color: real ? Tokens.fill(Theme.of(context).brightness) : null,
              ),
              child: real
                  ? Icon(Icons.image_outlined,
                      color: Tokens.label3(Theme.of(context).brightness))
                  : null,
            ),
          );
        },
      ),
    );
  }
}
