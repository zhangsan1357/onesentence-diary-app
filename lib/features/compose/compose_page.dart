// 发布页：全屏弹层（上滑过场）——正文自动增高 + 心情 6 胶囊（可反选）+
// 标签默认/云端 chips 点选（≤6）+ 文本补录新标签 + 照片（≤9）+ 录音 ≤60s + 发布。
import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:typed_data';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_defaults.dart';
import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/errors.dart';
import '../../features/theme/tokens.dart';
import '../../widgets/common.dart';

class ComposeRoute extends PageRouteBuilder {
  final DiaryEntry? editEntry; // 非空 = 长按编辑模式

  ComposeRoute({this.editEntry})
      : super(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, a, s) => ComposePage(editEntry: editEntry),
          transitionsBuilder: (context, a, s, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: a,
              curve: const Cubic(.32, .72, .35, 1),
            )),
            child: child,
          ),
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: .42),
        );
}

class ComposePage extends ConsumerStatefulWidget {
  final DiaryEntry? editEntry; // 非空 = 编辑（预填正文/心情/标签，保存=整条重新加密替换）

  const ComposePage({super.key, this.editEntry});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final _text = TextEditingController();
  final _tagIn = TextEditingController();
  String? _mood;
  final _tags = <String>[];
  final _photos = <Uint8List>[];
  RecorderController? _recorder;
  bool _recording = false;
  int _recSecs = 0;
  Timer? _recTimer;
  Uint8List? _audioDone;
  int _audioSecs = 0;
  bool _publishing = false;

  bool get _canPublish =>
      _text.text.trim().isNotEmpty ||
      _photos.isNotEmpty ||
      _audioDone != null ||
      (_isEdit && widget.editEntry!.payload.media.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final edit = widget.editEntry;
    if (edit != null) {
      _text.text = edit.payload.text;
      _mood = edit.payload.mood;
      _tags.addAll(edit.payload.tags);
    }
    _text.addListener(() {
      setState(() {});
      _saveDraft(); // 未落盘输入随时缓存（300ms 防抖，§4.12）
    });
    unawaited(_restoreDraft());
  }

  bool get _isEdit => widget.editEntry != null;

  /// 草稿键（§4.12）：编辑按条目隔离，新建共用一条。
  String get _draftKey =>
      _isEdit ? 'edit.${widget.editEntry!.localId}' : 'new';

  void _saveDraft() {
    ref.read(appSessionProvider.notifier).saveDraft(
        _draftKey,
        jsonEncode(
            {'text': _text.text, 'mood': _mood, 'tags': List.of(_tags)}));
  }

  /// 恢复草稿（上次未落盘的输入）：仅在用户尚未输入时应用，避免覆盖正在打的字。
  Future<void> _restoreDraft() async {
    final d = await ref.read(appSessionProvider.notifier).loadDraft(_draftKey);
    if (d == null || !mounted) return;
    final untouched = _text.text.isEmpty && _mood == null && _tags.isEmpty;
    if (!untouched) return;
    try {
      final j = jsonDecode(d) as Map<String, dynamic>;
      setState(() {
        _text.text = j['text'] as String? ?? '';
        _mood = j['mood'] as String?;
        _tags
          ..clear()
          ..addAll([
            for (final v in (j['tags'] as List?) ?? const [])
              if (v is String) v,
          ]);
      });
    } catch (_) {
      // 坏草稿按无处理
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _tagIn.dispose();
    _recTimer?.cancel();
    _recorder?.dispose();
    _recorder = null;
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final existingImgs = _isEdit
        ? widget.editEntry!.payload.media.where((m) => m.kind == 'image').length
        : 0;
    final room = 9 - existingImgs - _photos.length;
    if (room <= 0) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(limit: room, imageQuality: 85);
    final bytes = <Uint8List>[];
    for (final f in files.take(room)) {
      bytes.add(await f.readAsBytes());
    }
    setState(() => _photos.addAll(bytes));
  }

  Future<void> _startRecording() async {
    final rec = RecorderController();
    _recorder = rec;
    try {
      await rec.record(path: 'rec.m4a');
      setState(() {
        _recording = true;
        _recSecs = 0;
        _audioDone = null;
        _audioSecs = 0;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        _recSecs++;
        if (_recSecs >= 60) {
          await _stopRecording(); // 超时自动停（03 §6）
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      _show('录音不可用：${friendlyError(e)}');
    }
  }

  Future<void> _stopRecording({bool discard = false}) async {
    _recTimer?.cancel();
    _recTimer = null;
    final rec = _recorder;
    _recorder = null;
    if (mounted) setState(() => _recording = false);
    if (rec == null) return;
    try {
      if (discard) {
        rec.dispose();
        return;
      }
      final path = await rec.stop();
      rec.dispose();
      if (path == null) return;
      final bytes = await _readFile(path);
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _audioDone = bytes;
          _audioSecs = _recSecs;
        });
      }
    } catch (_) {
      // 停止失败按丢弃处理
    }
  }

  Future<Uint8List?> _readFile(String path) async {
    try {
      return await XFile(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _publish() async {
    if (!_canPublish || _publishing) return;
    // 锁定态守卫（晨 19 §5.11）：compose 路由浮于锁屏覆盖层之上，自动锁触发
    // 后本页仍可点发布 → 前置拦截给中文提示（不进入发布流程）
    if (!ref.read(appSessionProvider).unlocked) {
      _show('会话已锁定，请解锁后再试');
      return;
    }
    setState(() => _publishing = true);
    try {
      final media = <MediaInput>[
        for (final p in _photos) MediaInput(kind: 'image', bytes: p),
        if (_audioDone != null)
          MediaInput(kind: 'audio', bytes: _audioDone!, sec: _audioSecs),
      ];
      if (_isEdit) {
        await ref.read(appSessionProvider.notifier).updateEntry(
              widget.editEntry!,
              text: _text.text.trim(),
              mood: _mood,
              tags: List.of(_tags),
              newMedia: media,
            );
      } else {
        await ref.read(appSessionProvider.notifier).publish(
              text: _text.text.trim(),
              mood: _mood,
              tags: List.of(_tags),
              media: media,
            );
      }
      // 本地已落库（离线队列保证最终推云）→ 草稿使命完成（§4.12）
      await ref.read(appSessionProvider.notifier).clearDraft(_draftKey);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _show(_isEdit ? '保存失败：${friendlyError(e)}' : '发布失败：${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 删除当前编辑的日记：二次确认 → 会话层软删+服务端同步删除 → 回时光流。
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条日记'),
        content: const Text(
          '删除后本机与服务端同步删除，不可恢复。',
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final notifier = ref.read(appSessionProvider.notifier);
      await notifier.deleteEntry(widget.editEntry!);
      notifier.showToast('已删除 ✓');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _show('删除失败：${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    // 自动锁兜底（晨 19 §5.11）：compose 是全屏路由，浮在 HomeShell 的锁屏
    // 覆盖层之上——锁定触发即自动 pop，露出其下的锁屏（不再出现「发布页
    // 悬在锁屏之上」的竞态窗口）
    ref.listen(appSessionProvider.select((s) => s.locked), (prev, next) {
      if (next && prev == false && mounted) Navigator.of(context).pop();
    });
    // 微信式键盘收起（§4.11）：点空白/正文区收起；按钮/chip/输入框等子控件
    // 胜出手势竞技场，行为不受影响（不过敏——只拦空白点按）。
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      backgroundColor: Tokens.bg(b),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 46),
          children: [
            // 顶栏（吸顶视觉）：取消 / 写一条 / 发布
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text('取消',
                        style: TextStyle(
                            fontSize: 16, color: Tokens.label2(b))),
                  ),
                  Text(_isEdit ? '编辑' : '写一条',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Tokens.label(b))),
                  GestureDetector(
                    onTap: _canPublish ? _publish : null,
                    child: Text(
                      _publishing
                          ? (_isEdit ? '保存中…' : '发布中…')
                          : (_isEdit ? '保存' : '发布'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _canPublish
                            ? Tokens.blue(b)
                            : Tokens.blue(b).withValues(alpha: .35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 抓手条
            Center(
              child: Container(
                width: 38,
                height: 5,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Tokens.label3(b),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // 正文
            Container(
              margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              constraints: const BoxConstraints(minHeight: 150, maxHeight: 300),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Tokens.card(b),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _text,
                maxLines: null,
                
                style: TextStyle(
                    fontSize: 16, height: 1.6, color: Tokens.label(b)),
                decoration: InputDecoration(
                  hintText: '今天怎么样？写点什么……',
                  hintStyle: TextStyle(color: Tokens.label3(b), fontSize: 16),
                  border: InputBorder.none,
                ),
                autofocus: true,
              ),
            ),
            _sectionLabel(b, '此刻的心情'),
            moodRow(b),
            _sectionLabel(b, '标签'),
            tagSuggestRow(b),
            tagBox(b),
            _sectionLabel(b, '照片与声音'),
            mediaRow(b),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 12, color: Tokens.label3(b)),
                const SizedBox(width: 5),
                Text(
                  '端到端加密 · 每条独立密钥 · 主密钥可更换 · 服务端零明文',
                  style: TextStyle(fontSize: 11, color: Tokens.label3(b)),
                ),
              ],
            ),
            // 编辑态：删除这条日记（二次确认 → 本机+服务端同步删除）
            if (_isEdit) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _confirmDelete,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: Tokens.red(b).withValues(
                        alpha: b == Brightness.light ? .07 : .14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Tokens.red(b).withValues(alpha: .25)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: Tokens.red(b)),
                      const SizedBox(width: 7),
                      Text('删除这条日记',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Tokens.red(b))),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _sectionLabel(Brightness b, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 9),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Tokens.label2(b))),
      );

  Widget moodRow(Brightness b) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          for (final m in AppDefaults.allMoods)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _moodChip(b, m),
            ),
        ],
      ),
    );
  }

  Widget _moodChip(Brightness b, MoodCfg m) {
    final sel = _mood == m.key;
    return GestureDetector(
      onTap: () {
        setState(() => _mood = sel ? null : m.key);
        _saveDraft();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? m.color.withValues(alpha: .16) : Tokens.card(b),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? m.color : Tokens.sep(b),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.emoji, style: const TextStyle(fontSize: 16, height: 1)),
            const SizedBox(width: 5),
            Text(m.name,
                style: TextStyle(
                    fontSize: 13,
                    color: Tokens.label(b),
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }

  /// 可选标签：标签库（标签管理维护，初始含默认三项）+ 云端同步条目出现过的
  /// 标签（去重），点按即选/再点取消。免输入（iOS 中文键盘回车确认链路不稳，
  /// 点选最可靠）；新标签仍可文本输入。
  Widget tagSuggestRow(Brightness b) {
    final entries = ref.watch(appSessionProvider).entries;
    final cloud = <String>{
      for (final e in entries)
        if (!e.deleted) ...e.payload.tags,
    }..removeWhere(AppDefaults.tagPresets.contains);
    final suggestions = [...AppDefaults.tagPresets, ...cloud];
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final t in suggestions) _suggestChip(b, t)],
      ),
    );
  }

  Widget _suggestChip(Brightness b, String t) {
    final sel = _tags.contains(t);
    final c = AppDefaults.tagColor(t);
    return GestureDetector(
      onTap: () {
        if (sel) {
          setState(() => _tags.remove(t));
        } else if (_tags.length >= 6) {
          _show('最多 6 个标签');
        } else {
          setState(() => _tags.add(t));
        }
        _saveDraft();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: .16) : Tokens.card(b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? c : Tokens.sep(b), width: 1.5),
        ),
        child: Text(
          '#$t',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            color: sel ? c : Tokens.label2(b),
          ),
        ),
      ),
    );
  }

  Widget tagBox(Brightness b) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Tokens.card(b),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < _tags.length; i++)
            TagChip(_tags[i],
                compact: true,
                onDelete: () {
                  setState(() => _tags.removeAt(i));
                  _saveDraft();
                }),
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110),
              child: TextField(
                controller: _tagIn,
                style: TextStyle(fontSize: 13, color: Tokens.label(b)),
                decoration: InputDecoration(
                  hintText: '新标签（可选）',
                  hintStyle: TextStyle(color: Tokens.label3(b)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                ),
                onSubmitted: (v) {
                  final tag =
                      v.trim().replaceFirst(RegExp('^#'), '');
                  if (tag.isNotEmpty && !_tags.contains(tag)) {
                    if (_tags.length >= 6) {
                      _show('最多 6 个标签');
                    } else {
                      setState(() => _tags.add(tag));
                    }
                  }
                  _tagIn.clear();
                  _saveDraft();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget mediaRow(Brightness b) {
    const gradients = [
      [Color(0xFFFFB199), Color(0xFFFF0844)],
      [Color(0xFF5EFCE8), Color(0xFF736EFE)],
      [Color(0xFFF9D423), Color(0xFFFF4E50)],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 编辑模式：已附媒体（密文引用保留；如需删除走删除条目，编辑页不提供）
          if (_isEdit)
            for (final m in widget.editEntry!.payload.media)
              if (m.kind == 'image')
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Tokens.fill(b),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lock_outline,
                      size: 16, color: Tokens.label2(b)),
                ),
          if (_isEdit &&
              widget.editEntry!.payload.media.any((m) => m.kind == 'audio'))
            WavePill(
              seconds: widget.editEntry!.payload.media
                      .firstWhere((m) => m.kind == 'audio')
                      .sec ??
                  0,
            ),
          for (var i = 0; i < _photos.length; i++)
            GestureDetector(
              onTap: () => setState(() => _photos.removeAt(i)),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradients[i % gradients.length],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_photos[i], fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_photos.length < 9)
            GestureDetector(
              onTap: _pickPhotos,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Tokens.label3(b), width: 1.5, style: BorderStyle.solid),
                ),
                child: Icon(Icons.add, color: Tokens.label3(b)),
              ),
            ),
          // 录音按钮
          GestureDetector(
            onTap: _recording ? _stopRecording : _startRecording,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording ? Tokens.red(b) : Tokens.fill(b),
              ),
              child: Center(
                child: _recording
                    ? Text(
                        '0:${_recSecs.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      )
                    : Icon(Icons.mic, size: 21, color: Tokens.label(b)),
              ),
            ),
          ),
          if (_audioDone != null && !_recording)
            GestureDetector(
              onTap: () =>
                  setState(() { _audioDone = null; _audioSecs = 0; }),
              child: WavePill(seconds: _audioSecs),
            ),
        ],
      ),
    );
  }
}
