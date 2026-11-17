// friendlyError 统一友好错误映射（晨 19 §5.11）：五类输入 → 中文文案，
// 任何路径不得透出原始异常文本（用户约束：不把报错暴露给前端）。
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/util/errors.dart';
import 'package:dio/dio.dart'
    show DioException, DioExceptionType, RequestOptions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ApiException → 服务端中文业务 message 原样', () {
    expect(friendlyError(ApiException(404, '参数校验失败')), '参数校验失败');
    expect(friendlyError(ApiException(500, '注册名已存在')), '注册名已存在');
  });

  test('DioException 按错误类型分类', () {
    final ro = RequestOptions(path: '/');
    expect(
        friendlyError(DioException(
            requestOptions: ro, type: DioExceptionType.connectionError)),
        '无法连接服务端，请检查网络与服务端地址');
    expect(
        friendlyError(DioException(
            requestOptions: ro, type: DioExceptionType.connectionTimeout)),
        '连接服务端超时，请稍后重试');
    expect(
        friendlyError(DioException(
            requestOptions: ro, type: DioExceptionType.receiveTimeout)),
        '连接服务端超时，请稍后重试');
    expect(
        friendlyError(DioException(
            requestOptions: ro, type: DioExceptionType.badResponse)),
        '网络异常，请稍后重试');
  });

  test('StateError 哨兵转文案；中文业务消息原样', () {
    expect(friendlyError(StateError('locked')), '会话已锁定，请解锁后再试');
    expect(friendlyError(StateError('bad-passcode')), '口令不正确');
    expect(friendlyError(StateError('bio-missing')), '本机未设置面容/生物识别');
    expect(friendlyError(StateError('本机无身份')), '本机无身份');
  });

  test('FormatException/ArgumentError → message 直取（无类名前缀）', () {
    expect(friendlyError(const FormatException('恢复词需要 12 个词（用空格分隔）')),
        '恢复词需要 12 个词（用空格分隔）');
    expect(friendlyError(ArgumentError('口令不足 6 位')), '口令不足 6 位');
  });

  test('未知异常 → 通用兜底（不透原始文本）', () {
    final out = friendlyError(Exception('boom-raw-english-stack'));
    expect(out, '操作失败，请稍后重试');
    expect(out.contains('boom'), isFalse, reason: '原始异常文本不得上屏');
  });
}
