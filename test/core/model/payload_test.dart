// 载荷序列化与天分组测试。
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

EntryPayload _p({
  String text = '正文',
  String time = '21:14',
  String? mood = 'happy',
  List<String> tags = const ['工作'],
  List<MediaRef> media = const [],
  List<EntryComment> comments = const [],
}) =>
    EntryPayload(
      text: text,
      time: time,
      mood: mood,
      tags: tags,
      media: media,
      comments: comments,
    );

void main() {
  test('payload encode/decode 往返', () {
    final p = _p(
      text: '一句话\n两行',
      tags: ['工作', '吐槽'],
      media: const [
        MediaRef(id: 45, kind: 'image', cekB64: 'AAAA'),
        MediaRef(id: 47, kind: 'audio', cekB64: 'BBBB', sec: 12),
      ],
      comments: const [EntryComment(who: '我', text: '好', time: '21:30')],
    );
    final back = EntryPayload.decode(p.encode());
    expect(back.v, 1);
    expect(back.text, p.text);
    expect(back.time, '21:14');
    expect(back.mood, 'happy');
    expect(back.tags, ['工作', '吐槽']);
    expect(back.media.length, 2);
    expect(back.media[1].sec, 12);
    expect(back.comments.length, 1);
    expect(back.comments[0].who, '我');
  });

  test('payload 可缺省字段容错（旧版本/精简 JSON）', () {
    final p = EntryPayload.decode(
        '{"text":"hi","time":"08:01","mood":null}');
    expect(p.text, 'hi');
    expect(p.mood, isNull);
    expect(p.tags, isEmpty);
    expect(p.comments, isEmpty);
  });

  test('天分组：倒序 + deleted 剔除', () {
    DiaryEntry e(String date, String id) => DiaryEntry(
          localId: id,
          serverId: null,
          date: date,
          payload: _p(),
          cipherJson: null,
          updatedAt: DateTime(2026, 11, 13),
        );
    final entries = [
      e('2026-11-12', 'a'),
      e('2026-11-13', 'b'),
      e('2026-11-12', 'c'),
    ];
    final del = e('2026-11-10', 'd').copyWith(deleted: true);
    final groups = groupByDay([...entries, del]);
    expect(groups.length, 2);
    expect(groups[0].key, '2026-11-13');
    expect(groups[1].key, '2026-11-12');
    expect(groups[1].value.length, 2);
  });

  test('组内排序：时间顺序升序（写作先后，晨 19 §5.8；与库行序/插序解耦）', () {
    DiaryEntry e(String id, String time) => DiaryEntry(
          localId: id,
          serverId: null,
          date: '2026-11-13',
          payload: _p(time: time),
          cipherJson: null,
          updatedAt: DateTime(2026, 11, 13),
        );
    // 输入乱序（模拟同步后按库行序重建）→ 组内确定性输出写作顺序：早→晚
    final groups = groupByDay([e('a', '09:15'), e('b', '22:30'), e('c', '12:00')]);
    expect(groups.single.value.map((x) => x.localId).toList(),
        ['a', 'c', 'b']);
  });

  test('组内排序：同分钟并列按创建序 createdAt；updatedAt 兜底（晨 19 §5.8）', () {
    DiaryEntry e(String id, DateTime created, DateTime updated) => DiaryEntry(
          localId: id,
          serverId: null,
          date: '2026-11-13',
          payload: _p(time: '10:00'),
          cipherJson: null,
          updatedAt: updated,
          createdAt: created,
        );
    final groups = groupByDay([
      e('late', DateTime(2026, 11, 13, 10, 1), DateTime(2026, 11, 13, 10, 1)),
      e('early', DateTime(2026, 11, 13, 10, 0), DateTime(2026, 11, 14, 9)),
    ]);
    // 同分钟并列：早创建在前（updatedAt 更新的 late 不因「新更新」排前）
    expect(groups.single.value.map((x) => x.localId).toList(), ['early', 'late']);
  });

  test('组内排序：评论/编辑刷新 updatedAt 不改变顺序（晨 19 §5.8 拍板）', () {
    DiaryEntry e(String id, String time, DateTime updated) => DiaryEntry(
          localId: id,
          serverId: null,
          date: '2026-11-13',
          payload: _p(time: time),
          cipherJson: null,
          updatedAt: updated,
        );
    final before = groupByDay([
      e('morning', '08:00', DateTime(2026, 11, 13, 8)),
      e('evening', '21:00', DateTime(2026, 11, 13, 21)),
    ]).single.value.map((x) => x.localId).toList();
    // 模拟评论：把早条目的 updatedAt 刷到最晚（评论不影响排序）
    final commented = groupByDay([
      e('morning', '08:00', DateTime(2026, 11, 14, 23)),
      e('evening', '21:00', DateTime(2026, 11, 13, 21)),
    ]).single.value.map((x) => x.localId).toList();
    expect(before, ['morning', 'evening']);
    expect(commented, ['morning', 'evening']);
  });
}
