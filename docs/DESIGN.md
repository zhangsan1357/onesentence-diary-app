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

## 2. 离线同步体系（2026-11-16 设计，晨 14/15 落地）

### 2.1 目标与语义

1. **云端不可达时增删改全部本地保存**，体验与在线一致（toast 明示「已本地保存」）。
2. **冲正只由手动刷新触发**（解锁后同步 / 下拉刷新 / 横幅重试——用户拍板**不加定时
   自动重试**）。
3. **队列的是条目最终态，不是操作日志**：同一离线窗口内对同一条目的多次修改收敛为一
   行的最终内容（编辑覆盖编辑），冲正=把最终态按序推云（last-write-wins）。
4. 网络层失败（DioException）= 离线入队；业务错误（ApiException 4xx/5xx）= 真错误上
   抛（横幅），**绝不入队**——队列只兜「暂时不可达」，不吞业务失败。

### 2.2 状态模型（drift v3，schemaVersion=3）

| 存储 | 字段/列 | 语义 |
|---|---|---|
| `Entries.syncState` | 0/1/2/3 | 0=已同步；1=待新建；2=待替换；3=待删除。非 0 行是本地最终态，**拉取同步必须跳过** |
| `Entries.pendingMeta` | JSON `{"t":true,"c":[3,4]}` | 待同步标记：t=正文/心情/标签有离线改动；c=离线新增评论下标（评论 append-only → 下标稳定）。坏 JSON 按无标记处理；推云/冲正成功即清空（''） |
| `PendingMedia` 表 | localId/kind/sec/**bytes**/cekWrappedB64 | 离线暂存媒体：**端上加密后才落盘**（bytes = nonce12‖AES-GCM 密文，P1-3 同款约束）；冲正时上传并注入引用 |

迁移：v2（syncState 列 + PendingMedia 表）、v3（pendingMeta 列），见 `database.dart
MigrationStrategy`。踩坑记录：drift 列名不能用 `blob`（与 Table.blob 构建器冲突）→
`bytes`。

### 2.3 写路径矩阵（会话层四个公开操作 × 网络状态）

| 操作 | 在线 | 离线（DioException） |
|---|---|---|
| publish | 传媒体→加密→create→本地 syncState=0 | 媒体端上加密暂存（载荷**不含**其引用）→整条加密→本地 syncState=1 + meta{t:true}→toast「云端不可达 · 已本地保存」 |
| updateEntry | 加密→replace→本地 syncState=0（原 dirty 则清 meta） | 新媒体同 publish 离线；serverId!=null → syncState=2 + meta 合并 t；serverId=null（离线新建被编辑）→ 保持 syncState=1 + meta 合并 |
| addComment | 整条重加密 replace（契约：编辑=整条替换）→成功清原 dirty 的态与标记 | meta 合并 c+=新增下标（=原评论数），syncState 同 updateEntry 规则 |
| deleteEntry | API delete→本地 deleted=true | serverId=null → **本地硬删不入队**（无服务端可删）+计数回落；serverId!=null → syncState=3 + 本地 deleted=true，暂存媒体一并清 |

要点：
- `serverId == null` 的条目只可能来自离线新建（在线发布必先拿到 serverId 才落库）。
- 待同步条目的暂存媒体在**再次编辑时重置**（deletePendingMediaFor 后重插），保证「队列
  里存的媒体 = 载荷里尚未注入引用的媒体」，冲正不重传不遗漏。

### 2.4 冲正算法 `_flushDirty`

1. 取 `syncState != 0` 的行，按 `updatedAtMs` **从旧到新**排序。
2. 每行：有暂存媒体（且非待删除）→ 逐个上传 → 解密载荷注入 MediaRef → 整条重加密
   （明文只在内存）；无媒体 → 直接用库内 cipherJson。
3. 按 syncState 分派：1→create（回填 serverId）；2→replace；3→delete（**404 视为已删
   成功**）。成功即 `syncState=0` + `pendingMeta=''` + 清该条暂存媒体。
4. **中途 DioException → 中断保留队列**（已推成的已清、未推的下次续传）；ApiException
   上抛给 syncNow 的横幅路径。
5. `finally` 调 `_refreshMarks()`（中断也刷新——未冲正的标记保留在 UI 上）。

### 2.5 同步编排 `syncNow`

```
syncNow = _flushDirty()（先冲正） → _syncOnce()（全量拉取，纪元游标） → 清 syncError
```

- **拉取保护**：`_syncOnce` 对本地 `syncState != 0` 的行直接 continue——云端旧密文不得
  覆盖本地未上云的新密文。
- **推云成功即收敛**：`_replacePayload` 在线成功路径无条件 `syncState=0`（该次载荷包含
  全部离线改动），并清 dirty 行的 meta——修复「干净条目在线推替换仍留 dirty」的边角。

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

### 2.7 头像链路与方案 D（晨 15）

- 天卡头像消费后端 EntryVO.avatar（事实源在后端）；评论头像本地 `AnimalAvatar`（20 动
  物脸表，裸 emoji 无底色——晨 15 用户拍板退回原版）。
- **实测定位**：cravatar CDN 新 hash 首字节 4.5~6.1s（服务端生成），同 hash 二次
  0.16s——慢在「每次刷新 URL 换新 → 每张打 CDN 冷缓存」，不在网络。
- **方案 D（用户拍板）**：feed 构建时对未取过的天卡头像 `precacheImage` 并行预热
  （`dayAvatarUrls` 收集去重；**onError 必传**——precacheImage 不传 onError 会走
  FlutterError.reportError，widget 测试环境判失败）+ NetAvatar 占位垫底 + 250ms 淡入。
  感知层面：卡片与头像同帧出现、无灰圆突跳。
- **未拆的墙**：CDN 冷缓存 ~4.6s 的服务端时间，方案 D 治感知不治根因。根治 =
  **A/B 方案（会话 A 侧）**：A=固定 hash 池随机轮换（URL 稳定 → 边缘命中）；
  B=后端自产图池（毫秒级，但蜂窝场景后端不可达）。待 `EntryVO.avatar` 规则定稿一并拍。

### 2.8 已知取舍与边界

| 边界 | 现行为 | 理由 |
|---|---|---|
| 离线发带图/录音 | 媒体暂存但不入卡位（冲正后才显示） | 引用注入只能发生在上传拿到 id 之后；诚实呈现「未上云」状态 |
| 双端并发冲突 | 冲正按本地顺序 last-write-wins；拉取不覆盖 dirty | 个人日记量级，不做逐字段合并 |
| dart:io 无磁盘 HTTP 缓存 | ImageCache 仅会话内有效，重启后重拉 | 引入 cached_network_image 属方案 A/B 后再评估 |
| 离线新建+离线删除 | 本地直接清除，不上队 | 无服务端可删，留队只会推 404 |
| 断网窗口内先建后删 | 硬删，云端从未见过该条 | 同上 |

### 2.9 测试映射（离线体系）

| 设计点 | 测试 |
|---|---|
| 入队（发布/编辑/评论/删除 × 断网） | offline_sync_test 前 5 项（FakeApi.online 开关；DioException=断网信号） |
| 冲正（含幂等、中断续传、媒体注入） | offline_sync_test 冲正/续传/带图 3 项 |
| pendingMeta 编解码与容错 | offline_sync_test 编解码项 |
| 标记流转（入队标→冲正清，按部分精确） | offline_sync_test 标记 3 项 |
| 标记渲染（正文/评论精确标注） | pending_mark_test 2 项 |
| 预取清单/s 规范化/占位 | net_avatar_test 3 项 |

### 2.10 本节变更记录

| 日期 | 变更 | 提交 |
|---|---|---|
| 2026-11-16 晨 14 | 离线队列 v2：syncState/PendingMedia/冲正/拉取保护（用户拍板无定时重试） | b1d03a5 |
| 2026-11-16 晨 15 | 库 v3：pendingMeta 标记体系 + 方案 D 头像预取/淡入 | 4bb7525 |
| 2026-11-16 | 本设计书建立，确立「设计先行」流程 | （本提交） |

## 3. 设计先行流程（对本文件自身的约束）

1. **改设计**：先在本文件（或对应设计文档）写清楚「改什么、为什么、边界」并提交。
2. **改代码**：按文档执行；实现与文档出现偏差时，以先提交的文档为准修正代码，或反过
   来补文档（允许「实现中发现设计错了」→ 撤销/追加设计提交）。
3. **验证**：测试映射表随设计一并更新；`flutter analyze` 零告警 + 全量测试绿是合入
   门槛。
4. **记录**：PROGRESS.md 只记里程碑与踩坑（运行日志性质），设计语义一律归本文件。
