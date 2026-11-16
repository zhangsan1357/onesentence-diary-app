# 一句话日记 · 整体设计书

> 本文档是本仓库的**设计事实源**（design source of truth）。
> **流程约束（2026-11-16 用户拍板，已写入 AGENTS.md）：任何功能/行为改变，必须先修改本
> 文档（或对应设计文档）并提交，再改代码**——设计文档的 diff 是改动意图的第一现场，
> 代码 diff 是设计的执行结果。
>
> 只读真源边界：冻结契约（02 §5）、产品规格（01/03/04）在手册套件
> `E:\workSpace\goProject\tcl_ai\docs\一句话日记\`（**不得修改**）。本文档不复制契约
> 字段定义，只记录端上设计决策、实现结构与演进记录；与手册冲突时以手册为真源并在此
> 记录「契约缺口」。

## 1. 系统总览

### 1.1 分层架构

```
features/{shell,feed,compose,calendar,memory,me,lock,theme}   ← UI（Riverpod 消费）
        │  watch appSessionProvider (AppState)
AppSession（core/session/app_session.dart）                    ← 会话层：唯一业务编排
        │                      │
ApiClient（core/api）       LocalStore（core/db，drift v3）     ← 云端契约 / 本地事实源
        │                      │
后端 127.0.0.1:9060        sqlite 落盘（entries / kv / pending_media）
```

- **AppState**：UI 可见的全部状态（entries/locked/syncError/pendingCount/toast…），
  `copyWith` 语义；后台回写经 `_set`（容器释放时静默丢弃）。
- **会话层是唯一写入口**：UI 不直接碰 ApiClient / LocalStore；测试经
  `debugUseStore / debugUseApi / debugRestorePlainSession` 注入。

### 1.2 全局不变量（违反即 bug）

| 不变量 | 落点 |
|---|---|
| 端到端加密：服务端只见密文，密钥不出本机 | core/e2ee（Envelope：每条独立 CEK，媒体 CEK 独立 ECIES） |
| 落盘零明文（P1-3）：库行只存密文，读取时才解密 | `_upsertLocal`（payloadJson 列复用存密文）/ `_loadLocalEntries` |
| 契约冻结（02 §5）：字段名严格一致，缺口只记录不擅改 | core/api/api_client.dart 头注释 + PROGRESS 契约缺口记录 |
| 锁定清内存（P1-4）：lock() 清明文索引，解锁后从密文重建 | `lock()` / `_loadLocalEntries` |
| 显示层标记不入载荷：任何 UI 标注（* 徽标等）只在渲染时注入 | `pendingMark`（widgets/common.dart） |

### 1.3 平台范围（用户拍板 2026-11-13）

仅 iOS（android/windows/linux/macos 已删）；Windows 开发机用 Chrome web 预览；
GitHub Actions（macos-latest）push main 自动出未签名 ipa → Sideloadly 自签装真机。

## 2. 离线同步体系（2026-11-16 设计，晨 14/15 落地；晨 17 修订：写路径本地先行）

### 2.1 目标与语义

1. **云端不可达时增删改全部本地保存**，体验与在线一致（toast 明示「已本地保存」）。
2. **冲正由当前写操作后台触发一次 + 手动刷新兜底**（解锁后同步 / 下拉刷新 / 横幅重试
   ——用户拍板**不加定时自动重试**；晨 17 修订：写路径本地先行后，每次写完立即
   `unawaited` 后台冲正一次，遗留队列仍只由手动刷新续传）。
3. **队列的是条目最终态，不是操作日志**：同一离线窗口内对同一条目的多次修改收敛为一
   行的最终内容（编辑覆盖编辑），冲正=把最终态按序推云（last-write-wins）。
4. 网络层失败（DioException）= 离线留队；业务错误（ApiException 4xx/5xx）= 留队 +
   同步横幅（晨 17 修订：本地先行后写操作必然先落库，业务错误不再回滚——数据零丢失，
   横幅明示失败原因，条目保留 `*` 标记）。
5. **写路径本地先行（晨 17）**：发布/编辑/评论/删除一律先本地落库（加密）再后台推云，
   UI 不等网络——在线慢、离线断网、云端黑洞三种情况的界面响应都是即时的（真机反馈：
   离线发帖/评论明显卡顿）。在线路径由「先拿 serverId 再落库」改为「先落库后台回填」，
   `serverId == null` 的窗口从「离线期间」扩大为「推送完成前」。

### 2.2 状态模型（drift v3，schemaVersion=3）

| 存储 | 字段/列 | 语义 |
|---|---|---|
| `Entries.syncState` | 0/1/2/3 | 0=已同步；1=待新建；2=待替换；3=待删除。非 0 行是本地最终态，**拉取同步必须跳过** |
| `Entries.pendingMeta` | JSON `{"t":true,"c":[3,4]}` | 待同步标记：t=正文/心情/标签有离线改动；c=离线新增评论下标（评论 append-only → 下标稳定）。坏 JSON 按无标记处理；推云/冲正成功即清空（''） |
| `PendingMedia` 表 | localId/kind/sec/**bytes**/cekWrappedB64 | 离线暂存媒体：**端上加密后才落盘**（bytes = nonce12‖AES-GCM 密文，P1-3 同款约束）；冲正时上传并注入引用 |

迁移：v2（syncState 列 + PendingMedia 表）、v3（pendingMeta 列），见 `database.dart
MigrationStrategy`。踩坑记录：drift 列名不能用 `blob`（与 Table.blob 构建器冲突）→
`bytes`。

### 2.3 写路径矩阵（会话层四个公开操作 × 晨 17 本地先行后统一为一条路）

| 操作 | 统一路径（在线/离线同型，UI 即时返回） | 后台冲正结果 |
|---|---|---|
| publish | 媒体全部端上加密→**暂存**（载荷不含引用）→整条加密→本地 syncState=1 + meta{t}→UI 即现+高亮 | 上传媒体→注入引用→重加密→create→回填 serverId→syncState=0+清 meta/暂存；DioException→留队+toast「云端不可达」；ApiException→留队+横幅 |
| updateEntry | 新载荷加密→本地落库（serverId!=null→syncState=2；null→保 1）+meta 合并 t→UI 即现 | replace→syncState=0+清 meta；失败同上 |
| addComment | 整条重加密→本地落库（syncState 同上）+meta 合并 c+=新下标→UI 即现 | replace→syncState=0+清 meta；失败同上 |
| deleteEntry | serverId=null→**本地硬删不入队**（无服务端可删）；else→syncState=3+本地 deleted=true→UI 即隐 | delete（404 视为已删成功）→syncState=0；DioException→留队（条目保持隐藏） |

要点：
- `serverId == null` 只可能是「尚未推成」（离线新建，或本地先行窗口期内）。
- 待同步条目的暂存媒体在**再次编辑时重置**（deletePendingMediaFor 后重插），保证「队列
  里存的媒体 = 载荷里尚未注入引用的媒体」，冲正不重传不遗漏。
- 401 在冲正路径内透明重注册一次（现状保留）。
- 后台冲正与手动刷新冲正共用 `_flushDirty`，语义完全一致；区别只是「unawaited」与
  「await（横幅路径）」。

### 2.4 冲正算法 `_flushDirty`（晨 17 增补并发保护与内存重建）

1. 取 `syncState != 0` 的行，按 `updatedAtMs` **从旧到新**排序。
2. 每行：有暂存媒体（且非待删除）→ 逐个上传 → 解密载荷注入 MediaRef → 整条重加密
   （明文只在内存）；无媒体 → 直接用库内 cipherJson。
3. 按 syncState 分派：1→create（回填 serverId）；2→replace；3→delete（**404 视为已删
   成功**）。成功即 `syncState=0` + `pendingMeta=''` + 清该条暂存媒体。
4. **中途 DioException → 中断保留队列**（已推成的已清、未推的下次续传）；ApiException
   → syncError 横幅（后台路径与手动路径一致展示），队列保留、条目保留 `*`。
5. `finally` 调 `_loadLocalEntries()` 重建内存（serverId/载荷引用/标记/计数一并刷新；
   中断也刷——未冲正的标记保留在 UI 上）。
6. **并发保护（晨 17）**：`_flushing` 标志——已在冲正时再次触发直接跳过（写路径的后台
   触发与手动刷新可能撞车）；跳过的遗留行由下一次触发或手动刷新续传。
7. `flushNow()` 公开（= `_flushDirty` 的 await 包装）：测试与横幅重试的显式入口。

### 2.5 同步编排 `syncNow`

```
syncNow = _flushDirty()（先冲正） → _syncOnce()（全量拉取，纪元游标） → 清 syncError
          → dataRev+1（晨 17：驱动 UI 一次性动作，如收起评论） → 标签/心情配置双写（晨 17 §4.1）
```

- **拉取保护**：`_syncOnce` 对本地 `syncState != 0` 的行直接 continue——云端旧密文不得
  覆盖本地未上云的新密文。
- **推云成功即收敛**：冲正成功路径无条件 `syncState=0`（该次载荷包含全部离线改动），
  并清 dirty 行的 meta。
- `dataRev` 只在 syncNow 完成时自增（成功才增——失败带横幅返回，UI 不做「刷新后」动作）。

### 2.6 待同步标记（显示层）

- **三条约束（用户拍板）**：① 只进显示层，绝不写载荷（编辑预填/搜索/导出全消费原始
  payload）；② 橙色 `*`（`widgets/common.dart pendingMark`），与页头「N 条待同步」徽标
  同色——橙星=这条还没上云；③ 精确到部分——正文标 `textPending`、评论按
  `pendingComments.contains(下标)`，互不误伤。
- **唯一写入口 `_refreshMarks()`**：库行 pendingMeta → 内存 DiaryEntry 重建标记与
  pendingCount。所有写路径（入队/合并/冲正/删除/登录登出）只改库行，内存一律由此刷
  新，杜绝多处手工维护漂移。
- 渲染点：feed 正文 `Text.rich`（EntryView._body）、评论（CommentsView，indexed）。
  编辑预填、导出、搜索命中不消费标记。
- 晨 17 注：写路径本地先行后，在线场景标记也会短暂出现（落库到冲正成功之间，通常
  几百毫秒）——这是「还没上云」的诚实呈现，不是缺陷。

### 2.7 头像链路 v2：本地动物脸池随机（晨 17 修订，替代晨 15 方案 D）

- **用户提议评估（晨 17）**：「评估一张图多大、缓存 1w 张占多少磁盘，不大就随机调用」。
  实测：cravatar s=138（46pt@3x）单张 **4162 B**（PNG），冷缓存首字节 3.88s（复证慢在
  服务端生成）。1w 张 ≈ **42 MB** 磁盘——磁盘可承受，但获取需 1w 次 CDN 请求（冷缓存
  ~4s/张，不可行），打包进 ipa +42MB 也不可取。
- **决策（晨 17 用户拍板方向）**：「随机调用」用**本地 20 动物脸池**实现——与评论头像
  同款（晨 15 已拍板的裸 emoji 表），零网络、零磁盘、零等待，随机性语义与评论盐一致。
  天卡头像种子 = `$salt|$dateKey`（盐沿用 `avatarSaltProvider`，每次刷新换新 → 每天卡
  每轮随机换脸），同一刷新周期内稳定。
- **拆除链路**：NetAvatar 组件、feed 预取（`dayAvatarUrls`/`_precached`/precacheImage）、
  `_avatars` 内存映射、`DiaryEntry.avatarUrl` 字段、`util/avatar.dart` URL 模板与 demo
  引用一并退役（本次改动孤儿化，按 AGENTS.md 清理）。`ServerEntry.avatar` 契约字段保留
  解析不消费（文档化契约）。
- **推翻记录**：2026-11-15「头像 URL 事实源在后端，客户端不拼装」拍板就此废止；若后续
  会话 A 定稿 EntryVO.avatar 规则（A/B 方案），可再切换回来。
- 尺寸（晨 17 真机反馈）：天卡头像 46→**56**；评论头像 32→**24**（原版 d776648 尺寸）。

### 2.8 已知取舍与边界（晨 17 更新）

| 边界 | 现行为 | 理由 |
|---|---|---|
| 离线发带图/录音 | 媒体暂存但不入卡位（冲正后才显示） | 引用注入只能发生在上传拿到 id 之后；诚实呈现「未上云」状态 |
| 双端并发冲突 | 冲正按本地顺序 last-write-wins；拉取不覆盖 dirty | 个人日记量级，不做逐字段合并 |
| ApiException 留队 | 业务错误不回滚：条目保留 `*` + 横幅明示；每次刷新重试同一行 | 本地先行后先落库；回滚=用户感知丢数据，重试失败可见优于静默丢弃 |
| 在线发布 serverId 回填 | 落库后到后台冲正完成前 serverId=null | 本地先行的代价窗口；`serverId==null` 语义从「离线新建」扩为「尚未推成」 |
| 冲正期间新写操作 | `_flushing` 时后台触发跳过，行留队待下次 | 避免两路冲正并发写同一行；手动刷新始终可续传 |
| 草稿缓存不含媒体 | 草稿只存正文/心情/标签（KV 小体积）；媒体需重选 | 媒体字节大，KV 不适合；「文字零丢失」是主要诉求 |
| 键盘收起不拦子控件 | 空白处点按才收起；按钮/输入框等交互控件保持键盘 | 微信式「点空白收起」+ 用户要求「不能太敏感」；滚动不收键盘（更保守） |
| 标签/心情合并规则 | 拉取=补缺合并（同名本地优先）；删除名单防复活 | 契约无时间戳 → 无法 last-write-wins；无删除端点（缺口 #8） |
| 离线新建+离线删除 | 本地直接清除，不上队 | 无服务端可删，留队只会推 404 |
| 断网窗口内先建后删 | 硬删，云端从未见过该条 | 同上 |
| dart:io 无磁盘 HTTP 缓存 | 已随头像本地化失效（无网络头像） | 原 §2.7 问题域消失 |

### 2.9 测试映射（离线体系，晨 17 更新）

| 设计点 | 测试 |
|---|---|
| 本地先行：发布落库即现（不等网络） | offline_sync_test：publish 后立即断言本地行/entries，不先 await 网络 |
| 入队（发布/编辑/评论/删除 × 断网） | offline_sync_test 断网组（FakeApi.online 开关；DioException=断网信号） |
| 冲正（含幂等、中断续传、媒体注入、serverId 回填） | offline_sync_test 冲正/续传/带图组（在线写路径显式 flushNow/syncNow 后断言） |
| 冲正并发保护（_flushing 跳过） | offline_sync_test：冲正中再触发不重放 |
| ApiException 留队 + 横幅 | offline_sync_test：业务错误行保留 + syncError 置位 |
| pendingMeta 编解码与容错 | offline_sync_test 编解码项 |
| 标记流转（入队标→冲正清，按部分精确） | offline_sync_test 标记 3 项 |
| 标记渲染（正文/评论精确标注） | pending_mark_test 2 项 |
| 天卡动物脸池（种子稳定/盐换脸） | animal_avatar_test / feed 头像测试 |
| 组内排序（time desc 确定性） | diary_entry 组内排序单测（offline_sync 或独立单测） |

### 2.10 本节变更记录

| 日期 | 变更 | 提交 |
|---|---|---|
| 2026-11-16 晨 14 | 离线队列 v2：syncState/PendingMedia/冲正/拉取保护（用户拍板无定时重试） | b1d03a5 |
| 2026-11-16 晨 15 | 库 v3：pendingMeta 标记体系 + 方案 D 头像预取/淡入 | 4bb7525 |
| 2026-11-16 | 本设计书建立，确立「设计先行」流程 | （晨 16 提交） |
| 2026-11-16 晨 17 | 写路径本地先行（§2.1/2.3/2.4/2.5/2.6/2.8/2.9 修订）+ 头像本地动物脸池（§2.7 重写） | （本批次） |

## 3. 设计先行流程（对本文件自身的约束）

1. **改设计**：先在本文件（或对应设计文档）写清楚「改什么、为什么、边界」并提交。
2. **改代码**：按文档执行；实现与文档出现偏差时，以先提交的文档为准修正代码，或反过
   来补文档（允许「实现中发现设计错了」→ 撤销/追加设计提交）。
3. **验证**：测试映射表随设计一并更新；`flutter analyze` 零告警 + 全量测试绿是合入
   门槛。
4. **记录**：PROGRESS.md 只记里程碑与踩坑（运行日志性质），设计语义一律归本文件。

## 4. 晨 17 批次：真机反馈 13 项设计（2026-11-16）

> 来源：真机验收反馈。①~⑬ 逐项：问题定位 → 设计 → 边界。③（注册名/主密钥变更）
> 触及服务端身份不变量，**只给设计草案提请拍板，本轮不实现**。

### 4.1 标签/心情云端双写（契约内能力）

- **现状**：标签/心情显示配置是设备本地 KV（`cfgKvKeys`），`api_client.dart` 已定义
  未消费的 §5.5 端点。契约能力（02 手册只读）：`GET/POST /config/tags`（POST 同
  device 同名=更新）；`GET /config/moods`（6 种子行，只读）。**无标签删除端点、无心情
  写入端点** → 契约缺口 #8（记录，提请会话 A 扩展；且 tag 配置按 device 键控，跨设备
  同步契约本就不承诺）。
- **设计**：
  - **推**：`addTagPreset`/`setTagColor` 变更后 `unawaited(saveTag(name, color))`——
    color 推「当前生效色名」（无自定义时推稳定哈希解析色，把自动色物化为显式色）；
    失败（DioException）静默留本地，不重试（下次变更或刷新再推）。
  - **拉**：syncNow 挂载 `configTags()` + `configMoods()`，**补缺合并**：服务器独有的
    预设名/色并入本地（新增 `tagPresets` 条目与对应 override）；同名条目**本地优先**
    不覆盖（契约无时间戳，无法判新旧）；本地删除名单 `cfg.tagDeleted`（KV）防拉取复活
    已删预设（服务端无删除端点，行会一直在）。
  - **心情**：服务器 6 种子仅填充本地没有的 moodKey（补缺）；本地 overrides/自定义
    心情永远本地优先（无推送通道）。
- **边界**：注销（logout）已清 cfgKvKeys——`cfg.tagDeleted` 一并加入清除名单；合并幂等
  （每次刷新重复合并结果不变）。

### 4.2 天卡排序与组内顺序

- **根因**：`groupByDay` 只对天序（日期倒序）排序，组内条目顺序 = 内存列表顺序 =
  `_loadLocalEntries` 的**库行插入序**。发布时新条目插列表最前（即时正确），但任何
  同步后整表按库序重建 → 同日新条目落到卡底，且跨天卡顺序虽稳定、组内漂移——
  「新吐槽后天卡没有按顺序，刷新也不对」。
- **设计**：`groupByDay` 组内按 `payload.time` **倒序**（"HH:mm" 字典序即时间序），
  同时间按 `updatedAtMs` 倒序——组内顺序从此与库行序、内存插序解耦，任何路径重建后
  结果一致（最新在最上，与发布即现行为一致）。
- **边界**：搜索命中列表同样走 `groupByDay` → 行为一致；不改天序（日期倒序）。

### 4.3 更改注册名 / 更换 12 单词主密钥（只设计，提请拍板，本轮不实现）

- **为什么不能只做客户端**：服务端身份不变量「同 userId 必须同 userKey」（注册时校验）。
  ① 改注册名 = 换 userId → 服务端视为新账号（旧数据不在新空间），不是改名；② 换 12 词
  = 新 userKey → 被「同 userId 同 userKey」校验拒绝。二者都**需要后端配合**。
- **契约缺口 #7（身份变更能力，提请会话 A/用户拍板）**，客户端草案：
  - **改名**：后端提供 rename 端点（如 `POST /device/rename {newUserId}`，服务端重键
    数据空间）→ 客户端：设置页入口 + 二次确认（告知风险）→ 调端点 → 更新本地
    keystore.userId → 重新注册。无端点前不做假 UI。
  - **换主密钥**：后端放行同 userId 换 userKey（或 rotate 端点）→ 客户端协议：生成新
    12 词 → 全量拉取解密（旧钥）→ 全部条目重加密（新身份，逐条 replace 幂等）→
    keystore 重包 → re-register。中断安全：条目级幂等（每条 replace 完成即过半安全），
    KV 记录轮换进度。媒体 blob 无需重传（CEK 包裹在载荷内随条目重加密）。
  - **风险提示**：换主密钥后旧设备（仍持旧钥）将无法解密新密文 → 属于「重新生成身份」
    级操作，需强确认文案；改名影响多设备登录语义（旧名无法再登录）。
- **本轮交付**：仅本节设计 + 缺口记录，代码零改动。

### 4.4 刷新后收起已展开评论（dataRev）

- **设计**：AppState 新增 `dataRev`（int，默认 0）；`syncNow` **成功完成**时 +1。
  `_EntryViewState`（ConsumerStatefulWidget）在 build 里 `ref.listen`
  `appSessionProvider.select((s) => s.dataRev)`，rev 变化且 `_commentsOpen` → 收起。
- **边界**：失败（横幅路径）不增 rev——评论不收；手动收开不受影响；未展开的条目无感。

### 4.5 离线发帖/评论卡顿（→ §2 本地先行）

- **根因**：publish/addComment 内联等待网络（connectTimeout 5s；带图发布 = N×媒体
  上传超时 + 创建超时），UI await 全程。
- **设计**：见 §2.1 语义 5 与 §2.3 矩阵——写路径本地先行，UI 即时返回，推云交给后台
  冲正一次；遗留队列仍由手动刷新续传（保持用户拍板的「无定时重试」）。

### 4.6 发布评论后键盘自动收起

- **设计**：CommentsView `_send()` 提交即 `FocusScope.of(context).unfocus()`（本地先行
  后发送即时返回，收起无感延迟）；发送失败（横幅路径）不回焦。
- **边界**：输入框获焦状态、输入内容（草稿，见 4.12）不因收起丢失。

### 4.7 键盘使用点全量评估（⑦）

| 场景 | 位置 | 现状 | 处理 |
|---|---|---|---|
| feed 搜索条 | feed_page `_searchBar` | autofocus，点外不收 | 主界面统一包裹（4.11）覆盖 |
| 评论输入 | comments_view `_input` | 发送后键盘留驻 | 4.6 unfocus |
| compose 正文 | compose_page 304 | autofocus | compose 包裹（4.11）覆盖 |
| compose 标签输入 | compose_page 503 | onSubmitted 加标签 | 保持（连续加标签键盘不收是合理交互）+ 包裹兜底 |
| 锁定口令 | lock_overlay 168 | onSubmitted 解锁 | 保持（失败留焦便于重试；成功随遮罩消失） |
| 我的页弹窗（改口令/服务端地址/标签心情管理等 8 处） | me/dialogs | 弹窗 barrier 点击=连键盘一起关 | 保持；多字段弹窗 `textInputAction.next/done` 微调 |
| onboarding（恢复词/注册名） | onboarding_page 429/453 | 字段间提交跳转 | 保持 |
| 锁定口令设置 | pass_setup_page 99/117 | onSubmitted 提交 | 保持 |

### 4.8 长按评论误触条目编辑

- **根因**：`EntryView` 根 `GestureDetector(onLongPress→编辑)` 包住整个条目（含
  AnimatedSize 评论区），长按评论冒泡到手势竞技场的父识别器 → 打开的是条目编辑。
- **设计**：CommentsView 根部包 `GestureDetector(onLongPress: () {}, behavior:
  HitTestBehavior.opaque)`——内层长按识别器胜出竞技场，父级编辑不触发；空实现即「吸
  收」。后续给评论加长按菜单（撤回等）在此扩展点落地。

### 4.9 / 4.10 头像尺寸

- 评论头像 32→**24**（原版 d776648 的 SeedAvatar 占位 24；晨 15 改裸 emoji 时误扩到
  32）。天卡头像 46→**56**（「卡片的头像再大点」）。随 §2.7 本地化一并落地。

### 4.11 微信式键盘收起（点空白收起、不过敏）

- **设计**：两处包裹——HomeShell body 与 ComposePage Scaffold 外层
  `GestureDetector(onTap: () => FocusScope.of(context).unfocus())`。手势竞技场语义：
  子级交互控件（按钮/输入框/chip）的识别器胜出 → 点它们**不**收键盘（不过敏）；空白
  区域（卡片正文、留白、滚动区静止点按）父级胜出 → 收起。滚动/拖拽不触发 tap → 不收。
- **边界**：不拦双击/长按（未注册相应回调，互不影响）；弹窗走自身 barrier 关闭语义。

### 4.12 未落盘输入草稿缓存

- **设计**：会话层新增草稿 API（KV 承载，UI 不直接碰 LocalStore）：
  - `saveDraft(key, json)` / `loadDraft(key)` / `clearDraft(key)`，写防抖 300ms
    （`draft.<key>` KV 键）。
  - 三个使用点：**compose 新建**（`new`：正文+心情+标签，打开时恢复，发布本地落库成功
    即清）、**compose 编辑**（`edit.<localId>`：预填=草稿优先于条目原文，updateEntry
    成功即清）、**评论**（`cmt.<localId>`：CommentsView 打开时恢复，addComment 成功
    即清）。
  - 「落盘」定义：本地加密落库即算（离线队列保证最终推云）——草稿清空后数据已在
    sqlite，崩溃/杀进程不丢。
- **边界**：媒体不入草稿（§2.8）；草稿与正文标记（`*`）无关（草稿不进载荷）；注销随
  库清空（KV 属 entries 同库）。

### 4.13 卡片头像慢 → 本地池评估与随机调用

- 见 §2.7（评估数字 + 决策：本地 20 动物脸池、种子 `$salt|$dateKey`、NetAvatar 链路
  退役）。

### 4.14 测试映射（晨 17 批次）

| 设计点 | 测试 |
|---|---|
| 4.1 双写推/拉/补缺/防复活 | config_sync_test（新）：FakeApi 补 config 三端点桩；增改推、拉取补缺、同名本地优先、删除名单 |
| 4.2 组内排序 | groupByDay 组内 time desc 单测（乱序输入 → 确定性输出） |
| 4.4 刷新收评论 | feed widget 测试：展开评论 → syncNow 成功 → 收起；失败路径不收 |
| 4.6 发送收键盘 | comments widget 测试：发送后 FocusScope 无焦点 |
| 4.8 长按评论不误触 | comments widget 测试：长按评论不进编辑路由 |
| 4.11 点空白收键盘 | shell/compose widget 测试：空白 tap 收焦点、按钮 tap 不收 |
| 4.12 草稿 | draft roundtrip：保存/恢复/防抖/清除；compose 恢复 widget 测试 |
| §2 本地先行 | offline_sync_test 更新（§2.9 映射） |
| §2.7 头像池 | net_avatar_test 删除 → 动物脸种子稳定性测试 |

### 4.15 本批次变更记录

| 日期 | 变更 | 提交 |
|---|---|---|
| 2026-11-16 晨 17 | 13 项设计定稿（③ 仅设计提请拍板） | （本提交） |
