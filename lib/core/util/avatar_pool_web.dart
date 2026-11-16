// 头像预下载池·Web 实现：无 dart:io，池禁用——渲染恒走 NetAvatar 网络链路
//（Windows 开发机 Chrome 预览场景，真机 iOS 走 IO 实现）。
class AvatarPool {
  Future<void> start() async {}
  void stop() {}
  String? pathFor(int index) => null;
}

AvatarPool createAvatarPool() => AvatarPool();
