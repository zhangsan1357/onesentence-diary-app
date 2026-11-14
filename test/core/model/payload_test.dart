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
}
