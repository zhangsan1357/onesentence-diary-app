// 领域模型 + 加密载荷 schema。
// 契约注意：外层密文三字段（ciphertext/nonce_content/encrypted_cek）是 02 §5 冻结契约；
// 载荷 JSON（加密前的明文结构）是客户端自由度，本文件即其唯一事实源。
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 媒体引用（密文内的明文引用：媒体本体已端上加密后单独上传）。
@immutable
class MediaRef {
  final int id;
  final String kind; // image | audio
  final String cekB64; // 媒体 CEK 的 92B ECIES 包裹（b64），与条目密钥独立
  final int? sec; // 音频秒数

  const MediaRef({
    required this.id,
    required this.kind,
    required this.cekB64,
    this.sec,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'cek': cekB64,
        if (sec != null) 'sec': sec,
      };

  static MediaRef fromJson(Map<String, dynamic> j) => MediaRef(
        id: j['id'] as int,
        kind: j['kind'] as String,
        cekB64: j['cek'] as String,
        sec: j['sec'] as int?,
      );
}

/// 评论（内嵌于载荷；契约无独立评论接口，见 PROGRESS 契约缺口记录）。
@immutable
class EntryComment {
  final String who;
  final String text;
  final String time; // 新评论 yyyy-MM-dd HH:mm；存量 HH:mm（显示时补条目日期）

  const EntryComment({required this.who, required this.text, required this.time});

  Map<String, dynamic> toJson() => {'who': who, 'text': text, 'time': time};

  static EntryComment fromJson(Map<String, dynamic> j) => EntryComment(
        who: j['who'] as String,
        text: j['text'] as String,
        time: j['time'] as String,
      );
}

/// 载荷（= ciphertext 解密后的明文 JSON）。
@immutable
class EntryPayload {
  final int v;
  final String text;
  final String time; // HH:mm，等宽字体行内前缀
  final String? mood; // mood_key，null=未选
  final List<String> tags;
  final List<MediaRef> media;
  final List<EntryComment> comments;

  const EntryPayload({
    this.v = 1,
    required this.text,
    required this.time,
    required this.mood,
    this.tags = const [],
    this.media = const [],
    this.comments = const [],
  });

  Map<String, dynamic> toJson() => {
        'v': v,
        'text': text,
        'time': time,
        'mood': mood,
        'tags': tags,
        'media': media.map((m) => m.toJson()).toList(),
        'comments': comments.map((c) => c.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static EntryPayload decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return EntryPayload(
      v: j['v'] as int? ?? 1,
      text: j['text'] as String? ?? '',
      time: j['time'] as String? ?? '00:00',
      mood: j['mood'] as String?,
      tags: (j['tags'] as List?)?.cast<String>() ?? const [],
      media: (j['media'] as List?)
              ?.map((m) => MediaRef.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      comments: (j['comments'] as List?)
              ?.map((c) => EntryComment.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// 待同步标记 meta（库行 pendingMeta 列的 JSON，2026-11-16 晨 15）：
/// {"t":true,"c":[3,4]} → (正文/心情/标签有离线改动, 离线新增评论下标)。
/// 评论 append-only → 下标稳定；冲正成功即清空。坏 JSON 按无标记处理。
({bool text, List<int> comments}) parsePendingMeta(String? s) {
  if (s == null || s.isEmpty) return (text: false, comments: const []);
  try {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return (
      text: j['t'] == true,
      comments: (j['c'] as List?)?.map((e) => e as int).toList() ?? const [],
    );
  } catch (_) {
    return (text: false, comments: const []);
  }
}

String encodePendingMeta(bool text, List<int> comments) {
  if (!text && comments.isEmpty) return '';
  return jsonEncode({
    if (text) 't': true,
    if (comments.isNotEmpty) 'c': comments,
  });
}

/// 日记条目（领域模型：明文字段 + 密文引用）。
@immutable
class DiaryEntry {
  final String localId; // 本机 uuid，稳定主键
  final int? serverId; // 服务端 id（null=尚未同步/演示数据）
  final String date; // yyyy-MM-dd（明文，天粒度）
  final EntryPayload payload;
  final String? cipherJson; // Envelope 序列化 JSON（null=未落库）
  final DateTime updatedAt;
  final bool deleted;
  final String? avatarUrl; // 后端 EntryVO.avatar 链接（客户端只消费不拼装；demo/评论用同款模板）
  // 待同步标记（显示层 * 前缀的唯一依据，来自库行 pendingMeta；冲正/推云成功即清）
  final bool textPending;
  final List<int> pendingComments;

  const DiaryEntry({
    required this.localId,
    required this.serverId,
    required this.date,
    required this.payload,
    required this.cipherJson,
    required this.updatedAt,
    this.deleted = false,
    this.avatarUrl,
    this.textPending = false,
    this.pendingComments = const [],
  });

  DiaryEntry copyWith({
    String? localId,
    int? serverId,
    String? date,
    EntryPayload? payload,
    String? cipherJson,
    DateTime? updatedAt,
    bool? deleted,
    String? avatarUrl,
    bool? textPending,
    List<int>? pendingComments,
  }) =>
      DiaryEntry(
        localId: localId ?? this.localId,
        serverId: serverId ?? this.serverId,
        date: date ?? this.date,
        payload: payload ?? this.payload,
        cipherJson: cipherJson ?? this.cipherJson,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        textPending: textPending ?? this.textPending,
        pendingComments: pendingComments ?? this.pendingComments,
      );

  /// 从库行 pendingMeta 解析结果重建待同步标记（_refreshMarks 唯一写入口）。
  DiaryEntry copyWithMark(({bool text, List<int> comments}) meta) => copyWith(
        textPending: meta.text,
        pendingComments: meta.comments,
      );
}

/// 天分组：按日期聚合、倒序排列（feed 渲染单位）。
List<MapEntry<String, List<DiaryEntry>>> groupByDay(List<DiaryEntry> entries) {
  final map = <String, List<DiaryEntry>>{};
  for (final e in entries) {
    if (e.deleted) continue;
    map.putIfAbsent(e.date, () => []).add(e);
  }
  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) MapEntry(k, map[k]!)];
}
