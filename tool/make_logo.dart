// 用任意图片生成 iOS 全套 AppIcon（2026-11-16）：
//   dart run tool/make_logo.dart <图片路径> [输出目录]
// 规则：带透明通道 → 白底合成 + 白边居中补方（contain）；纯不透明 → 居中裁方（cover）。
// 输出沿用 appiconset 现有文件名，Contents.json 无需改动；
// 全部按 RGB 落盘——iOS 图标不得含透明通道（1024 那张会被 App Store 校验拒收）。
// 注意：iPhone 相册原生的 HEIC 不支持，先转 jpg/png 再喂进来。
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/make_logo.dart <图片路径> [输出目录]');
    exit(2);
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('文件不存在: ${input.path}');
    exit(2);
  }
  final outDir = Directory(args.length > 1
      ? args[1]
      : 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (!outDir.existsSync()) {
    stderr.writeln('输出目录不存在: ${outDir.path}');
    exit(2);
  }

  final src = img.decodeImage(input.readAsBytesSync());
  if (src == null) {
    stderr.writeln('无法解码: ${input.path}（支持 jpg/png/webp/gif/bmp/tiff）');
    exit(2);
  }

  final square = _squareOf(src);
  var count = 0;
  for (final entity in outDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final m = RegExp(r'^Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$')
        .firstMatch(name);
    if (m == null) continue;
    final size = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
    var resized = img.copyResize(square,
        width: size, height: size, interpolation: img.Interpolation.cubic);
    // 统一收敛到 RGB 真彩（个别尺寸的 resize 会产出调色板图，其 numChannels
    // 同样报 3，必须用 hasPalette 判；iOS 图标以无透明、稳定编码为先）
    if (resized.hasPalette || resized.numChannels != 3) {
      resized = resized.convert(numChannels: 3);
    }
    entity.writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('${name.padRight(32)} ${size}x$size');
    count++;
  }
  if (count == 0) {
    stderr.writeln('输出目录里没有 Icon-App-*.png 可供替换: ${outDir.path}');
    exit(1);
  }
  stdout.writeln(
      '完成：$count 张（源图 ${src.width}x${src.height} → ${square.width}x${square.width}）');
}

/// 方形化：EXIF 摆正 → 调色板转真彩 → 透明图白底合成（顺带把输出收敛到 RGB）→
/// contain（白边补方）或 cover（居中裁方）。返回值必无透明通道。
img.Image _squareOf(img.Image src) {
  var work = img.bakeOrientation(src);
  if (work.hasPalette) {
    work = work.convert(numChannels: work.hasAlpha ? 4 : 3);
  }
  final hasAlpha = work.hasAlpha;
  if (hasAlpha) {
    final bg = img.Image(
        width: work.width, height: work.height, numChannels: 3);
    img.fillRect(bg,
        x1: 0,
        y1: 0,
        x2: work.width - 1,
        y2: work.height - 1,
        color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(bg, work);
    work = bg;
  }
  final w = work.width;
  final h = work.height;
  if (w == h) return work;
  if (hasAlpha) {
    final side = w > h ? w : h;
    final out = img.Image(
        width: side, height: side, numChannels: 3);
    img.fillRect(out,
        x1: 0,
        y1: 0,
        x2: side - 1,
        y2: side - 1,
        color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(out, work, center: true);
    return out;
  }
  final side = w < h ? w : h;
  return img.copyCrop(work,
      x: (w - side) ~/ 2, y: (h - side) ~/ 2, width: side, height: side);
}
