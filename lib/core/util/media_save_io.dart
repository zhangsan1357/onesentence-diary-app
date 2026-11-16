// 保存图片到系统相册·IO 实现（晨 19 §5.3）：gal 插件；权限拒绝/失败抛异常给
// 调用方 toast。iOS 14+ 需相册写权限（插件自带请求）。
import 'dart:typed_data';

import 'package:gal/gal.dart';

Future<void> saveImageBytes(Uint8List bytes) async {
  await Gal.putImageBytes(bytes);
}
