// 统一友好错误文案（晨 19 §5.11）：任何 UI 提示一律经此映射——
// 绝不把原始异常文本（英文类名/栈信息）暴露给用户；服务端与客户端校验的
// 中文业务消息原样透出。纯 Dart 无 UI 依赖（原生翻译友好约束 1）。
import 'package:dio/dio.dart' show DioException, DioExceptionType;

import '../api/api_client.dart' show ApiException;

/// 异常 → 用户可读中文。分类依据实际失败原因，而非透出异常对象。
String friendlyError(Object e) {
  // 服务端业务异常：message 本就是中文用户文案（404 参数校验/500 业务失败等）
  if (e is ApiException) return e.message;
  // 网络层失败：按 dio 错误类型给对应提示（DioException 带响应体的已在上游
  // 转为 ApiException，走到这里都是连接类失败）
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '连接服务端超时，请稍后重试',
      DioExceptionType.connectionError => '无法连接服务端，请检查网络与服务端地址',
      _ => '网络异常，请稍后重试',
    };
  }
  // 会话层哨兵异常：message 直取（StateError.toString 前缀 "Bad state: "
  // 带空格，正则去前缀不可靠，用属性），哨兵转文案、中文业务消息原样
  if (e is StateError) {
    final m = e.message;
    if (m == 'locked') return '会话已锁定，请解锁后再试';
    // §5.14：bio-missing 实际触发点=钥匙串存档失效（biometryCurrentSet 平台
    // 语义），unlock 成功后会自动重存——文案指引口令解锁一次即可自愈
    if (m == 'bio-missing') return '面容存档已失效 · 请先用口令解锁，之后面容将自动恢复';
    if (m == 'bad-passcode') return '口令不正确';
    return m;
  }
  // 客户端校验异常（恢复词/注册名/口令等），消息本身是中文 → message 直取
  if (e is FormatException) return e.message;
  if (e is ArgumentError) {
    final m = e.message;
    return (m == null || '$m'.isEmpty) ? '参数不合法' : '$m';
  }
  // 其余（Exception/平台异常/未知）：一律通用兜底，不透原始文本
  return '操作失败，请稍后重试';
}
