// 全屏媒体查看器（晨 19 §5.3）：暗底 + PageView 左右翻 + InteractiveViewer 缩放
// + 保存到相册。字节经 session.mediaBytes（下载→解 CEK 包裹→AES-GCM 解密）按需
// 获取，页内缓存；失败页内重试。fetchBytes/saveBytes 注入为测试与翻译预留。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/model/diary_entry.dart';
import '../core/util/errors.dart';
import '../core/util/media_save.dart';

class MediaViewer extends StatefulWidget {
  final List<MediaRef> images;
  final int initialIndex;
  final Future<Uint8List> Function(MediaRef ref) fetchBytes;
  final Future<void> Function(Uint8List bytes) saveBytes;

  const MediaViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.fetchBytes,
    this.saveBytes = saveImageBytes,
  });

  /// 入口：root 导航全屏推入（feed 的 ImageGrid.onOpen 调用）。
  static Future<void> show(
    BuildContext context, {
    required List<MediaRef> images,
    required int initialIndex,
    required Future<Uint8List> Function(MediaRef ref) fetchBytes,
  }) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaViewer(
            images: images, initialIndex: initialIndex, fetchBytes: fetchBytes),
      ));

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late int _index = widget.initialIndex;
  final _loaded = <int, Uint8List>{}; // ref.id → 明文字节（页回调回填）

  Future<void> _save() async {
    final bytes = _loaded[widget.images[_index].id];
    if (bytes == null) return;
    try {
      await widget.saveBytes(bytes);
      if (mounted) _toast('已保存到相册 ✓');
    } catch (e) {
      if (mounted) _toast('保存失败：${friendlyError(e)}');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.white24, content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: CloseButton(onPressed: () => Navigator.of(context).pop()),
        title: Text(
          '${_index + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed:
                _loaded.containsKey(widget.images[_index].id) ? _save : null,
          ),
        ],
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _MediaPage(
          ref: widget.images[i],
          fetchBytes: widget.fetchBytes,
          onLoaded: (bytes) => setState(() => _loaded[widget.images[i].id] = bytes),
        ),
      ),
    );
  }
}

/// 单页：按需获取字节（页内 Future + 重试），InteractiveViewer 缩放。
class _MediaPage extends StatefulWidget {
  final MediaRef ref;
  final Future<Uint8List> Function(MediaRef ref) fetchBytes;
  final void Function(Uint8List bytes) onLoaded;

  const _MediaPage({
    required this.ref,
    required this.fetchBytes,
    required this.onLoaded,
  });

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// 发起获取；完成时回调父级回填（保存按钮启用依据）。只回调一次，
  /// 不在 build 内回调（会触发无界重建循环）。
  void _start() {
    _future = widget.fetchBytes(widget.ref);
    _future.then((b) {
      if (mounted) widget.onLoaded(b);
    }, onError: (_) {});
  }

  void _retry() => setState(_start);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('加载失败', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _retry, child: const Text('重试')),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.memory(snap.data!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}
