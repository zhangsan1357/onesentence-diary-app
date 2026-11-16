// 保存图片到系统相册·web 桩（晨 19 §5.3 边界）：浏览器无相册，不可用。
import 'dart:typed_data';

Future<void> saveImageBytes(Uint8List bytes) async {
  throw UnsupportedError('web 预览不支持保存到相册');
}
