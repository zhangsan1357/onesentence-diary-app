// 演示数据 = mockup v2 的 ENTRIES 逐条移植（Chrome 视觉迭代用，M2-b 对照）。
// cek 为空的 MediaRef 表示 demo 占位（UI 渲染渐变色块，不发网络请求）。
// 头像：demo 无后端 → 用 avatar.dart 同款模板（与后端定稿格式一致）本地拼。
import '../model/diary_entry.dart';
import '../util/avatar.dart';

DiaryEntry _demo({
  required String date,
  required String time,
  required String text,
  String? mood,
  List<String> tags = const [],
  int images = 0,
  int audioSec = 0,
  int imageSeed = 0,
  List<EntryComment> comments = const [],
  required int seq,
}) {
  final media = <MediaRef>[
    for (var i = 0; i < images; i++)
      MediaRef(id: -(1000 + imageSeed * 20 + i), kind: 'image', cekB64: ''),
    if (audioSec > 0)
      MediaRef(id: -9, kind: 'audio', cekB64: '', sec: audioSec),
  ];
  return DiaryEntry(
    localId: 'demo-$date-$seq',
    serverId: null,
    date: date,
    payload: EntryPayload(
      text: text,
      time: time,
      mood: mood,
      tags: tags,
      media: media,
      comments: comments,
    ),
    cipherJson: null,
    updatedAt: DateTime.parse('$date $time'.replaceFirst(' ', 'T')),
    avatarUrl: avatarUrl('demo-$date-$seq'),
  );
}

const demoYearAgo = EntryPayload(
  text: '深夜，服务终于跑通了第一版。写一句话纪念今天。',
  time: '23:47',
  mood: 'happy',
);

/// 与 mockup v2 完全一致的示例数据（回忆/统计也以它计算视觉对照）。
final demoEntries = <DiaryEntry>[
  _demo(
    date: '2026-11-12', seq: 1, time: '21:14', mood: 'angry',
    tags: ['工作', '吐槽'],
    text: '今天又开了三个小时的会。领导说我们要「拥抱变化、降本增效」，说完把这四个字写在了白板上，字很丑。\n然后是 OKR 对齐、向上管理、颗粒度……每个词我都认识，连在一起就听不懂了。\n散会的时候已经快八点，走出大楼那一刻，晚风一吹，突然觉得也没那么糟——至少今天不用加班了。\n回来路上买了两个烤红薯，一个给门卫大爷，他说我像他孙子。就为这句话，今天的班也没白上。',
    comments: const [
      EntryComment(who: '我', text: '这会我也在，罚款三小时。', time: '21:30'),
      EntryComment(who: '她', text: '然后呢？快更。', time: '22:05'),
    ],
  ),
  _demo(
    date: '2026-11-11', seq: 1, time: '20:15', mood: 'happy',
    tags: ['生活'], images: 1,
    text: '光棍节什么都没买，省下的钱给自己买了杯热的。',
  ),
  _demo(
    date: '2026-11-11', seq: 2, time: '23:08', mood: 'tired',
    tags: ['工作'], audioSec: 12,
    text: '加班到十一点，出租车的窗上映着我的哈欠。',
    comments: const [EntryComment(who: '我', text: '第二天果然起不来。', time: '07:30')],
  ),
  _demo(
    date: '2026-11-09', seq: 1, time: '13:12', mood: 'love',
    tags: ['她'], images: 2, imageSeed: 1,
    text: '她突然发来一句「在干嘛」，我盯着屏幕笑了半天。',
  ),
  _demo(
    date: '2026-11-08', seq: 1, time: '16:33', mood: 'surprise',
    tags: ['生活', '摄影'], images: 9, imageSeed: 2,
    text: '第一次给多肉换盆，没想到这么解压。',
    comments: const [
      EntryComment(who: '我', text: '第几盆了？', time: '17:00'),
      EntryComment(who: '她', text: '下次教我。', time: '18:21'),
      EntryComment(who: '我', text: '他们状态好就说明你厉害。', time: '18:25'),
      EntryComment(who: '我', text: '阳台快放不下了。', time: '18:26'),
      EntryComment(who: '她', text: '哈哈，保重。', time: '19:40'),
    ],
  ),
  _demo(
    date: '2026-10-28', seq: 1, time: '22:41', mood: 'tired',
    tags: ['工作'], audioSec: 8,
    text: '加班到十点，窗外的雨一直没停。',
  ),
  _demo(
    date: '2026-10-24', seq: 1, time: '16:33', mood: 'surprise',
    tags: ['生活'], images: 2, imageSeed: 3,
    text: '把阳台的灯换成暖光，晚饭后突然有了生活气息。',
  ),
  _demo(
    date: '2026-10-21', seq: 1, time: '13:12', mood: 'happy',
    tags: ['美食'],
    text: '楼下新开的牛肉面，加了双份辣，通透。',
  ),
  _demo(
    date: '2026-10-17', seq: 1, time: '19:05', mood: 'love',
    tags: ['她', '电影'], images: 1, imageSeed: 4,
    text: '和她去看 IMAX，散场时她说下次还来。',
    comments: const [EntryComment(who: '我', text: '下次我选片子。', time: '20:00')],
  ),
  _demo(
    date: '2026-10-15', seq: 1, time: '21:26', mood: 'sad',
    tags: ['她'],
    text: '她今天没回消息，晚风也很凉。',
  ),
  _demo(
    date: '2026-10-12', seq: 1, time: '22:10', mood: 'happy',
    tags: ['工作'],
    text: '把搁置两周的 bug 修了，原来只是少一个等号。',
  ),
  _demo(
    date: '2026-10-10', seq: 1, time: '08:47', mood: 'angry',
    tags: ['吐槽'],
    text: '周六调休上班，地铁上人人面如死灰，包括我。',
  ),
  _demo(
    date: '2026-10-08', seq: 1, time: '09:15', mood: 'tired',
    tags: ['工作'],
    text: '假期结束第一天，键盘都生了三天假的味道。',
  ),
  _demo(
    date: '2026-10-05', seq: 1, time: '12:31', mood: 'angry',
    tags: ['家庭'],
    text: '亲戚又问「什么时候买房」，我笑而不语。',
  ),
  _demo(
    date: '2026-10-02', seq: 1, time: '17:40', mood: 'happy',
    tags: ['生活'], images: 12, imageSeed: 5,
    text: '高速堵了四个小时，全家在车里唱完了整本周杰伦。',
    comments: const [
      EntryComment(who: '她', text: '七里香起头的是我。', time: '18:00'),
      EntryComment(who: '我', text: '跑调也是你。', time: '18:01'),
      EntryComment(who: '她', text: '……', time: '18:02'),
    ],
  ),
  _demo(
    date: '2026-09-27', seq: 1, time: '08:52', mood: 'angry',
    tags: ['吐槽'],
    text: '调休上班，周日挤地铁，想骂人。',
  ),
  _demo(
    date: '2026-09-25', seq: 1, time: '21:03', mood: 'happy',
    tags: ['生活'], images: 1, imageSeed: 6,
    text: '中秋一个人吃了块月饼，居然觉得还不错。',
  ),
];

/// 回忆页「随机翻一条」示例池（mockup POOL）。
const demoRandomPool = [
  (mood: 'surprise', text: '电梯里遇见老板，我默默按了关门。'),
  (mood: 'happy', text: '食堂阿姨今天多给了一勺土豆。'),
  (mood: 'sad', text: '雨下了一整天，伞忘在公司。'),
  (mood: 'happy', text: '睡前列了明天的清单，只有一条：好好吃饭。'),
];

/// mockup 连续天数示例（视觉对照）。
const demoStreak = 23;
