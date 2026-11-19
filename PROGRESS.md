# PROGRESS.md — 一句话日记 前端会话（会话 B）

> 工作目录 `E:\env\java\workspace\onesentence-diary-app`。手册套件（00~04 + mockup v2）为只读真源；本文件只记进度与约定，指回手册，不复制契约。
> 更新：2026-11-14（晚：后端身份模型 v4 演进全面适配——恢复词+注册名+动态口令，见下节）

## 里程碑状态（对照 03 §7 / 00 §5）

| 里程碑 | 状态 | 证据 |
|---|---|---|
| M2-a 工程 + golden 常绿 | ✅ 完成 | `flutter test` 81 项全绿（含 golden 向量；live 14 项后端在跑时执行）；`flutter analyze` 零问题 |
| M2-b UI 全页面对照 mockup v2 | ✅ 完成 | Chrome 实测截图逐页对照（见下「视觉对照」）；像素采样自测通过 |
| M3 客户端接后端 | ✅ 完成（2026-11-13；2026-11-14 随后端 v4 重验） | `flutter test test/live/` **14/14 全绿**：原 11 项回归 + 新增 M3-12 动态口令（错口令→401「动态口令」壳）、M3-13 多设备共享（同注册名+同密钥+新设备号→数据互通，②的服务端语义验收）、M3-14 冒名拒绝（同注册名异密钥→404）。M3-1~9 全程隐式回归 X-Diary-Pass 口令头（拦截器计算，公式对活后端 curl 实测） |
| M4-a GitHub Actions 出 ipa | 🔧 本地就绪，待 push | git 仓库已初始化（main，5719d35）；`ios.yml` 合并旧工程 dvhdjdjdnddmaker/test 实证配置（macos-latest + Xcode 26.6.0 选择带回落）；补齐 `ios/Podfile`（原生插件 pod install 必需，旧工程缺失项）；待用户在 GitHub 建仓库并 push（需用户登录授权） |
| M4-b Sideloadly 真机 | ⏳ 等待 M4-a | 依赖 ipa + 用户插线（USB 驱动缺失，04 §3.2） |
| M5 真机回归 | ⏳ | 依赖 M4-b |

## 2026-11-14（晚）后端身份模型 v4 适配（恢复词 + 注册名 + 动态口令）

**背景**：后端（会话 A）身份模型演进为 v4——身份 = (注册名 userId, 主密钥 userKey) 二元组，每个业务请求附 5 分钟窗动态口令。手册 02 未同步（契约缺口见下）。客户端五段产品文案（①首次启动生成身份 ②新设备登录 ③401 口令过期 ④多设备共享说明 ⑤关于动态口令）全部落地。

### 后端实况（curl 逐项实测，重启后确认）

- `POST /device/register`：`{userId=注册名(必填≤64), deviceNo(必填≤64), name=设备名(可选), userKey=公钥hex(必填 ^[0-9a-fA-F]{64}$)}` → `{token, userId, deviceId}`；同 userId+同 userKey+新 deviceNo=新设备共享数据（deviceId 递增）；同 userId 异 userKey → 404「参数检验失败」（冒名拒绝）
- **动态口令**（后端调试台 v4 注释 + curl 实测钉死）：`X-Diary-Pass = SHA-256(userKey小写 + ':' + 窗号) 前 8 位 hex`，窗号 = epoch秒/300（5 分钟窗）；注册本身不带；错口令 → 401「动态口令无效或已过期（请检查系统时间是否准确、密钥是否一致）」
- 黄金向量（Node crypto ↔ Dart pointycastle 互证 + 活后端实测）：key=2bdb0e19…bea4d、window=5982143 → **pass=23b15233**（test/core/session/recovery_words_test.dart 钉死）

### 客户端改造

1. **恢复词核心**（`lib/core/session/recovery_words.dart` + `bip39_zh.dart`）：BIP39 中文简体标准词表（2048 词，@scure/bip39@1.5.4 审计版经 npmmirror 拉取，`tool/gen_wordlist.js` 生成）；128 位熵+4 位校验和→12 词，**抄写错误可检出**；派生 seed=SHA-256(规范短语)；「或其派生密钥」= 64 hex 直接作 seed 导入（往返一致）。黄金向量：熵全 0 → 「的×11 在」→ seed 7571379a…cd1e2。
2. **身份层**（`crypto_session.dart`）：`sessionFromIdentity(text)`——12 词（过 BIP39 校验）或 64hex → 确定性 X25519；**userKey=publicKeyHex**（服务端视为不透明 64hex，兼容调试台）；**deviceNo 每设备随机 UUID v4（不复用旧设备号）**；`KeystoreData.userId`=注册名随 keystore 落 KV（`ks.userId`）。移除旧 64-hex 随机秘钥模型（`newIdentitySecret`/`setupIdentitySession`/deviceNo 派生），`plainFromSession`/`rekeyKeystore` 携带 userId。
3. **API 层**（`api_client.dart`）：register 新字段（userId/deviceNo/name/userKey）；`otpKey` 字段 + 拦截器对全部业务请求实时附 `X-Diary-Pass`（kdf.diaryPass）；**动态口令 401 透明重试一次**（窗口边界竞态，报错含「动态口令」判定；无需重新注册——③语义）。
4. **会话层**（`app_session.dart`）：`createIdentity(words, userId)`（①）/`loginIdentity(userId, text)`（②：校验→重建→清本地→注册+全量同步，服务端拒绝内联上抛）/`setName`（存量 keystore 一次性补设注册名，deviceNo 保留）/`retrySync`/`dismissSyncError`；`needsOnboarding`/`needsName`/`userId`/`syncError` 状态；401 分流（动态口令类→横幅，token 失效→重注册）；后台路径状态回写 `ref.mounted` 守卫（`_set`）。移除 init 的自动开通分支（无 keystore → ①页）。
5. **UI**：`OnboardingPage`（create=①：12 词 3×4 网格+索引+复制全部+警示句+注册名 gate；login=②：文案逐字+内联校验错误；nameOnly=补设注册名）——main.dart 路由门（needsOnboarding / needsName&&unlocked）；feed 401 横幅（③：口令过期专用文案+重试/忽略，其他同步错误显示原始消息）；我的页：**恢复词**（查看注册名/12 词/派生密钥+复制）、**新设备登录**（替换原导入身份）、**多设备共享**（④⑤逐字说明弹窗）。
6. **测试 64 项全绿**：recovery_words 7（含双语言黄金向量+窗口边界）、identity 6（短语/hex 往返、deviceNo 随机 v4、非法输入）、identity_flow 6（create/login/setName 全流程，MemoryLocalStore 注入）、ui_smoke +3（onboarding 两模式、401 横幅）、live 14（上表）。
7. **浏览器真实栈验证（Chrome 8123→9060，全通过）**：清空 localStorage → ①页渲染（12 词/警示/注册名 gate 禁用态）→ 键入注册名按钮变蓝 → 创建身份 → 主界面+toast「身份已创建」；**localStorage 硬证据**：ks.userId=浏览器验证一号、ks.identity=躺 级 桑 恒 状 崇 弟 升 施 收 忆 妥、api.token（deviceId=14）、sync.cursor 落盘；发布真实密文（16:42 #周六 卡片+加密 toast）；刷新→免口令直进（keystore 路径）；再次清空→②登录页文案+**空恢复词内联校验**正常。遗留：②完整登录录词被 IAB 隐藏标签页（document.visibilityState=hidden，Flutter 停帧/语义树不稳）卡在自动化环节——**应用逻辑本身**由 identity_flow_test（loginIdentity 同词重建同公钥）+ live M3-13（服务端共享语义）覆盖；用户手动操作不受影响。
8. 环境注记：后端曾出现 register 全量 500 / holidays 500（迁移中途），重启后恢复；重启后 DB 清空（deviceId 从 1 重计）——旧服务端数据不再存在。

## 2026-11-14 用户反馈轮次（四项改动 + 浏览器真实栈验证）

1. **web 点击「标签管理」整屏卡死（根因修复）**：`showTagConfigDialog` 对 `AppDefaults.defaultTags`（const 列表）直接 `.sort()`，web DDC 上 const 列表是不可变 JS 数组 → `checkMutable` 异常；异常发生在 `showDialog` builder 内 → 弹窗未渲染但模态 barrier 已压屏吃掉所有点击。修复：先 `toList()` 拷贝再排序（[dialogs.dart](lib/features/me/dialogs.dart)）；全工程排查其余 `.sort` 点（holiday/calendar/diary_entry 均已先拷贝，安全）。新增回归测试。
2. **存储层抽象（浏览器真实栈的前提）**：`LocalStore` 接口三实现——原生 `DriftLocalStore`(sqlite 落盘)、web `WebLocalStore`(localStorage KV 持久 + 内存条目缓存，条目真实数据在服务端密文，刷新后解锁+sync 重建索引)、`MemoryLocalStore`(打库失败兜底)。web 端会话走真实栈（demo 仅剩测试环境 `FLUTTER_TEST`）。
3. **服务端地址 = 客户端配置（不区分构建环境）**：「我的 → 服务端地址」行 + 弹窗（[dialogs.dart](lib/features/me/dialogs.dart)），存 KV `api.base`，`ApiClient.setBase()` 运行时切换 baseUrl，**所有接口调用拼接此地址**；切换后旧 token 作废自动重注册。删除 `--dart-define=API_BASE/DEMO` 环境区分（运行配置收敛为 `-d chrome`）。
4. **日记长按编辑**：feed 条目长按 → 发布页编辑模式（标题「编辑」、按钮「保存」，预填正文/心情/标签；已附媒体保留展示，可追加新媒体）→ `session.updateEntry` 整条重新加密 `replaceEntry`（契约：编辑=整条替换）。新增 widget 测试覆盖长按→预填→保存→toast。
5. **锁定保护开关（默认关闭，调试友好）**：「我的 → 安全组 → 锁定保护」开关（[me_page.dart](lib/features/me/me_page.dart) + `showSetPasscodeDialog`）。关闭（默认）：免口令直进——私钥明文本机存（`crypto_session.dart` 明文模式：wrappedPrivB64 复用、salt/nonce 留空，无 Argon2id 启动瞬时），端到端加密对服务端仍成立；自动开通/自动解锁/锁屏遮罩/生命周期锁/时光页锁按钮全部随开关关闭。开启：设口令（仅重包裹私钥，数据零重加密）→ 口令门恢复。存量口令 keystore 在开关关闭后**需最后一次口令解锁迁移为明文**（unlock 内自动转换）。lifecycle 锁加 `lockEnabled` 守卫（[main.dart](lib/main.dart)）。
6. **身份秘钥模型（2026-11-14 用户拍板：不再按设备区分身份）**：`newIdentitySecret()`（64 hex 随机，用户保管）→ `sessionFromIdentity()`：seed=SHA-256(秘钥) → X25519 确定性密钥对，**deviceNo 同源派生**（UUID v4 格式，域分离）→ 服务端重注册幂等 → **同一数据空间**。同一秘钥在任意设备/浏览器导入即恢复全部日记。「我的」新增 **身份秘钥**（查看/复制）与 **导入身份秘钥**（锁定开启时附口令重包裹；清空本地索引+游标 → 重注册 + 全量同步；旧身份密文不再可读的警示）。锁定开启的首次开通走 `setupIdentitySession`（身份秘钥 + 口令包裹）；「恢复码」概念并入身份秘钥。新增 4 项确定性单测（test/core/session/identity_test.dart）。
7. **同步修复 + 下拉刷新**：`_syncOnce` **本地缓存为空 → 从纪元全量拉取重建**（修复 web 刷新后内存条目清空 + 旧游标 → 永远查不到数据的缺陷；native 不受影响）；时光页 `RefreshIndicator` 下拉刷新（onRefresh=syncNow），并放开鼠标拖拽（ScrollConfiguration dragDevices，浏览器可用）。浏览器实测：刷新后数据自动恢复 ✓、下拉同步 ✓。
8. **测试 44 项全绿** + web release 编译通过。

### 浏览器真实栈端到端验证（Chrome，127.0.0.1:8123 → 9060）

- 后端 CORS 已具备（OPTIONS 预检 200，Allow-Origin 回显 Origin——会话 A 已配置）
- 设口令 → Argon2id 派生 → keystore 落 localStorage → 注册设备 #9 → sync 空 → 解锁 ✓
- 发布真密文：14 日卡片高亮、00:23 等宽前缀、#周六 伪标签 ✓；`sync.cursor` 推进到发布时刻 ✓
- 浏览器刷新 → 锁屏恢复「已锁定」态（keystore 持久化）✓ → 口令解锁成功（「欢迎回来 👋」）✓
- **1 分钟自动上锁真实触发**（默认 autoLockMin=1）✓
- 已知现象：**dart2js 端 Argon2id 派生需 10~30 秒**（64MB×3 轮在 JS 引擎慢）；真机 iOS 为 AOT 原生毫秒级，无此问题。浏览器调试需耐心等「处理中…」。

## 2026-11-14（夜）用户反馈第二轮：凭证展示收紧 + toast 常驻修复 + 标签点选

1. **①引导页支持自定义 12 词 + 同屏显示派生密钥**（[onboarding_page.dart](lib/features/onboarding/onboarding_page.dart)）：新增「已有恢复词？手动输入 12 词」切换——自动生成词网格 ⇄ 手动输入框（空格/换行分隔，实时校验，提交传规范化短语）；**派生密钥块**（=SHA-256(规范短语) 64hex，与恢复词等价）自动生成恒显示、手动输入实时校验通过后显示，附「复制派生密钥」；警示文案补「创建完成后本应用不再显示恢复词与派生密钥，请务必现在抄写/保存」。黄金向量联动：输入「的×11 在」→ 密钥=7571…d1e2（widget 测试钉死）。②登录页本就支持密钥/逐词两种输入（canonicalPhrase 任意空白分隔），无需改动。
2. **保存后任何页面不再显示身份凭证**（用户拍板）：「我的 → 恢复词」行移除（[me_page.dart](lib/features/me/me_page.dart)）；`showIdentityDialog`、`AppSession.identitySecret`、KV 重复写 `ks.identity`（keystore.recoveryCode 已含同一文本）一并删除。凭证只在引导页出现一次，登录弹窗仍为纯输入（不回显）。
3. **修「身份已登录 · 同步中」toast 常驻**（[common.dart](lib/widgets/common.dart) ToastHost）：根因 = loginIdentity/createIdentity/setName 在同一次状态更新里既设 toast 又把路由门切回主界面 → ToastHost **以非空 message 挂载**，而自动关闭定时器只挂在 didUpdateWidget（挂载不触发）→ 永不消失。修复：initState 时有消息即调度 + Timer 字段管理（新消息取消旧定时器，防上一条的定时提前关掉新 toast）；挂载无消息不调度。3 项 ToastHost widget 测试（挂载即关/切换重置/无消息不调度）。
4. **发布页标签点选（免输入——iOS 中文键盘回车确认链路不稳，点选最可靠）**（[compose_page.dart](lib/features/compose/compose_page.dart)）：节标签「标签（回车添加）」→「标签」；新增可选 chips = 默认模板（吐槽/趣事/流水账）∪ **云端同步条目出现过的标签**（去重、点按即选/再点取消、≤6 约束复用）；文本输入保留用于新标签，提示改「新标签（可选）」，全页面无「回车」字样。

### 浏览器实测（IAB 127.0.0.1:8123，后端 9060 未启动——会话 A 侧停止）

- 引导页：12 词网格 + **派生密钥 fca66d07…d09 同屏显示** + 复制派生密钥 ✓；手动输入模式与「恢复词有效后自动生成」占位 ✓（向量联动由 widget 测试覆盖）
- 创建身份（浏览器验证三号）→ toast「身份已创建 · 端到端加密已开启」**显示 → ~1.9s 自动消失**（修复前常驻）✓；ks.userId 落盘 ✓；同步失败横幅（后端未启动，预期行为）
- 我的页：**恢复词行已消失**，新设备登录/多设备共享保留 ✓
- 发布页：标签 chips 点选（#趣事 选中态 + tagBox 出现可删 chip）✓、无「回车添加」✓、提示「新标签（可选）」✓
- **待补**（后端恢复后）：注册名 123 + 秘钥 26670b6b…6720 登录实测（登录 toast 自动消失 + 云端标签 chips + 同步解密）；live 14 项重跑

## 2026-11-14（夜 2）用户反馈第三轮：宫格输入 + 去重入口 + 光晕几何修正 + 注销账号

1. **①手动输入改 12 宫格直接输入**（[onboarding_page.dart](lib/features/onboarding/onboarding_page.dart)）：替换上一轮的多行文本框——与自动生成**共用同一 12 宫格布局**，序号 1~12 即位置（顺序天然可见），格内直接输入；iOS 键盘「下一项」逐格跳转（textInputAction.next）；整段恢复词粘贴到任意一格也可（空白归一）；切回生成模式输入内容保留；派生密钥随 12 格实时校验显示。浏览器实测：逐格输入黄金向量「的×11 在」→ 密钥实时变 7571…d1e2 ✓
2. **时光页空卡去掉「写一条」**（[feed_page.dart](lib/features/feed/feed_page.dart)）：输入入口与底部中央发布键重复；FeedPage.onCompose 参数随之孤儿化删除。
3. **卡片光晕"没有颜色"根因修正（对照原版 test.html 逐行核实）**（[common.dart](lib/widgets/common.dart)）：原版 `radial-gradient(circle at 锚点, 色, transparent 120%)` 的 120% 是 **farthest-corner 基准**（半径超过对角线，整卡被淡色覆盖——原版「修复2」注释原文）；Flutter 版半径却只有 1.2×短边，光晕在卡内提前衰减 → 几乎无色。修正：LayoutBuilder 按 `1.2×对角线/短边` 换算 radius。像素自测：浅色角部 Δ5→**7**、中心 Δ1→**8**（近白 ≤12 达标且色可感）；深色按原版 `calc(0.12×var(--post-glow-opacity))` 保持 ×0.15（原版深色本就近乎无色；`light-dark(1,.15)` 失效教训只发生在 mockup 文件，test.html 用 calc(var) 是生效的）。**此前把深色系数改成 1 的尝试被推翻回滚**。
4. **注销账号**（[me_page.dart](lib/features/me/me_page.dart) + [dialogs.dart](lib/features/me/dialogs.dart) + app_session）：数据组新增红色「注销账号」行 → 二次确认弹窗（强提示恢复词只显示过一次）→ `AppSession.logout()`：清 keystore 七键 + api.token/deviceId + sync.cursor + 本地索引，状态回生成身份引导；服务端密文保留（契约无服务端删除端点——如需彻底删除提请会话 A 增补）。浏览器实测：注销 → KV 全空 → 回引导页 → 重新登录原身份 ✓

### 浏览器实测（IAB 127.0.0.1:8123 ↔ 9060，注册名 123 + 派生密钥 26670b…6720）

- 引导页登录 → **toast「身份已登录 · 同步中」显示 → ~1.9s 自动消失**（前一轮修复在 123 真实身份上复验 ✓）
- 同步解密：14 日卡片两条（16:50「123」、16:57「626」#1231 #131 😊 评论 1），卡片右上可见淡蓝光晕（g1）
- 发布页可选标签 = 默认模板 + **云端条目标签 #1231 #131**（#周六 为日期伪标签不入载荷，不出现——逻辑正确）✓
- 环境备注：IAB 坐标点击对中央发布键（GestureDetector）始终不触发、tab/InkWell 均正常——自动化怪癖，真机/真浏览器不受影响；发布页改经语义节点点击验证

## 2026-11-14（夜 3）用户反馈第四轮：暗色光晕 + 宫格优先 + 回忆真实数据 + 标签/心情管理 + 日历双休标色

1. **暗色模式光晕放开**（[tokens.dart](lib/features/theme/tokens.dart) + [common.dart](lib/widgets/common.dart)）：用户要求「暗色模式也需要渐变一下」——原版 body.dark ×0.15 在深底上近不可见（光晕色距深底近，同系数实测 ΔRGB 仅 2~4）。改为 Tokens 直接给出常态/悬停透明度：浅色 0.12/0.30（原版不变），深色 **0.40/0.55**。像素实测：深色角部 Δ**14**、中心 Δ**7**（可感知不过浓）；浅色不变 Δ7/8。这是对原版深色表现的**用户明确覆盖**，已在代码注释与测试名中记录出处。
2. **①引导页改「12 宫格优先」**（[onboarding_page.dart](lib/features/onboarding/onboarding_page.dart)）：按用户要求默认直接显示 12 宫格输入，**下方新增「🎲 随机生成 12 词」按钮**——点击随机生成并填入各格（生成后仍可逐格修改），旁边的「复制全部 12 词」在 12 词有效后可用；旧的「自动生成/手动切换」双模式与只读词片（_wordChip、_phrase、_customWords）删除。派生密钥仍随宫格实时显示。widget 测试黄金向量复验：随机生成 → 密钥出现 → 逐格输入「的×11 在」→ 7571…d1e2 → 提交回调收到逐格拼接短语。
3. **回忆「随机翻一条」改用真实数据**（[memory_page.dart](lib/features/memory/memory_page.dart)）：此前**无条件读演示池**（mockup POOL），真实登录用户会翻到不属于自己账号的随机文案（用户报「感觉像是真随机生成的」）。修正：非演示模式从用户未删除条目取池（无心情条目用 📝 绿圈），空池显示「还没有可以翻看的日记」防 `%0` 崩溃；演示模式保留 POOL 视觉对照。浏览器实测（123 登录态）：显示用户真实条目「123」✓
4. **标签管理：增删改查 + 调色板**（[dialogs.dart](lib/features/me/dialogs.dart) + [app_defaults.dart](lib/core/config/app_defaults.dart) + app_session）：原为只读弹层。现：标签库（初始=默认三项「吐槽/趣事/流水账」，可增删）∪ 日记实际标签；新增标签输入行（1~16 字校验）；**行点击进底部弹层 → 8 色调色板**（选色覆盖 / 「自动」恢复稳定哈希）+ 预设可删除（不影响已写日记）。颜色实现：`AppDefaults.tagColorOverrides`（标签名→8色名）+ `tagColor()` 查覆盖表后回落哈希——**回答用户「标签颜色怎么确定」：原逻辑是标签名 32 位溢出哈希 %8 映射 iOS 色板 8 色（同名永远同色、不存储颜色字段），现在允许调色板覆盖**。撰写页建议 chips 同步接入标签库。KV 持久化 `cfg.tagColor`/`cfg.tagPreset`（设备本地，'[]' 显式空库 ≠ 键缺失回默认）。
5. **心情管理：增删改查 + 调色板**：原为只读展示。现：默认 6 心情可改显示（emoji 28 选 + 名称 1~8 字 + 8 色板，key 不变→历史条目照常渲染）；**新增自定义心情**（key=`m<时间戳>`）与删除（默认不可删）。`moodOf()` 查自定义→默认+覆盖→末位兜底；compose 心情选择器改用 `allMoods`。KV：`cfg.moodOver`/`cfg.moodCustom`。
6. **日历双休标红**（[calendar_page.dart](lib/features/calendar/calendar_page.dart)）：周六/周日数字红色（法定休日同样红、调休上班「班」橙优先于周末红——班日是工作日），表头「日/六」红色呼应，底部说明改「周末与法定节假日红色 · 班 = 调休上班 · 圆点为心情」。浏览器实测 2026-11 月：1/7/8/14/15/21/22/28/29 全红、14 今日蓝圈、补位灰显 ✓
7. **回答用户「本地怎么存储数据」**（[database.dart](lib/core/db/database.dart)）：原生（iOS）= **drift/SQLite 落盘**，两张表——`Entries`（localId uuid / serverId / entryDate / **payloadJson 明文索引**（搜索统计端上做）/ cipherJson 密文 Envelope / updatedAtMs / deleted 软删）+ `Kv`（keystore 七键 ks.*、api.token/deviceId、sync.cursor、ui.* 设置、cfg.* 显示配置）；**web 预览 = localStorage KV 持久 + 内存条目缓存**（刷新靠 sync 重建）。密钥安全：私钥不出设备（锁定开=Argon2id(口令,盐) 包裹，盐不上传），服务端只见密文。

### 浏览器实测（IAB 127.0.0.1:8123，123 登录态 + 深色）

- 深色卡片光晕**清晰可见**（右上蓝色渐变铺满卡面）✓；日历双休红 ✓；回忆翻真实条目 ✓；123 两条数据完好
- IAB 环境后段再次进入点击死锁周期（坐标点击/tab 均不触发，与上轮怪癖一致）；标签/心情弹层与引导页宫格的浏览器走查改由 widget 测试全量覆盖（改色→粉色断言、默认 6 心情+新增入口、随机生成→密钥→黄金向量提交）

## 2026-11-14（夜 4）GitHub 云编译准备（M4-a 本地侧完成）

1. **找到旧工程**：`E:\env\java\workspace\test`（2026-08 的 Flutter 试验工程）→ 远程 `github.com/dvhdjdjdnddmaker/test`，`.github/workflows/ios_build.yml` 为当年实证配置（macos-latest + `ls /Applications/Xcode*` 排查 + `sudo xcode-select Xcode_26.6.0` + build ios --no-codesign + zip Runner.app）。
2. **workflow 合并**（`.github/workflows/ios.yml`）：保留本工程的 `flutter test` 门禁与 **Payload→diary.ipa 规范打包**（Sideloadly 直收），触发/Runner/Xcode 选择改用旧工程实证配置；Xcode 26.6.0 缺失时回落镜像默认版不阻塞。
3. **补齐 `ios/Podfile`**（关键缺口）：本工程含 10+ 原生插件（image_picker/audio_waveforms/flutter_local_notifications/local_auth/share_plus/path_provider/sqlite3_flutter_libs），无 Podfile 时 CI 的 pod install 无从执行、插件不链接；旧工程缺失此文件（其插件仅 http/shared_preferences）。按 flutter create 模板落位（platform 13.0 与 pbxproj 一致，含 RunnerTests target）。
4. **git 初始化**：`git init -b main` + 初始提交 `5719d35`（107 文件；build/.dart_tool/.idea/sqlite3.dll 均按 .gitignore 排除——tool/bin/sqlite3.dll 已入库供 Windows 测试用）。push 需用户在 GitHub 建仓库并登录授权（本机 8 月曾 push 过旧工程，凭据管理器大概率已存）。
5. **CI 首跑两处修正（用户推送后实测）**：①Node 20 弃用警告非报错——仍升级 `actions/checkout@v5` + `actions/upload-artifact@v6`（node24 运行时；flutter-action v2 尚无 node24 版，被强制属预期）；②`pod install` 真报错 `undefined flutter_ios_podspec_setup`——我凭记忆写的Podfile 方法名有误，3.44.8 实际是 **`flutter_ios_podfile_setup`**（本地 Flutter 安装 `templates/cocoapods/Podfile-ios` 原版模板逐字拷贝修正，`b020a1f`）。旁证：日志已跑到 pod install（pub get/SPM 插件解析都过了）；3.44 的 ios 模板不再自带 Podfile（SPM 默认），audio_waveforms 不支持 SPM 回退 pods——这正是必须手动落位 Podfile 的原因。

## 2026-11-14（夜 5）真机反馈轮：评论按钮右置 + 下拉刷新反馈 + 面容 ID 全量解锁

1. **回答「标签颜色怎么决定」**：标签名 32 位溢出哈希 %8 → 固定 8 色板（blue/green/red/orange/purple/gray/pink/cyan，01 §6 + mockup TCN，同名永远同色、颜色不入载荷）。用户看到「没有颜色」的 #周六 实为哈希落 **gray**（实测 690693%8=5=gray，约 1/8 命中率）；可在 标签管理 → 点标签 → 调色板覆盖（上轮已建）。不改默认映射（冻结向量）。
2. **评论按钮移到右侧**（[feed_page.dart](lib/features/feed/feed_page.dart)）：对照 mockup `.post-actions{justify-content:space-between}`——标签行+心情合并为一个 post-actions 行（左 Wrap），评论按钮固定右侧。
3. **下拉刷新**：RefreshIndicator 早已存在（真机可用）；用户感知「没有」是同步静默完成无反馈——补 `showToast('已同步 ✓')`（新增 AppSession.showToast）。
4. **面容 ID 全量解锁（本夜核心）**：用户确认「面容解锁后还要输密码」根因——原实现 Face ID 只是先验身份，解锁仍靠 Argon2id(口令)（私钥被口令包裹）。按用户拍板增补 **flutter_secure_storage ^11.2.0**（此前悬置的依赖决策）：新建 [bio_vault.dart](lib/core/session/bio_vault.dart)——私钥 b64 存 iOS Keychain（**AccessControlFlag.biometryCurrentSet**，生物特征集变更自动失效）+ local_auth 探测/验证；AppSession 增 `enableBioUnlock/disableBioUnlock/unlockBiometric`（ui.bio KV + AppState.bioUnlock）；LockOverlay **锁屏出现即自动弹 Face ID**，识别通过 → 钥匙串取私钥直建会话（**免口令**），钥匙串无存档/失败回退口令路径；我的页面容开关真绑定（web/桌面 available=false → 提示真机可用）；注销清除钥匙串存档。**注意**：更换口令（rekey）不影响面容解锁（存的是私钥非口令派生物）。
5. 测试：+4 项 bio 流程（假 BioVault 注入：启用入库/锁定后面容免口令解锁/bio-missing 回退信号/拒绝启用/关闭清除/注销清除）；全量 **77 项绿** + analyze 零告警 + web 构建通过。

## 2026-11-15（凌晨）下拉刷新动画 + 标签动态色 + 发布键居中凸起

1. **下拉刷新动画（仿原生）**（[feed_page.dart](lib/features/feed/feed_page.dart)）：Material RefreshIndicator 换成 **CupertinoSliverRefreshControl + 自绘头**——下拉时箭头随拉距旋转（朝下→朝上，越过触发距离 90 变蓝），松手转圈 + 「正在刷新…」，完成 ✓ + 「已同步 ✓」随头部收回淡出（另有底部 toast 兜底反馈）。物理改 `BouncingScrollPhysics(parent: AlwaysScrollable)` 强制顶部过拉（真机 iOS 天然弹性，web/桌面同步开启）。**媒体渲染（真实图片下载解密显示/录音播放）按用户拍板暂缓不动**——时光流图片仍为占位图标、录音条仍不可播。
2. **标签动态色（用户拍板，覆盖 01 §6「同名永远同色」）**（[app_defaults.dart](lib/core/config/app_defaults.dart) + [common.dart](lib/widgets/common.dart)）：哈希种子改为 **标签名+正文**——同一标签在不同条目呈现不同颜色（`tagColorSeeded`/`tagColorOf(seed:)`，TagChip 增 `seed` 参数，feed 传正文）。用户调色板覆盖仍最优先；标签管理/撰写页建议 chips 仍走纯名字哈希（避免随草稿抖动）。JS 32 位溢出语义与黄金向量不变（新增动态色确定性+异色+覆盖优先断言）。
3. **发布键居中凸起**（[home_shell.dart](lib/features/shell/home_shell.dart)）：去掉 margin-top 20（此前圆钮中心比左右 tab 图标低 10px，观感"沉底"）→ 与左右图标同一视觉线；直径 52→58、图标 23→26、阴影加重（真机反馈"偏下、希望比左右大、突出"）。
4. 测试：**79 项全绿**（新增 下拉刷新头拖拽箭头断言 + 动态色断言）+ analyze 零告警 + web 构建通过；后端被会话 A 重启致开发数据清空（身份仍可重登，属后端侧）。

## 2026-11-15（晨）关键词搜索

- **时光页搜索**（[feed_page.dart](lib/features/feed/feed_page.dart)）：标题旁新增放大镜 → 展开搜索条（自动聚焦，× 清空，再点放大镜收起还原）——**实时过滤正文/标签**（大小写不敏感子串，01 §7 明文索引端上做）；命中条目按天卡片原样呈现；无结果显示「没有找到「kw」」，搜索态隐藏「今天还没写点什么」空卡。纯本地过滤，无契约影响。
- 测试：**80 项全绿**（新增搜索流程断言：正文命中/标签命中/无结果态/清空还原）+ analyze 零告警 + web 构建通过。

## 2026-11-15（晨 2）同日间距收紧 + 编辑页删除按钮

1. **同日条目间距收紧**（[feed_page.dart](lib/features/feed/feed_page.dart)，用户反馈"页面松散"）：条目上下 padding 9→**6**、脚注（post-actions）顶部 10→**7**、天卡内容区底部 8→**6**——一天多条时明显紧凑。媒体块间距未动（用户拍板媒体暂缓）。
2. **编辑页删除按钮**（[compose_page.dart](lib/features/compose/compose_page.dart)）：长按进入编辑后，页面底部（加密脚注下）新增红色「🗑 删除这条日记」→ 二次确认弹窗（本机+服务端同步删除，不可恢复）→ `AppSession.deleteEntry`（软删+401 重试+本地索引替换）→ toast「已删除 ✓」→ 回时光流。仅编辑态显示，新建无此按钮。
3. 测试：**81 项全绿**（新增 删除流程：滚动到按钮→取消不删→确认删除→条目消失；弹窗「取消」与顶栏「取消」重名 → AlertDialog 子树限定）+ analyze 零告警 + web 构建通过。

## 2026-11-15（晨 3）同日分割线 + 跨月双休修正 + 随机头像接入

1. **同日内条目分隔线（若隐若现）**（[feed_page.dart](lib/features/feed/feed_page.dart)）：天卡内条目之间加 0.5px 分隔线 = sep 再 ×0.4（≈12% 黑，可辨但不抢眼），左缩进 38 对齐正文起点；仅同日多条之间出现。
2. **日历跨月双休变色修正**：补位（outside）格此前一律灰——现跨月周六/周日红显（透明度 .55 与本月红区分）；「班」仍橙优先（补位格无徽章数据，不受影响）。
3. **天卡头部去重 + 重排**：原「左大日数字 + 右侧『11月 + 完整日期』」日期重复两处——重排为 **头像左上 + 日大数字右上 + 『2026年11月』收在日下（含年，跨年不丢信息）**，休/班徽章移至日数字左侧。完整 dateKey 行删除（用户拍板）。
4. **随机头像接入（后端契约增量 EntryVO.avatar）**：后端响应时现生成随机 cravatar 头像 URL（不落库、每次请求不同、树洞匿名风，不破坏 E2E）。客户端：ServerEntry/DiaryEntry 增 `avatar` 字段（仅内存，重启由下次同步重填）；**每天一个头像**（方案 a，天卡头部取当天首条的 avatar；方案 b 每条一个可随时切换）；demo 数据走同款确定性 cravatar 渲染路径（[avatar.dart](lib/core/util/avatar.dart)：MD5→cravatar 镜像）。加载中/失败回落同尺寸占位人形。
5. **评论每条头像**：评论在密文载荷内（后端无法注入）→ 客户端确定性种子（who|time|text）cravatar——同一条评论稳定、各条互不相同；加载/失败回落原字母圆（离线测试环境走回落路径，原断言不受影响）。
6. 测试：**81 项全绿**（feed 头部断言改『年11月』×2）+ analyze 零告警 + web 构建通过。浏览器截图本轮 IAB 截图管线超时未取（头像失败回落路径已被离线测试实际覆盖）。

## 2026-11-15（晨 4）头像改本地确定性生成 + 评论时间标准格式

1. **头像还是灰色的根因与解法**：cravatar 远端图在 web 预览（Flutter 3.44 CanvasKit 渲染器，跨域图需 CORS 头，cravatar 不带）与真机（网络波动）两种环境都加载失败，两轮渲染成灰色占位/字母回落。**用户拍板改本地确定性生成**（[seed_avatar.dart](lib/widgets/seed_avatar.dart)）：颜色（8 色 iOS 色板，与标签色同源 `AppDefaults.stableHash`）+ 表情（20 种动物脸）由种子哈希决定——同种子稳定、跨端一致、**零网络依赖永不灰**。天卡种子=日期（每天一个，用户此前拍板）、评论种子=who|time|text（每条不同）。
2. **评论「我」字消失**：字母回落圆渲染 who 首字（『我』）即用户看到的「评论我+内容」——SeedAvatar 无文字，彻底解决；评论只显示 头像+内容+时间。
3. **评论时间标准格式 `2026-11-15 17:08`**：新评论存储改完整 `yyyy-MM-dd HH:mm`（[app_session.dart](lib/core/session/app_session.dart) addComment）；存量 HH:mm 显示时补条目日期（comments_view `_fmtTime`），旧评论也能正确显示。
4. **网络头像链路整体拆除**（本次改动产物，孤儿清理）：`util/avatar.dart`（cravatar MD5 URL）删除、`DiaryEntry.avatarUrl` 字段删除、session `_avatars` 内存表与同步挂载逻辑删除、feed `_Avatar` 网络组件与评论 `_letterAvatar` 回落删除、demo 数据 avatarUrl 参数删除；`ServerEntry.avatar` 契约字段保留解析（文档化后端增量，客户端不再用于展示）。
5. 测试：**82 项全绿**（新增「评论展开：本地头像渲染 + 存量 HH:mm 补日期→标准格式」）+ analyze 零告警 + web 构建通过。

## 2026-11-15（晨 5）头像换第三方 DiceBear + 天卡日数字变色

1. **用户否决本地预制头像**（晨 4 SeedAvatar 表情圆）→ 拍板「第三方的随机头像」。实测候选（curl 本网络）：**api.dicebear.com 200 + `access-control-allow-origin: *` ✓**（bottts 机器人，seed 确定性）、cravatar.cn 可达但无 CORS 头（web 预览两次灰掉的根因）、gravatar.com 超时、pravatar 403。→ [net_avatar.dart](lib/widgets/net_avatar.dart)：`Image.network('https://api.dicebear.com/9.x/bottts/png?seed=<enc>&size=80')`，加载中/失败回落中性人形占位（不显示文字，避免字母圆「我」）。种子沿用：天卡=日期（每天一个）、评论=who|time|text。SeedAvatar 删除；晨 4 的 `stableHash` 公开拆分回滚（失去消费者）。
2. **天卡日数字变色**（用户报「日的变色似乎又掉了」）：日历页变色逻辑核查**未丢**（周末红/休红/班橙/跨月红 .55 全在）——掉色感来自时光页天卡大日数字（此前仅高亮才变色）。→ [feed_page.dart](lib/features/feed/feed_page.dart) DayCardBody：日数字与日历呼应（班橙 / 休与双休红 / 工作日 label），高亮（日历跳转/新发布）组色仍优先。
3. **浏览器实证**（IAB 390×844）：DiceBear 头像加载成功（橙色机器人，不再灰）；天卡「15」（今日周日）红色 ✓。评论区展开点击在 IAB 不命中（Flutter canvas 命中怪癖），评论头像/时间格式由测试断言覆盖。
4. 测试：**82 项全绿**（SeedAvatar→NetAvatar 断言更名）+ analyze 零告警 + web 构建通过。

## 2026-11-15（晨 6）头像源定案 cn.cravatar.com + 日数字与卡片同色

1. **CORS 根因最终修正**：cravatar 图源（cn.cravatar.com）本身带 `access-control-allow-origin: *`，缺头的是 **cravatar.cn 入口 301 那一跳**（CORS 要求重定向链每跳过检）。浏览器 fetch 实测（预览页上下文）：cn.cravatar.com 直连 ✓ / cravatar.cn 经 301 ✗ / weavatar.com ✓ / dicebear ✓。用户拍板**直连源站一行解**：[avatar.dart](lib/core/util/avatar.dart) 恢复（MD5→hex），域名 cravatar.cn → **cn.cravatar.com**（省一次跳转，web+真机双通）；NetAvatar 改用 avatarUrl(seed)。iOS 真机本无 CORS，cravatar 一直可用（两轮灰色均为 Chrome 预览）。
2. **天卡日数字与卡片同色**（用户拍板，覆盖 mockup「常态 label 仅高亮变色」语义）：accent = `glowAnchors[(glowIndex-1) % 8].$3` 常显；DayCardBody.highlighted 参数失去消费者一并删除（GlowDayCard 高亮保留）。上一轮的周末红/班橙日数字方案被本拍板替换。
3. 浏览器实证：cravatar 头像加载成功 + 日数字「15」与该卡光晕同蓝。测试 **82 项全绿** + analyze 零告警 + web 构建通过。

## 2026-11-15（晨 7）头像事实源收归后端 + 尺寸适配

1. **用户拍板「客户端直接使用后端链接」**：条目头像 URL 事实源在后端（EntryVO.avatar），客户端只消费不拼装、不改 host（301 由网络栈自动跟随，iOS 完全正常）。实现：DiaryEntry.avatarUrl 恢复；app_session `_avatars` 缓存 **首存后不覆盖 + KV 持久化**（`avatar.<localId>`，init 从 kvAll 恢复）——后端现生成链接也能保住「每天一个头像」稳定；**增量同步头像补挂**：本地有非删除条目但缺头像缓存（存量数据同步早于后端加字段）→ 该次同步自动用纪元游标全量拉一次补挂，补齐后恢复增量；deleteEntry/logout 清理 avatar KV。
2. **尺寸适配（用户给 s= 用法后）**：NetAvatar.sized 按显示尺寸规范化 `s=` 参数（天卡 40→120、评论 24→72，3x 屏 1:1；同 hash 不同 s 是同一张图的不同分辨率，图案不变），已有 s 覆盖、没有追加；圆形裁剪+cover。评论头像与 demo 数据（密文内、后端不可见）用 [avatar.dart](lib/core/util/avatar.dart) **与后端定稿格式一字不差**的模板本地拼（种子：评论=who|time|text、demo=localId）；后端改 URL 规则时客户端同步一处常量。
3. **web 预览 CORS 实况（决定性实测，客户端不可修）**：cn.cravatar.com 的 `access-control-allow-origin` 头**随 CDN 缓存状态漂移**——早前命中缓存的 URL 浏览器 fetch ✓，新 hash/带 query 的回源响应 ✗（页面内三变体实证）；cravatar.cn 入口 301 首跳始终无 ACAO。**真机（iOS 无 CORS）不受影响，客户端已就绪**。预览侧两案待用户拍板：①Chrome CORS 解除扩展（零代码）；②tool/serve.js 加图片代理路由（前端工具链，web 分支 kIsWeb 走本地代理）。
4. 测试：**82 项全绿** + analyze 零告警。

## 2026-11-15（晨 8）头像每次刷新换新（用户拍板新鲜感）

1. **推翻晨 7「首存不覆盖」缓存**：用户真机验收前拍板「刷新之后使用新的头像，有点新鲜感」——`_avatars` 回归**纯内存、每次同步覆盖更新**（后端现生成链接、每次不同），不持久化：重启/刷新后头像区短暂占位 → 同步完成即换新。
2. **同步恒全量拉取**（纪元游标，替代增量游标）：重启后增量列表为空会拿不到任何头像，与「每次刷新换新」矛盾；全量后本地密文比对未变条目直接 continue，实际开销在传输+解密，个人日记量级可接受。`sync.cursor` 读写随之移除（logout 清理保留清残留）。
3. 真机验收路径确认：iOS 无 CORS，后端 cravatar 链接直接可用；web 预览 CORS 限制仍在（晨 7 记录，两案待拍板：Chrome 扩展 / serve.js 代理）。
4. 测试：**82 项全绿** + analyze 零告警。

## 2026-11-15（晨 9）安全加固：P0×2 + P1×2 全落地（用户拍板）

1. **P0-1 ATS 收紧**（[Info.plist](ios/Runner/Info.plist)）：删 `NSAllowsArbitraryLoads=true`（调试期任意明文）→ 改 `NSAllowsLocalNetworking=true`——公网强制 HTTPS，本地网络（后端 127.0.0.1 / 局域网 9060 联调）明文例外；将来服务端上公网 HTTPS 可整段移除。
2. **P0-2 默认安全基线 · 锁定口令引导**：`AppState.needsPass`（createIdentity/loginIdentity[未开锁]/setName 后置位，logout 复位）→ [PassSetupPage](lib/features/onboarding/pass_setup_page.dart)（路由门 `needsPass && unlocked`）：开启锁定（≥6 位口令×2 确认，setLockEnabled=Argon2id 重包裹）或「暂不设置」——跳过后果红字明示（私钥明文落盘、拿到手机可直接阅读全部日记）。
3. **P1-3 本地明文根治**：Entry 表 `payloadJson` 列**复用存密文 JSON**（免 schema 迁移），落盘零明文；`_loadLocalEntries` 解密重建内存索引（解密失败跳过渲染、密文保留）；**旧明文行自动迁移**（payloadJson 含 'text' 键判旧格式 → 重写为密文，一次性）；**同步循环不再解密**（他设备密文原样落库，读取时才解密——「无法解密 continue」分支自然消解）。`_upsertLocal` 去掉 payload 参数（4 处调用同步）。
4. **P1-4 锁定清内存**：`lock()` 清 `_avatars` + `entries`（此前明文条目驻留内存到进程结束）；解锁路径（unlock/unlockBiometric）已有 `_loadLocalEntries` 重载 ✓。
5. 测试：**85 项全绿**（新增 3 条安全回归：落盘零明文+解密重建、needsPass 引导状态机、lock 清内存+解锁重建；`debugReloadEntries` 测试钩子）。analyze 零告警。
6. 未做（评估中的 P2，待拍板）：剪贴板自动清空、token/keystore 迁 Keychain、TLS pinning、依赖 CVE 审计、导出明文提示。

## 2026-11-16（晨 10）App 名字确认 + logo 换装管线就绪

1. **名字**：桌面显示名早已生效——`Info.plist` `CFBundleDisplayName=一句话日记`；`CFBundleName=diary_app` 为内部标识不可见，不动。
2. **logo 管线**（用户拍板「提供任意图片，转成符合要求的」）：新增 [tool/make_logo.dart](tool/make_logo.dart) + dev 依赖 `image: ^4.13.1`（纯 Dart，Windows 本地可跑）。用法 `dart run tool/make_logo.dart <任意图片> [输出目录]`：EXIF 摆正 → 调色板转真彩 → 透明图白底合成+白边居中补方（contain）/ 不透明居中裁方（cover）→ 重写 appiconset 全部 15 张（沿用现有文件名，Contents.json 不动），统一收敛 RGB 无透明（iOS 硬性要求）。
3. **自测双路径通过**（合成图：600×400 不透明 → cover 裁方；400×600 透明 → contain 白底居中，bbox 上 255/下 256）：15 张全 color type 2。踩坑记录：①`Interpolation` 只有 nearest/linear/cubic；②`hasPalette` 看 `palette!=null`（RGB 调色板 numChannels 仍报 3，判真彩必须用 hasPalette）；③文件名正则 `\d+` 跨不过 `83.5` 的小数点（放宽 `[\d.]+`）。
4. 等用户提供图片 → 跑管线出全套图标 → 看图验收 → 提交 → push 出 ipa。

## 2026-11-16（晨 11）App 内换图标功能（真机生效，三样例定稿）

1. **三张样图预处理定稿**（用户拍板「①裁剪 ②③放大」；临时脚本出图后逐张看图验收）：night=暗夜少女居中裁方（750²）、patrick=派大星含完整「胖？」+脚（926²取616²）、sponge=海绵宝宝地面线压底边（1920²取1300²）。二轮返工：patrick「胖？」右上残半截→改完整收进（梗图灵魂）；sponge 底部地面线裁切位置三调。
2. **iOS 备用图标机制**（`setAlternateIconName`，iOS 10.3+ 公开 API）：Assets.xcassets 新增 AppIconNight/Patrick/Sponge 三个单尺寸 appiconset（1024×1024 RGB 无透明，Xcode 14 单尺寸格式）；[project.pbxproj](ios/Runner.xcodeproj/project.pbxproj) 三处 Runner 配置（Debug/Profile/Release）加 `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES`，不动 Info.plist。
3. **原生通道**（[AppDelegate.swift](ios/Runner/AppDelegate.swift)）：AppIconPlugin（FlutterPlugin，在模板 `didInitializeImplicitFlutterEngine` 扩展点注册，scene 生命周期安全）——`get` 当前名 / `set(name)`（空串=恢复默认 `setAlternateIconName(nil)`）；成功后 iOS 自动弹系统确认框。
4. **Flutter 侧**：[lib/core/app_icon.dart](lib/core/app_icon.dart)（choices 三元组 + supported 门控 `!kIsWeb && defaultTargetPlatform==iOS`）+「我的」页配置组新增「App 图标」行（仅 iOS 显示）+ [dialogs.dart](lib/features/me/dialogs.dart) `showAppIconDialog`（默认+3 格缩略图、当前勾选、失败红字降级；缩略图走 `assets/appicon/` 240px 预览）。web 预览自动隐藏该行。
5. 测试：**88 项全绿**（新增 3 条：弹窗选项+当前勾选、点击样例通道收到 set、默认=空串映射）。analyze 零告警。CI 首跑两个 Swift 编译错已修（commit 3ec9ed8）：FlutterPlugin 协议要求 `handle` 与类型同级可访问（去 private）、`pluginRegistry.registrar(forPlugin:)` 该版返回可选需解包。
6. **名字答疑**：桌面显示名= Info.plist `CFBundleDisplayName`（已是「一句话日记」）；`CFBundleName=diary_app` 内部标识不可见。

## 2026-11-16（晨 12）真机反馈两连修：换图标改松散 PNG 路线 + 刘海屏顶距

1. **换图标真机报 `feature is not supported`**（用户截图：弹窗四格/缩略图/构图全对，仅原生 set 失败）：根因=侧载重签包里**资产目录 + ALTERNATE_APP_ICON_NAMES 路线的 supportsAlternateIcons 不可靠**（websearch 证实：备用图标须以 PNG 文件形式在包根 + Info.plist 显式声明）。修复：①`ios/Runner/Icons/` 松散 PNG×6（@2x=120/@3x=180，从 1024 源降采样，RGB 无透明；源图归档 [tool/icons/](tool/icons/)）②[Info.plist](ios/Runner/Info.plist) 显式 `CFBundleIcons` + `CFBundleIcons~ipad` → `CFBundleAlternateIcons`（key 与传参一致，CFBundleIconFiles 基名由系统解析 @2x/@3x）③pbxproj 六处接线（fileRef/buildFile/组/Resources 阶段）④撤 ALTERNATE 构建设置 + 删三个 appiconset（资产目录路线整体退役）。set/get 通道与 Dart/测试契约不变。
2. **刘海/灵动岛顶距**：四个 tab 页大标题顶距写死 64（岛机安全区 ~62+ 被压住，web 预览 inset=0 又必须保住 64 视觉）→ [common.dart](lib/widgets/common.dart) 统一 `headerTopPad = max(64, 安全区+12)`（岛机 ~74、web 仍 64），me/feed/calendar/memory 四页接入。
3. 测试 **88 项全绿** + analyze 零告警；web 预览不受影响（inset 0 → 64 原样）。**CI 后补坑两层**（commit 22cb08e + 6cf24c0）：①`ios/.gitignore` 模板的 `Icon?` 规则恰好匹配 `Icons/` 目录名，6 张松散 PNG 没进首仓——`!Icons/` 放行并补提交；②补提交后 CI 仍缺文件——**生成脚本文件名 `@2.png/@3.png` 少了 x**，与 pbxproj 引用（及 iOS 系统解析要求的）`@2x/@3x` 差一字符——git mv 修正 + 引用/文件名一致性脚本校验（refs 6 missing 0）。教训：生成产物名与构建引用名要过一致性断言，本地不构建 iOS 时 CI 是唯一验证点。

## 2026-11-16（晨 13）卡片颜色 SWRR 洗牌 + 评论头像退回 12 生肖本地动物

1. **卡片颜色不再恒定**（用户点名 SWRR）：此前 glowIndex=列表索引取模 → 最新卡片恒同色。改 [feed_page.dart](lib/features/feed/feed_page.dart)：`swrrOrder`（平滑加权轮询，nginx 同款 current-weight 算法）+ 洗牌起点——启动/下拉刷新/横幅重试后 `_rerandomize()` 重掷 `_glowSeq`，第 i 张卡取 `_glowSeq[i%8]+1`：每 8 张覆盖全部 8 色（不饿死）、每次刷新序列不同。等权时 SWRR=平滑轮询；加权能力保留（`weights`/`rounds` 参数，算法测试覆盖）。
2. **评论头像退回本地动物图标**（用户拍板）：[animal_avatar.dart](lib/widgets/animal_avatar.dart) `AnimalAvatar`（★配置点 `animalAvatars` 12 生肖表，emoji+专属柔和底色，不好看再增删）；随机性走 `avatarSaltProvider`（刷新盐）——盐变 → 全部评论动物换新，同一刷新周期内同一条评论稳定。评论头像 24→32px（「实在太小」）、天卡头像 40→46px（NetAvatar 后端链接不变）。
3. **分割线答疑**：同日内第 2 条起才画线（`if (i>0)`），单条日子本就不画——现状已满足，未改。
4. 踩坑三连：①djb2 乘数 33≡0 (mod 3) → 其值恒为 3 的倍数，对 12 生肖取模时「前缀加盐」系统性失效（实测 18/20 撞同动物）→ 换乘数 31（Java hashCode 同款，与 12 互素）；②`dart run` import 整包撞 drift FFI 编译器 crash（绕开：独立脚本验证哈希）；③Riverpod 3 的 StateProvider 在 `flutter_riverpod/legacy.dart`。
5. 测试 **94 项全绿**（新增 6：SWRR 等权不饿死/全覆盖/加权平滑性、stableHash 确定性/生肖表 12 互异/渲染冒烟+盐变随机性）。analyze 零告警。

## 2026-11-16（晨 14）评论头像退回原版动物脸（去底色）+ 离线队列（云端不可达本地暂存）

1. **评论头像再改回原版**（用户拍板：12 生肖带底色圆「比不上原版」，评论场景不要底色）：[animal_avatar.dart](lib/widgets/animal_avatar.dart) 恢复 d776648 原版 20 动物脸表（`animalFaces` ★配置点），渲染改**裸 emoji**（无 ClipOval/底色，fontSize=size），salt 随机机制与 stableHash(31) 不变。
2. **离线队列**（用户需求：云端暂时无法访问 → 增删改先本地保存，云端恢复后一次性同步；**用户拍板：不加定时自动重试，手动刷新才触发冲正**）：
   - **库 v2**：Entries 加 `syncState`（0 已同步/1 待新建/2 待替换/3 待删除）+ 新表 `PendingMedia`（已加密媒体字节暂存，落盘零明文 P1-3 同款约束）；migration addColumn/createTable。踩坑：**列名不能用 `blob`（与 drift Table.blob 构建器同名冲突）**→ 改 `bytes`。
   - **发布/编辑/评论/删除**：网络层失败（DioException，与业务错误 ApiException 区分）→ 本地落盘 + 标记 syncState + toast「云端不可达 · 已本地保存」；媒体端上加密后暂存（`_encryptMediaLocal`），引用等冲正时注入。未上云条目（serverId=null）直接本地硬删不入队。
   - **冲正 `_flushDirty`**（syncNow 前置，手动下拉刷新/解锁/横幅重试触发）：按 updatedAtMs 从旧到新重放——上传暂存媒体 → 解密载荷注入引用 → 重加密 → create/replace/delete；删除 404 视为已删成功；网络仍不通则中断保留队列（下次刷新续传）。拉取同步跳过未同步行（防云端旧密文覆盖本地新密文）。
   - **UI**：时光页头部「N 条待同步」橙色徽标（pendingCount>0 时显示）。
3. 测试 **102 项全绿**（新增 8：头像表改版 1 + 离线队列 7——发布入队/冲正新建+幂等/评论待替换/删除待删除/离线新建再删直除/中途断网续传/媒体暂存注入）。analyze 零告警。

## 2026-11-16（晨 15）头像刷新提速方案 D（预取+淡入）+ 待同步 `*` 标记（用户拍板）

1. **头像慢的实测定位**（curl 5 连测）：cravatar CDN 新 hash 首字节 **4.5~6.1s**（服务端生成/回源），同 hash 二次 **0.16s**（边缘命中，30 倍差）；DNS/TCP/TLS ≤0.17s、图片本体 <4KB——慢不在网络，在「每次刷新 URL 换新 → 每张都打 CDN 冷缓存」。CDN 侧 `cache-control: max-age=300` 也短，客户端绕不开服务端时间。
2. **方案 D 落地**（用户从 A~F 方案中拍板先做 D）：①[feed_page.dart](lib/features/feed/feed_page.dart) 构建时对未取过的天卡头像 `precacheImage` 并行预热（`dayAvatarUrls` 收集去重，★onError 必传——precacheImage 不传 onError 会走 FlutterError.reportError，widget 测试环境判失败）②[net_avatar.dart](lib/widgets/net_avatar.dart) 占位垫底 + 图就绪 250ms 淡入（AnimatedOpacity），预取命中首帧即显无动画。感知：列表结构与头像同帧出现、无灰圆突跳；CDN 冷缓存的墙要 A/B 方案（后端池）才拆。
3. **待同步 `*` 标记**（用户提的「指针」思路 + 三条工程约束）：**只进显示层绝不写载荷**（编辑预填/搜索/导出全消费原始 payload，永不污染）；**橙色 `*`** 与页头「N 条待同步」徽标同色（橙星=这条还没上云）；**精确到部分**——正文改动标正文、离线新增评论按下标标评论（互不误伤）。实现：库 v3 Entries 加 `pendingMeta` 列（JSON `{"t":true,"c":[3,4]}`，评论 append-only 下标稳定，坏 JSON 按无标记处理）；[diary_entry.dart](lib/core/model/diary_entry.dart) `parsePendingMeta/encodePendingMeta` + DiaryEntry.textPending/pendingComments；[app_session.dart](lib/core/session/app_session.dart) `_refreshMarks()` 唯一写入口（库行→内存条目重建标记+计数，杜绝手工维护各处漂移）、入队 merge、**推云成功/冲正成功即清**（推云成功顺带 syncState→0，修掉「干净条目在线推替换仍留 dirty」的边角）；渲染 [common.dart](lib/widgets/common.dart) `pendingMark` + 正文 Text.rich + 评论按 `contains(i)` 标注。
4. 测试 **111 项全绿**（新增 9：sized 规范化/预取清单收集/URL 缺失占位；pendingMeta 编解码往返+容错/离线发布整条标*/干净条目加评论只标评论/离线编辑标正文（各含冲正清空断言）；正文与评论渲染 `*` 精确标注）。analyze 零告警。踩坑：drift 列名不能叫 `blob`（与 Table.blob 构建器冲突）→ `bytes`（晨 14 补记）。

## 2026-11-16（晨 16）整体设计书落地 + 「设计先行」流程入 AGENTS（用户拍板）

1. **[docs/DESIGN.md](docs/DESIGN.md)** 建立：系统总览（分层/全局不变量/平台范围）+ 离线同步体系完整设计（状态模型/写路径矩阵/冲正算法/拉取保护/待同步标记/头像方案 D/已知取舍/**测试映射**/变更记录）。设计事实源归仓库；冻结契约仍指只读手册套件。
2. **AGENTS.md 新增「设计先行」**：任何改变 = 先提交设计文档的改变再改代码（顺序①文档②代码③analyze+测试④PROGRESS；偏差时回改文档，不允许代码先行）；测试映射表随设计一并更新。
3. 无代码改动（本提交纯文档 + 流程）；测试维持 111 项全绿。

## 2026-11-16（晨 17）13 项真机反馈批次：写路径本地先行 + 键盘/草稿/排序/双写（设计先行全程）

**设计先行两提交**：`63a4012`（13 项设计定稿 §2 修订 + §4 全表）→ `8a79b11`（用户重申**天卡必用接口图像**：废止天卡动物脸池早稿；§2.7 v3 = 预下载池基本设计——1w 张实测 ≈42MB、后台静默 3 并发/20 张小批/2~5s 抖动/Wi-Fi 断点续传/随机调用+缺失回退接口链路，**只设计不实现**）。

1. **写路径本地先行（§2 v2，真机反馈「离线发帖/评论明显卡顿」）**：publish/updateEntry/addComment/deleteEntry 统一为「加密→本地落库（syncState 1/2/3）→UI 即时返回→`_kickFlush` 后台冲正一次」——在线/离线同型，UI 永不等网络。`_replacePayload`（内联推云）退役 → `_stageLocal`（纯落库）；媒体一律先加密暂存、引用冲正时注入；`_flushDirty` finally 改 `_loadLocalEntries` 全量重建内存（serverId/引用/标记一并刷）；并发保护 `_flushing` + `debugHoldFlush` 测试开关；后台冲正 DioException→toast「云端不可达」、ApiException→同步横幅（不回滚不丢数据）。`flushNow()` 显式入口（syncNow/测试）。
2. **排序修复（§4.2）**：根因=组内顺序吃库行插入序（同步重建后新条目落卡底）。`groupByDay` 组内按 `payload.time` 倒序（同时间按 updatedAt 倒序）——与库序/插序解耦，任何重建路径确定性最新在最上。
3. **标签/心情双写（§4.1，契约内）**：推=`addTagPreset/setTagColor` 后 saveTag（**覆盖优先生效色**，无覆盖时哈希自动色物化；`tagColorName` 不查覆盖表是踩坑一次）；拉=syncNow 挂载 `_syncCfg` 补缺合并（同名本地优先，契约无时间戳）；删除名单 `cfg.tagDeleted` 防拉取复活（缺口 #8：无标签删除端点/无心情写入端点）；心情种子仅填充本地没有的 key。
4. **键盘（§4.4/4.6/4.8/4.11）**：AppState 加 `dataRev`（syncNow 成功自增）→ EntryView ref.listen 收起已展开评论；评论发送即 `unfocus`（本地先行后发送即时）；评论区根部长按吸收（`GestureDetector(onLongPress(){}, opaque)`）治「长按评论误触条目编辑」；HomeShell/compose 包裹「点空白收键盘」（子控件胜出竞技场不过敏，滚动不收）；登录弹窗三字段 textInputAction next/next/done。
5. **草稿缓存（§4.12）**：会话层 `saveDraft/loadDraft/clearDraft`（KV `draft.*`，300ms 防抖合并写；loadDraft 先落防抖值防旧读）；compose 新建/编辑（正文+心情+标签 JSON，未输入才应用防覆盖）、评论按条目（纯文本）；本地落库成功即清（离线队列保证最终推云）；注销/换身份 `clearDrafts()`（LocalStore 新方法，drift `k LIKE 'draft.%'`）。
6. **头像尺寸（§4.9/4.10）**：天卡 46→56（预取 s 同步改 56×3）；评论 32→24（原版 d776648 尺寸）。接口图像链路（EntryVO.avatar + 方案 D 预取）原样保留。
7. 测试 **126 项全绿**（新增 15：offline 2——后台冲正失败 toast/在线发布后台回填 serverId；draft_config 6——推生效色/拉补缺+同名本地优先/删除名单防复活/心情补缺/草稿往返防抖/注销清草稿；payload 2——组内时间倒序/同时间按更新倒序；keyboard 交互 5——长按评论不误触编辑/发送收键盘+草稿清除/评论草稿恢复/dataRev 收评论/点空白收键盘+compose 草稿恢复）。analyze 零告警。
8. **踩坑**：①testWidgets 是 FakeAsync 区——`Future.delayed` 永不推进（挂死 300s），必须 `tester.pump` 推假时钟；②`createIdentity→unawaited(_loadHolidays)` 的资产加载 `.timeout(2s)` Timer 在收尾被判 pending——bootstrap 后 pump 3s 放掉；③unfocus 断言不能是 `primaryFocus == null`（回落根 scope），用 EditableText 的 focusNode.hasFocus 翻转；④`tagColorName()` 只哈希不查覆盖表，推双写生效色要 `tagColorOverrides[tag] ?? tagColorName(tag)`。

## 2026-11-17（晨 18）头像预下载池落地：枚举改后端同款随机 QQ 邮箱逻辑（用户拍板「不要自定义种子」）

1. **设计修订（`30bd516`，DESIGN §2.7 v3→v4）**：用户重申天卡必用接口图像后拍板池枚举逻辑——**与后端 `AvatarUtil.ofRandomQQ` 完全一致**：随机 QQ 号（`RandomUtil.randomInt(123456789, 987654321, 双闭区间)`）→ `"%s@qq.com"` → md5 → cravatar URL；每格一个号、清单 `seeds.json` 持久化（一次确定永不重生成，避免文件与清单错位）——同一邮箱空间 = 池图像与接口图像同源同分布。黄金向量：md5(`798969707@qq.com`)=`dedf817b2bf150463aca1693856ad6e8`（后端 main 示例号）。断点续传简化为**文件即进度**（免 KV 位图）。
2. **池服务三件套**（条件导入，web 无 dart:io → 池禁用恒 NetAvatar）：[avatar_pool.dart](lib/core/util/avatar_pool.dart) 门面（+`avatarPoolProvider` 单例、onDispose stop）+ [avatar_pool_core.dart](lib/core/util/avatar_pool_core.dart) 平台无关核心（常量/`avatarPoolUrl`=md5→cn.cravatar.com 直连+`?s=184`/`avatarPoolIndex`=stableHash(盐|dateKey) 非负取模——与评论头像/标签色同源哈希）+ [avatar_pool_io.dart](lib/core/util/avatar_pool_io.dart) IO 实现（IoAvatarPool，fetch/isWifi/resolveDir/批量参数全可注入供测试）。新增依赖 `connectivity_plus ^6.1.4`（NWPathMonitor 封装；Wi-Fi/以太网放行，检测异常保守放行不阻塞）。
3. **后台静默管线**：`init()` 启动一次（无需身份、锁屏下可填；单飞 guard）；并发 3 / 批 20 / 批间隔 2~5s 抖动 / 单张超时 8s / **多轮全池巡检**——失败项下一轮重试、≤3 次封顶、一整轮无可做之事即收束（遗留项下次启动再巡检）；非 Wi-Fi 批间等待 60s 重查（仅 Wi-Fi 填充，1w 张 ÷ 3 并发 ≈ 55~90 分钟累计）；Application Support `avatarpool/av-<n>.png` tmp+rename 原子写（进程被杀不留半张、无状态损坏）。
4. **渲染接入**：[day_card_avatar.dart](lib/widgets/day_card_avatar.dart)（IO/Web 条件实现）——池文件命中 `Image.file`（ClipOval 同视觉、cacheWidth=56×3 与 s=184 源图 1:1 解码）本地直读零等待；缺失回落 `NetAvatar`（EntryVO.avatar + 方案 D 预取不变）。[feed_page.dart](lib/features/feed/feed_page.dart) DayCardBody 按 `avatarPoolIndex('$salt|$dateKey')` 取格：盐随刷新重掷 → 每轮换新、同周期稳定（与「刷新后新头像」拍板一致）。
5. 测试 **134 项全绿**（新增 8，`test/features/avatar_pool_test.dart`）：md5 黄金向量逐字钉死、indexFor 确定性+范围、种子生成（数量/唯一/双闭区间/持久化复用）、批次下载（全落盘/幂等不再拉/失败重试封顶/原子写不落半张）、并发上限峰值=3、Wi-Fi 门（非 Wi-Fi 零拉取+stop 退出）、pathFor 边界、渲染两分支。analyze 零告警。
6. **踩坑**：①门面文件只 `export` 条件实现时自身作用域没有 `createAvatarPool`（`import`+`export` 双写）；②`prefer_initializing_formals` 告警——注入型构造器的字段与参数同名（公开字段 + 初始化形参 + 默认值指向静态方法）；③重试语义：「≤3 次封顶」必须配**多轮巡检**（单轮内每格只访问一次，计数器无意义），收束条件=整轮零发起。

## 2026-11-17（晨 19）四件功能 + 排序语义修正 v2 + 服务端计算清单（设计先行全程）

1. **设计定稿（`6f733a7`，DESIGN §5）**：用户从提案菜单拍板四方向——评论长按菜单（复制/编辑/删除）、媒体全屏查看器、缺口 #7 身份变更客户端、iOS Widget 快照层（Swift 等买 Mac）；**AGENTS.md 新节「原生翻译友好约束」**（Windows 开发/后期购 Mac/便于 AI 翻译原生 SwiftUI：逻辑只写 core 纯 Dart 层、payload schema 唯一事实源、平台插件收敛单文件门面、UI Cupertino 声明式、Swift 专属件等 Mac）。
2. **排序语义修正 v2（`e4922be` 设计 / `5fb3edc` 实现，§5.8，用户拍板替代晨 17 §4.2）**：天卡=天逆序（已正确）+ **天内时间升序（写作先后）+ 评论不影响排序**。根因两处：晨 17 用了时间倒序 + updatedAt tiebreak（评论会刷新它）。修复=库表新增 `createdAtMs`（**schema v3→v4 迁移**，存量回填 updatedAtMs；publish 写一次、编辑/评论/冲正 absent 保留、sync 新行回填）+ `groupByDay` 比较链 `time↑ → createdAt↑ → updatedAt↑`。测试：升序确定性/同分钟创建序并列/**评论刷新 updatedAt 不变序**专项。
3. **评论长按菜单（§5.2，零契约改动）**：评论内嵌加密载荷（`EntryComment`）→ 编辑/删除=重建载荷走既有 `replaceEntry` 冲正。UI：§4.8 吸收点转正——长按自己评论 CupertinoActionSheet（复制/编辑/删除），他人评论仅复制；编辑=行内 TextField 预填。session `editComment/deleteComment` 镜像 addComment；`pendingComments` 语义扩为「未上云评论内容索引」（编辑并入去重、**删除移除+其后索引整体 -1**；`_stageLocal` 增 `replaceMeta` 整体替换旁路——合并语义对删除不成立）。测试 7 项（`comment_menu_test.dart`）。
4. **媒体全屏查看器（§5.3，`733ad50`）**：`session.mediaBytes` 查看管线（downloadMedia→`unwrapCek` 解媒体 CEK 包裹→AES-GCM 解密；会话级缓存，锁定/注销清空）+ `media_save` 门面（gal ^3.0.1 / web 桩，条件导入）+ `MediaViewer`（暗底 PageView 左右翻+InteractiveViewer 缩放+i/n 索引+保存到相册+失败页内重试）+ feed `ImageGrid.onOpen` 接线（**无密钥引用 tile 不响应——demo 占位不可点**）。边界：网格缩略图仍占位（每 tile=整原图下载+解密代价不成比例）；音频播放仍 P2。测试 7 项（`media_viewer_test.dart`；踩坑：`Image.memory` 需真实 PNG 字节、build 内回调 onLoaded 触发无界重建循环→改 future 完成时回调一次）。
5. **心情管理服务端同步核查与修正（`448ee5b` 设计 / `0c37abe` 实现，§5.9，用户拍板）**：核查结论=**只拉不推**（契约无心情写入端点=缺口 #8）+ **复活 bug**（服务端来源心情删除后被拉回——标签有删除名单、心情没有）。修正：心情删除名单 `_deletedMoods`（KV `cfg.moodDeleted`，拉取过滤防复活）+ 推送先行（api_client `saveMood/deleteMood` 镜像 saveTag 同 moodKey 幂等；addMood/updateMood 自定义推、removeMood 推删；colorHex→色名反查；**默认 6 心情显示覆盖不推=设备本地偏好**；失败静默端点上线即生效）+ 缺口 #8 扩充转发会话 A。测试 3 项（draft_config_test 心情组）。
6. **缺口 #7 身份变更客户端（`87b2240` 设计修订 / `e800081` 实现，§5.4）**：api_client `rename/rotate` 端点（提案）。`renameIdentity`：先过服务端（失败零状态变更）→ keystore.userId 更新 → 重注册。`rotateIdentity`：**序修正（实现期发现原草案有不可恢复中断窗口）**——① 新词新键对 → ② **keystore 先重写** + 旧私钥以新公钥 ECIES 暂存 `cfg.rotateOld` + 进度 `cfg.rotateDone` → ③ 逐条目重加密（**媒体 CEK 旧解新包，blob 免重传**；§4.3 原表述不完整已修正）→ ④ rotate 端点换 userKey 换 token → ⑤ 清暂存；崩溃后 unlock/init 挂钩 `_resumeRotateIfAny` 从进度续跑；轮换前先冲正（在途暂存媒体引用是旧钥包裹）。me 页入口**暂不露出**（「无端点前不做假 UI」），端点就绪一次性打开。测试 4 项（`identity_change_test.dart`）。
7. **Widget 数据快照层（`e800081`，§5.5）**：`widget_snapshot_core` 纯函数契约（writtenToday/todayCount/streak/lastText≤60 截断/lastTime/total/updatedAtIso；streak 与 computeStreak 同语义今天未写不断签）+ `home_widget` 门面（iOS 守卫、无 entitlement 静默、注入点测试预留）+ 接线在 `_loadLocalEntries` 尾部（所有数据变化汇聚点；**内容不变跳过**——比较排除 updatedAtIso 时间戳键）。**WidgetKit/App Intents/entitlements 等 Mac 后**（Windows 无法编译 Swift）。测试 4 项（`widget_snapshot_test.dart`）。
8. 测试 160 项全绿（净增 26），analyze 零告警。
9. **后端就绪收尾（§5.10，`94f6198` 设计 / `6770498`+`9d16b46` 实现，2026-11-17）**：会话 A 落地 stats/顺序契约/rename/rotate/mood 全部端点后——①**stats 消费**：api_client `stats()`/`StatsResult` 解析 + `AppState.stats`（syncNow 两路径拉取，失败静默保留旧值）+ me/memory 页**服务器优先本地兜底**（标签数仍本地=密文内）。②**身份变更入口打开**（§5.4 约定）：me 页安全组「更改注册名」「更换 12 词主密钥」两行 + 对话框（rotate 成功后新 12 词宫格 barrierDismissible=false 必点「我已抄写」）；原「更换主密钥」行标题澄清为「更换锁定口令」（重包裹封套不换钥，两概念并存需可区分）。③**服务端协议注意三条落地**：rotate 请求临时切回旧钥算 X-Diary-Pass（门先于控制器；失败恢复原值）、续跑改新钥 register 续接不重试 rotate（register 被拒兜底 rotate 一次；`cfg.rotateOldPub` KV 随注销清理）、emoji \uXXXX 标准解析零改动。④**mood color 契约修正**：服务端校验/种子=#RRGGBB hex（≠saveTag 色名）——推送 colorHex→`#RRGGBB` 格式化（原色名反查 live 实测 404）、拉取 `_moodColorOf` hex 优先兼容色名（种子 #34C759 不再落灰兜底）。⑤**定义核对**：streak 服务端（其 DESIGN §6.1.1）与客户端 `computeStreak` 逐字一致（锚点今天→昨天→无；今天没写不断签）零改动测试钉死；heatmap 稀疏格式一致（客户端渲染本就 `counts[date] ?? 0` 自填零值）；服务端 heatmap/perMonth 解析保留暂不消费（客户端已有全量明文索引）。
10. 测试 **169 项全绿**（净增 29，含 live 18 项对活后端），analyze 零告警。**真机验收清单**：天卡排序新语义 / 评论长按菜单 / 媒体查看器+保存相册 / 心情推送自动生效 / 身份变更两入口 / me-memory 页 stats 数字。
11. **CI 反馈修复（2026-11-17）**：①live M3-15~18 补 SKIP 守卫（CI 无后端，约定「后端在跑才执行」对全部 live 项生效——守卫曾被手动注释，已恢复+守卫）；②stats_sync 置位断言时序无关（CI 快机 bootstrap 内就完成首次置位）；③iOS deployment 13.0→14.0（home-widget 平台要求，CI Xcode 实测）；④live 注册统一 429 退避 helper（服务端新限流，本地连跑套件会撞）。
12. **屏蔽恢复 + 后端契约逐项核对（用户要求，2026-11-17）**：两笔「临时屏蔽」（5164a69 live 四项 / 2dd8023 stats_sync 一项）——live 四项已恢复+守卫；stats_sync「syncNow 成功置位」恢复为时序无关版。核对后端校验规则（RenameRequest 1~64 字符、RotateRequest 64hex、MoodWriteRequest moodKey ^[a-z0-9_]{1,16}$ + emoji @NotBlank≤8 + color #RRGGBB、stats days 1..3660）与客户端实现全部匹配；两处加固——live 退避序列 20s/45s 覆盖 60 秒滑窗（原 5s/10s 跨不过）、_pushMood emoji 空值兜底 📝（@NotBlank）。测试 **170 项全绿**。
13. **错误提示不外泄 + 锁定态发布竞态 + 地址保存健壮化（§5.11，用户真机反馈，2026-11-18）**：①**"Bad state: locked" 根因**=publish 的 `StateError('locked')` 经 compose `'发布失败：$e'` 上屏；触发链=compose 全屏路由浮于 HomeShell 内锁屏覆盖层之上，自动锁触发后发布页仍可操作。三重修：compose `ref.listen(locked)` 自动 pop 露出锁屏 + `_publish` 前置未解锁守卫（'会话已锁定，请解锁后再试'）+ UI 层 friendlyError 转义。②**地址保存**=setServerBase 无整体容错（全角冒号/空格 → Uri 解析异常静默吞、零反馈）+ 探测失败横幅透原始异常。重写：输入规范化（全角冒号`：`→`:`、去空格）→ 先校验后写入 → 保存成功 toast 诚实反馈 → 探测失败横幅『服务端已保存 · 暂时连不上，稍后可重试同步』。③**`friendlyError(e)` 统一映射**（新 `core/util/errors.dart`，纯 Dart）：ApiException 服务端中文原样 / DioException 按类型（超时/连接失败/网络异常）/ StateError 哨兵（locked/bio-missing/bad-passcode）转文案 / FormatException·ArgumentError message 直取 / 其余一律『操作失败，请稍后重试』——**UI 16 处 `$e` 全部收敛**（compose 3 处、comments_view 3 处、me_page 2 处、lock_overlay、dialogs 5 处、media_viewer、onboarding、pass_setup、app_session 4 处）。④**unlock/unlockBiometric 联网尾段不再抛**（口令验证通过即解锁成功，注册/同步失败转友好同步横幅——服务端不可达不阻断解锁，锁屏也不再误显『面容解锁未就绪』）。测试 **181 项全绿**（净增 11：errors_test 5 项映射 + session_error_test 5 项会话级 + compose 锁定自动 pop widget 测试 1 项；bio_unlock/identity_flow 三处 unlock 抛出断言按新语义改写）。

14. **头像链路本地化 v5 + 设置页更新进度（§5.12，用户真机反馈「头像只使用本地，没有就默认人像」，2026-11-18）**：渲染零网络——`DayCardAvatar` 池命中 `Image.file` 直读本地 av-*.png、池缺失/未启用 → 默认人像占位（灰圆+person 图标，视觉同原 NetAvatar 占位）；删除 NetAvatar 组件与 feed 网络预热循环（precacheImage）、session 头像内存缓存链拆除（lock/注销/删除条目/_syncOnce/_loadLocalEntries 全部不再碰头像）。**PoolProgress(filled,total,enabled) ValueNotifier 上报**（IO 池目录扫描初值/每张下载成功递增；web/未启动=未启用；demo/测试环境不启动池——测试不触网）；me 页配置组「头像库」行实时显示 未启用/更新中 f/t/已就绪 f/t。demo_data 删 avatarUrl。测试 179 项全绿（净删 NetAvatar 3 项/新增渲染两分支+进度断言）。
15. **功能级 E2E 设施 + 两真 bug 修复 + 后端 CORS 迭代（§5.13，用户纠偏「要功能测试不是单元测试」——真实 GUI 全流程打真实后端，2026-11-18）**：
   - **设施**：`integration_test` + `flutter drive -d chrome`（`--browser-dimension=390,950`，headless 默认 800×600 视口会让懒构建断言全错位）+ chromedriver 157 + 三次重试 wrapper + 停摆看门狗（日志 180s 无更新杀浏览器逼退）；五段流程 `test/integration/app_flow_test.dart`——T1 首开注册→发布→冲正、T2 重启口令解锁→云端回拉、T3 评论增改删真后端回环、T4 地址保存健壮化+头像库行、T5 锁定解锁+友好错误映射；`env.isTestEnv()` 守卫（`flutter test` 下整组 SKIP，仅 drive 真栈运行——VM 下 dart:io 可用但 web 编译单元是桩，探测用 dio）；`tool/serve.js` /api/* 同源反代（与生产 nginx 同拓扑，web 预览真栈不依赖 CORS）。
   - **后端 CORS 迭代闭环（派活会话 A 三单）**：E2E 首跑发现 9060 无 ACAO 头 → 后端安全评估原主张「删 CORS」与 web 预览需求冲突 → 折中 env 开关 `DIARY_CORS_ORIGINS`（默认空=关、Origin 回显、headers 含 Authorization/X-Diary-Pass/Content-Type）→ 会话 A 自启新后端 → curl 验收（GET ACAO 回显/OPTIONS 预检 200/注册 200）。
   - **两真 bug（E2E 实测抓到，单测钉死，与 DESIGN §5.13 对应）**：①`lock_overlay` setState after dispose——unlock 成功 locked=false 早于联网尾段 → 锁屏提前卸载 → 解锁收尾回调崩；两路径补 `mounted` 守卫。②**口令错误哨兵从未兑现**——unlockKeystore 无 try/catch，口令错误实抛 cryptography 包 SecretBoxAuthenticationError，文档哨兵 `StateError('bad-passcode')` 不存在 → UI『口令不正确』分支恒不命中，用户看到泛化文案；补 try/catch 归一哨兵 + 单测（错误口令抛哨兵且 locked 不变）。
   - **E2E 工程要点（后续会话必读）**：① 1 分钟自动锁截断 >60s 流程（默认 autoLockMin=1）→ 测试解锁尾段 `setAutoLock(0)`（KV 持久，应用侧语义不变）。② onboarding 是 ListView 懒构建——折叠线下组件不进树（find 不到/enterText 打错字段），先 `scrollUntilVisible` 入树再交互；`ensureVisible` 对未构建 finder 无效；dialog 命中后 pump 落定动画再点（动画中点击落空）；drive 输出接管道会被 grep/tail 整体缓冲 → 日志直落文件；DDC 按需编译首个等待放大预算（240s）；DWDS AppConnectionException 启动抖动 ~50% → 清 chrome/chromedriver 进程重试；serverStatus 渲染在「端到端加密」信息弹窗内（页面树上没有）→ 开弹窗读取。
   - **结果（诚实口径）**：单测 **185 项全绿**，analyze 零告警。E2E 最完整一轮（哨兵修复前）T1~T4 全绿实测（T1 01:53 / T2 03:34 / T3 05:24 / T4 07:28）；T5 卡点即真 bug ②（哨兵），修复后由哨兵单测+锁定语义单测覆盖，且修复后复跑 T1 01:44 通过（证明修复不伤主流程）。哨兵修复后的完整复跑受宿主浏览器抖动未能收束（三种实测死法：Chrome 进程中途死亡/renderer 30s 失联（孤儿 dart 编译进程挤压内存，清后复现）/DWDS 启动期停摆——看门狗三轮全部正确收束）；据此把 Argon2id 相关等待预算放大（Icons.edit 120→240s、云端回拉 20→45s，符合 §5.13「DDC 预算放大」既定原则）。**应用逻辑全链路 = T1~T4 真后端 GUI 实测 + T5 关卡单测**；Windows 宿主 web E2E 抖动大，单次全绿需宿主安静时段，真机回归按 M5 清单执行。

16. **真机反馈第三批八项 + 换钥口令根治（§5.14，用户 2026-11-19 拍板清单）**：
   - **①心情全面服务端化**：核实后端 mood 为全局表（无 userId 维度，服务端即唯一事实源）→ 客户端废除「显示覆盖+种子补缺+删除名单」混合模型——`AppDefaults.serverMoods` 全量覆盖拉取（KV `cfg.moodServer` 快照离线兜底）、增/改/删全部即时推服务端（await saveMood/deleteMood，失败不落本地提示需联网）、默认心情同路径可改不可删；种子中文名静态映射（服务端 name 缺口 #9 落地前回落）。
   - **②换钥后「同步失败，口令过期」根治**：根因=rotateIdentity 步骤③（全量重加密）提前切新钥 otpKey，而服务端仍持旧 user_key → 每请求 401「动态口令无效」→ 中断 → 续跑同错 → 死循环。**客户端修复**：③ 期间口令钥保持调用前值、④ rotate 成功才切新、续跑两态覆盖（rotate 已落/未落服务端）；**契约缺口 #10**（用户拍板「hash 不要用会变动的量」）派活后端会话落地——user.pass_key 列（注册声明制、rotate/rename 不触碰、门验证 pass_key 非空恒用之/空回退 user_key）+ RegisterRequest.passKey + RegisterResponse.passKeyRegistered，curl 全链路验收（注册/rotate 前后 passKey 口令均通、passKeyRegistered 正确）；**客户端第二轮跟进**：keystore 增 passKey（每设备随机 64hex，`ks.passKey`）、首次注册生成落盘、拦截器口令输入源 = _passKeyOf（passKey 优先回退 userKey）——换钥全程零口令错位窗口。改名路径逐行核实本就安全（hash 输入是 user_key 非用户名）。
   - **③头像池未满即显示**：池未命中 → `Image.network` 即时回落（cravatar 直连）+ 挂载触发 ensureIndex 补写池（原子写/在途去重/失败静默）——没下满 1w 也都有头像；web 恒占位不变（cravatar 无 CORS）。
   - **④FaceID 二选一**：解锁成功路径补「ui.bio=1 且钥匙串存档缺失 → 静默重存」自愈（biometryCurrentSet 平台失效语义不再打断常态）；bio-missing 文案改「面容存档已失效 · 请先用口令解锁，之后面容将自动恢复」；**face 改口令**——更换锁定口令弹窗加「使用面容 ID 验证」（rekeyWithBio：生物识别通过免旧口令重包裹）。
   - **⑤⑥设置页瘦身**：删「端到端加密」「多设备共享」两解释行与底部脚注；serverStatus 并入「服务端地址」弹窗（唯一出口，E2E probeSettles 同步改）；重分组=安全组/身份组/通知组/配置组/数据组；多设备共享 ④⑤契约文案并入「新设备登录」弹窗首段。
   - **⑦日历排版**：底部图例移顶部说明行（节假日说明合并）；底部统计升级卡片（本月条数+连续天数+心情 top3，FittedBox 防窄屏溢出）。
   - **⑧提示语上浮**：全局 ToastHost 底部黑胶囊 → 顶部浮窗（安全区下悬停，逻辑不变）。
   - **测试 190 项全绿**，analyze 零告警。E2E 诚实口径：§5.14 八项代码（passKey 接入前）真后端 GUI 实测 **T1~T4 全绿**（02:18/04:19/06:32/09:03——发布等待预算 240s 修复 DDC 编译抖动后）；passKey 接入后完整复跑受宿主浏览器反复崩溃未收束（用户拍板收尾）——passKey 为纯确定性输入源切换，语义由 identity_change 口令时序断言单测覆盖；E2E 设施预算修正随本轮落盘（发布等待 240s、看门狗 300s）。

## 测试清单（`flutter test` 190 项全绿；后端未启动时 live 项自动 SKIP，就绪后 18 项全跑）

- **golden 向量 9 项**（`test/core/e2ee/golden_test.dart`，02 §7 固化向量）：Argon2id masterKey、X25519 公钥推导（clamp）、sharedSecret、HKDF encKey、92B EncryptedCEK 字节布局、AES-GCM cipher+tag 布局、完整 JSON fixture 解密、确定性加密复现完整 JSON、随机往返。**一次实现全绿**，Dart 端与 Go 参考实现逐字节互通。
- **恢复词 7 项**（`test/core/session/recovery_words_test.dart`）：BIP39 黄金向量（熵全 0 短语+seed，Node 互证）、生成多轮校验、抄写错误四类拒绝（换词/缺词/词表外/错序）、空白归一化、hex 判定、**diaryPass 动态口令向量（活后端实测）+窗口边界**。
- **身份 6 项**（`test/core/session/identity_test.dart`）：同短语同身份、异短语异身份、**hex 导入=短语导入往返**、空白归一化、deviceNo 随机 UUID v4（不复用）、非法输入拒绝。
- **身份流程 11 项**（`test/core/session/identity_flow_test.dart`；2026-11-18 §5.13 增口令错误哨兵 1 项——unlock('999999') 抛 StateError(bad-passcode) 且不解锁）：createIdentity 落盘/校验失败不留痕/注册名 gate、loginIdentity 同词同公钥（跨设备等价）/词校验拒绝、存量补设注册名（deviceNo 保留）、**注销账号（KV 全清 + 状态回引导 + 原词可重登）**、**P1-3 落盘零明文（库行只有密文 + 解密重建）**、**P0-2 needsPass 引导状态机**、**P1-4 lock 清内存明文（解锁后从密文重建）**。MemoryLocalStore 注入（debugUseStore/debugRestorePlainSession/debugReloadEntries 钩子）。
- **面容解锁 4 项**（`test/core/session/bio_unlock_test.dart`）：启用（生物识别确认 → 私钥入库 + ui.bio）、锁定后面容免口令解锁（bio-missing 回退信号 + 口令回退仍可用）、拒绝启用（识别未过/设备不可用）+ 关闭清除、注销清除钥匙串存档。FakeBioVault 注入。
- **core 单测 8 项**：tagColor 哈希与 JS 参考实现一致、payload 序列化往返、容错解码、天分组、调休合并/说明行/命中。
- **UI 冒烟 21 项**（390×844 手机视口）：feed 渲染（**头像头部/年月一行/若隐若现分割线**）/折叠/**下拉刷新头拖拽箭头**/**关键词搜索（正文/标签/无结果/还原）**/**评论展开（第三方随机头像 + 存量 HH:mm 补日期标准格式）**/日历/**跨月双休红显（outside weekend）**/回忆/我的页全行/发布流（标签 chips 点选）/TagChip/标签管理回归/**标签调色板改色（粉→0xFFFF2D55 断言）+ 心情管理列表**/**长按编辑**/**长按删除（二次确认）**/主题三档/**onboarding（12 宫格优先+随机生成+黄金向量提交）/401 横幅**/**ToastHost 3 项**。
- **App 图标 3 项**（`test/features/app_icon_test.dart`，2026-11-16）：弹窗默认+三样例+当前勾选、点击样例通道 set、默认=空串映射（原生 setAlternateIconName(nil)）。MethodChannel mock。
- **SWRR 算法 3 项 + 动物头像 4 项**（`test/features/swrr_test.dart`、`animal_avatar_test.dart`，2026-11-16）：等权平滑轮询不饿死/全覆盖/加权平滑性（[1,1,2] 四轮 c×2 不相邻）；stableHash 确定性/原版 20 动物脸表互异/裸 emoji 渲染无底色/盐变随机性。
- **离线队列 7 项**（`test/features/offline_sync_test.dart`，2026-11-16 晨 14）：发布断网本地入队（syncState=1+计数+提示）、手动刷新冲正新建+幂等不重放、评论断网待替换（syncState=2 → 冲正推替换且评论在密文内）、删除已同步条目断网待删除（syncState=3 → 冲正推删除）、离线新建再删本地直除、冲正中途断网已推清队未推保留（下次刷新续传）、带图发布断网媒体加密暂存 → 冲正上传注入引用。FakeApi 注入（debugUseApi，online 开关模拟断网/恢复，DioException=断网信号）。
- **头像预取/淡入 3 项 + 待同步标记 6 项**（`test/features/net_avatar_test.dart`、`offline_sync_test.dart` 标记 4 项、`pending_mark_test.dart`，2026-11-16 晨 15）：s= 尺寸规范化、天卡头像预取清单收集去重、URL 缺失占位；pendingMeta 编解码往返+坏 JSON 容错、离线发布整条标 *（冲正清空）、干净条目加评论只标评论正文不标（冲正清空）、离线编辑标正文（冲正清空）；正文/评论渲染 `*` 精确标注。
- **显示配置 4 项**（`test/core/session/display_cfg_test.dart`）：标签库增删（初始含默认三项）+ KV 重载（'[]' 空库语义）、调色板覆盖/恢复自动/非法色名忽略、心情增删改（默认仅改显示）+ KV 重载、cfgVersion 自增。MemoryLocalStore 注入 + debugLoadCfg 钩子；静态表 setUp/tearDown 复位防污染。
- **本地先行/后台冲正 2 项**（`test/features/offline_sync_test.dart` 增补，2026-11-16 晨 17）：离线发布→后台冲正失败 toast「云端不可达」留队；在线发布本地先行→后台冲正回填 serverId+清队列标记（发布即时返回不等网络）。`debugHoldFlush` 挂起后台触发保确定性。
- **双写/草稿 6 项**（`test/features/draft_config_test.dart`，2026-11-16 晨 17）：saveTag 推覆盖优先生效色（同名=更新）；拉取补缺合并+同名本地优先；删除名单防拉取复活；心情种子仅补本地没有的 key；草稿保存/读取往返（loadDraft 先落防抖值）+ 清除；注销清草稿与删除名单。CfgFakeApi 补 config 三端点桩。
- **组内排序 3 项**（`test/core/model/payload_test.dart`，2026-11-17 晨 19 语义 v2）：乱序输入组内 time 升序（写作先后）确定性输出；同分钟并列按创建序 createdAt；**评论/编辑刷新 updatedAt 不变序**专项（晨 17 版倒序断言已按用户拍板改写）。
- **键盘/评论交互 5 项**（`test/features/keyboard_interactions_test.dart`，2026-11-16 晨 17）：长按评论不误触条目编辑（手势吸收）；评论发送后 focusNode 失焦+输入清空+草稿清除；评论草稿恢复预填；dataRev 自增收起已展开评论（失败路径不收）；compose 草稿恢复+点空白收键盘。FakeAsync 踩坑：pump 推假时钟 + pump 3s 放掉 holidays timeout Timer（见晨 17 §8）。
- **评论菜单 7 项**（`test/features/comment_menu_test.dart`，2026-11-17 晨 19）：编辑（载荷重建/标记并入去重/冲正推云新文本在密文内/保留原评论时间）；删除（标记索引重排其后-1/冲正后服务端载荷少一条）；删除未冲正新评论（标记随内容消失/载荷留队幂等）；菜单差异（自己=复制/编辑/删除，他人=仅复制）；复制（剪贴板 mock+提示）；行内编辑（预填/保存落库载荷更新）；删除确认弹窗。
- **媒体查看器 7 项**（`test/features/media_viewer_test.dart`，2026-11-17 晨 19）：查看管线往返（加密上传→下载解密逐字节相等）；缓存命中不再下载；空密钥引用拒绝+未知媒体 id 报错；查看器暗底/索引标题/关闭返回；加载失败页内重试；保存按钮加载后启用+注入 saveBytes 被调+提示；ImageGrid 门控（无密钥引用不响应）。
- **心情同步 3 项**（`test/features/draft_config_test.dart` 增补，2026-11-17 晨 19）：自定义增/改推 saveMood（colorHex→色名反查/同 moodKey 幂等）+默认覆盖不推；删除名单防复活（删除推 deleteMood+KV 持久化+拉取过滤）；推送失败静默（本地照常生效/名单仍持久化）。
- **身份变更 4 项**（`test/features/identity_change_test.dart`，2026-11-17 晨 19）：改名全链路（rename→keystore 落盘→重注册同 userKey 新 userId）；改名 404 零状态变更；换钥全链路（全量重加密/媒体 CEK 重包裹后 mediaBytes 仍可解/新钥可解旧钥不可解/rotate 端点一次/register 不再走/暂存清理）；轮换中断续跑（④ 失败暂存留存→debugResumeRotate 补 ④⑤ 清暂存）。
- **统计消费 6 项**（`test/features/stats_sync_test.dart`，2026-11-17 晨 19 收尾）：StatsResult 解析（稀疏 heatmap/date ASC/perMonth/缺字段容错）；syncNow 成功置位 AppState.stats；拉取失败静默保留旧值；computeStreak 边界三类钉死服务端定义（今天写/今天未写昨天写不断签/今天昨天都无=0）。
- **live 联调 4 项**（`test/live/integration_live_test.dart` M3-15~18，2026-11-17 晨 19 收尾，对活后端）：stats（独立身份建 2 条 → total=2/streak≥1/heatmap 全正数+date ASC+窗口含今天/perMonth 含当月）；rename（改名→新名重注册同 userKey 成功）；rotate（换 userKey 换 token→新 token 新钥建条目）；mood 写删（saveMood #RRGGBB → 回读 → deleteMood 消失）。
- **Widget 快照 4 项**（`test/features/widget_snapshot_test.dart`，2026-11-17 晨 19）：构建器（今日已写/今日条数/streak 断档/已删不计/最近一句=日期+日内时间最大/lastText 60 字截断）；今天未写不断签；空数据全零；会话接线（汇聚点触发/内容不变跳过排除时间戳键/发布后写入全字段）。
- **错误提示/地址保存/解锁健壮化 11 项**（`test/core/errors_test.dart` 5 + `test/features/session_error_test.dart` 6，2026-11-18 §5.11）：friendlyError 五类映射（ApiException 原样/DioException 按类型/StateError 哨兵/校验异常 message 直取/未知兜底且不透原始文本）；setServerBase 全角冒号+空格规范化持久化、非法地址（端口含字母）不动现有配置+中文提示、空输入提示、不可达地址不抛+横幅友好（无原始异常文本）、可达时「服务端已连接」；unlock 服务端不可达不抛且锁定解除+横幅友好；compose 自动锁触发自动 pop（widget 级竞态兜底）。
- **心情服务端化 6 项**（`test/features/draft_config_test.dart` 心情组重写 + `display_cfg_test.dart` 快照组，2026-11-20 §5.14）：全量覆盖拉取（服务端列表胜/名称回落/快照落盘/空表守卫）、增改即推后重拉（默认心情同路径推送）、删除推 deleteMood+默认不可删（全局表保护）、推送失败不落本地（严格云一致）、快照 KV 重载恢复+坏数据回落种子。
- **FaceID 自愈与 face 改口令 2 项**（`test/core/session/bio_unlock_test.dart` 增补，§5.14）：ui.bio=1 钥匙串失效 → 口令解锁成功即静默重存（下次面容恢复可用）；rekeyWithBio 生物识别通过免旧口令重包裹、未通过/设备不可用/口令过短拒绝。
- **头像按需回落 3 项**（`test/features/avatar_pool_test.dart` 增补，§5.14）：urlForIndex（种子就绪/未启动/越界）、ensureIndex（下载原子入池/已有跳过/在途去重/失败静默）、渲染未命中挂载触发 ensure+命中不触发。
- **换钥口令时序 2 项**（`test/features/identity_change_test.dart` 增补，§5.14）：③ 重加密期间口令钥恒定=passKey（replaceOtps 逐次捕获断言）；rotate 请求口令=passKey、改名不动口令种子。
- **光晕像素采样 2 项**（`test/features/glow_pixel_test.dart`；深色期望改为可见 Δ≥4 ≤48——用户覆盖原版 0.15）。
- **头像池 9 项**（`test/features/avatar_pool_test.dart`，2026-11-18 §5.12 改造）：md5 黄金向量、indexFor、种子生成、批次下载（全落盘/幂等/失败重试封顶/原子写）、并发上限、Wi-Fi 门、pathFor 边界 + **渲染两分支（池命中 Image.file / 缺失默认人像占位 byIcon(Icons.person)）+ PoolProgress 进度断言（目录扫描初值/逐张递增）**。NetAvatar 3 项随组件删除（`git rm`）。
- **live 集成 14 项**（`test/live/integration_live_test.dart`）：原 11 项回归（全程隐式验证 X-Diary-Pass）+ M3-12 动态口令 401 + M3-13 多设备共享 + M3-14 冒名拒绝。**2026-11-14 后端 v4 实测 14/14 全绿**（未启动自动 SKIP）。

## 视觉对照（Chrome，390×844，浅色+深色）

已逐页对照 mockup v2：时光（天卡片/日期盒/等宽时间前缀/标签 8 色哈希/心情/评论徽标 0 条不显示数字/长文折叠/九宫格/今日空卡）、日历（‹ › 今/休班徽章 10.1-10.7 休 + 10.10 班/心情圆点 ≤3/底部统计/补位灰显）、回忆（hero 23 天/那年今天/随机翻一条/热力图 7 行×26 列）、我的（3 统计卡/安全组/通知组/配置组/数据组全行）、发布页（全屏上滑/心情 6 胶囊反选/标签回车/照片+麦克风/加密脚注）、发布流（发布→toast「已加密保存 · 每条独立密钥 ✓」→跳时光→当天日期数字按组高亮）。

浏览器过程中发现并修正：
1. 热力图方向（原 7 列 → 修正为 mockup 的 7 行×26 列列优先）。
2. 天卡片日期数字误常显组色 → 修正为常态 label 色、仅高亮变组色（mockup .hl 语义）。

## 契约缺口记录（00 §3.2：提请用户拍板，未擅自改契约）

1. **身份模型 v4 未回写手册（2026-11-14 后端先行演进）**：02 §5 仍是 {deviceNo, publicKey} 注册 + 静态 token；实况为 {userId=注册名, deviceNo, name=设备名, userKey=公钥} + 每请求动态口令 `X-Diary-Pass=SHA-256(userKey:窗号)前8位`（5 分钟窗）。客户端按实况适配（公式自后端调试台 v4 注释提取并 curl 实测钉死）；**建议会话 A 将 v4 契约回写 02 手册**（userKey 大小写归一、窗口边界容差、错误码语义）。
2. **评论无专用接口**：01 §2.1 要求评论懒加载，02 §5 无 comments 端点。实现取载荷内嵌（评论进密文，新增=整条重加密 replaceEntry）。如需真懒加载/多设备评论合并，需在 02 §5 增补端点。
3. **sync 条目的 deleted 字段未在字段级定义列出**：客户端按可选字段兼容解析；**M3-9 实测服务端确实带该字段**，缺口消解。
4. **正文长度**：按 01（设计真源）实现：无硬限，超 6 行折叠「展开全文」（以 mockup 为准）。
5. **音频播放**：03 §6 只覆盖录音+波形，未指定播放库；feed 录音条目前为展示，P2 需要时引入播放库。
6. **标签/心情配置为设备本地（2026-11-14 夜 3）**：02 §4.2 提到 tag_config 服务端种子（device 0），但 §5 契约无配置读写端点。现实现存本机 KV（cfg.*），标签库/调色板/自定义心情**不随多设备同步**；若需多设备共享配置，提请会话 A 在 §5 增补端点后再切服务端存储。
7. **暗色光晕系数（2026-11-14 夜 3 用户拍板）**：原版 body.dark ×0.15（近不可见）被用户「暗色模式也需要渐变」明确覆盖为 0.40/0.55；如后续要回原版表现，改 `Tokens.glowBaseOpacity/glowHotOpacity` 一处即可。
8. **注册名不可变更**：文案①「终身使用」——客户端无改名入口；如需改名需后端先定义语义（同名异钥已被拒绝，改名=数据空间迁移，涉及服务端）。
9. **身份变更能力（晨 17 §4.3，提请拍板，DESIGN §4.3 有草案）**：①改注册名=服务端重键数据空间，需后端 rename 端点；②换 12 词主密钥=新 userKey，被「同 userId 必须同 userKey」校验拒绝，需后端放行或 rotate 端点（客户端协议：全量拉取解密→重加密逐条 replace 幂等→keystore 重包→re-register，媒体 blob 无需重传）。二者本轮**客户端零改动**。
10. **标签/心情双写受契约限制（晨 17 §4.1）**：POST /config/tags 仅增改（同名=更新）**无删除端点**；/config/moods **GET-only 6 种子**；且 tag 配置按 device 键控，跨设备同步契约本就不承诺。端上已按契约能力双写（推增改/拉补缺/删除名单防复活）；若需真删除与跨设备共享，提请会话 A 扩展端点。

## 实现约定（指回手册）

- **依赖**：03 §2.1 清单全部落位（cryptography 2.9 / pointycastle 4.0 / dio / drift / image_picker / audio_waveforms / flutter_local_notifications / timezone / local_auth / table_calendar / flutter_riverpod），另加 drift_dev+build_runner（codegen）、share_plus（导出 03 §6）、path_provider+sqlite3_flutter_libs（drift 运行时）、flutter_riverpod 替代裸 riverpod（UI 层需要）。
- **载荷 schema**（客户端自由度，`core/model/diary_entry.dart`）：`{v:1, text, time:"HH:mm", mood:mood_key|null, tags[], media:[{id,kind,cek(92B ECIES b64),sec}], comments:[{who,text,time}]}`。媒体 CEK 独立 ECIES 包裹 → 编辑重加密不影响媒体可解。
- **媒体密文布局**：blob = nonce(12B) ‖ AES-256-GCM(cipher+tag)；CEK 逐媒体 ECIES 包裹进载荷引用。
- **keystore / 身份**（`core/session/crypto_session.dart`，2026-11-14 晚 v4）：身份文本 = 12 恢复词短语（BIP39 中文简体，校验和防抄错）或其派生密钥 64hex（seed 直填，等价导入）→ SHA-256 → X25519 确定性密钥对；**userKey=publicKeyHex** 注册到服务端；**userId=注册名**（用户自起，终身不变，多设备共用）；**deviceNo 每设备随机 UUID v4**（不复用旧设备号）；动态口令 X-Diary-Pass 由 kdf.diaryPass 每请求实时推算。锁定开启时 Argon2id(口令,盐) 包裹私钥；换口令仅重包裹（03 §2.2 第 6 条）。锁定关闭时私钥明文本机存（调试模式）。存量旧版 64-hex 秘钥 keystore：无恢复词、需一次性补设注册名（OnboardingPage nameOnly 模式）。
- **平台范围（2026-11-13 用户拍板）**：**仅 iOS**。`android/`、`windows/`、`linux/`、`macos/` 目录已删（`flutter create . --platforms <平台>` 可随时恢复）；`NotificationService.supported` 收敛为 iOS-only；注册设备名固定 'iPhone'。保留 `web/` 仅作 Windows 开发机本地预览目标（Chrome），非发布平台。**Windows 上的查看方式=Chrome 预览（用户已确认）**：本机未装 Visual Studio（C++ 工作负载），Windows 桌面应用无法构建；如日后需要，装 VS 2022（Desktop development with C++）+ 开发者模式后 `flutter create . --platforms windows` 再构建。iOS Info.plist 已加 FaceID/相册/麦克风描述 + ATS 任意明文（调试期，03 §3.1）；Bundle ID `la.tucao.diary`（03 §1）。
- **iOS 通知**：flutter_local_notifications 21:30 每日提醒的调度代码在「每日提醒」开关（`_scheduleDailyReminder` 于 session 层待接入——见「未竟事项」第 3 条）。

## 环境注意事项（本机特有，后续会话必读）

1. **sqlite3 构建钩子**：pubspec `hooks.user_defines.sqlite3.source: system`——本机 release-assets.githubusercontent.com 被网络拒（GitHub 主站可达、资产 CDN 不可达），无法下载预编译库。system 模式运行时按名加载：Windows 宿主跑 `flutter test` 需 `tool/bin/sqlite3.dll` 在 PATH（`source tool/env.sh`，DLL 取自本机 Navicat）；iOS 由 sqlite3_flutter_libs 打包按名加载。运行时无哈希校验（system 模式），DLL 版本需 ≥ drift 要求（实测 Navicat DLL 通过全部测试）。
2. **web 构建**：`drift/native.dart` 不可进 web 编译图——已用 `db_open_stub.dart if dart.library.io` 条件导出隔离；web 默认演示数据（`--dart-define=DEMO=0` 可强制真实栈联调）。
3. **测试环境检测**：flutter_test 注入 `FLUTTER_TEST` 环境变量，session 据此回落演示数据（`core/session/env_check*.dart` 条件导入，web 不引 dart:io）。
4. **flutter 命令**：PATH 加 `/e/flutter/bin`（04 故障表）；已执行 `git config --global --add safe.directory E:/flutter`（flutter 自身 git 调用报 dubious ownership 的标准修复）。

## 未竟事项（按优先级）

1. **M4-a**：建 GitHub 仓库（公开免费 macOS runner，00 §6）→ push → workflow 自动出 ipa artifact。
2. **每日 21:30 本地通知调度**：已实现；真机验证（M5）待做。
3. **Face ID 快捷解锁**：local_auth 集成已写，但无 Keychain 存储（flutter_secure_storage 不在手册依赖表），Face ID 通过后仍需口令派生主密钥。真机体验如不满足，提请用户拍板是否增补依赖。
4. **真机回归 M5**：Face ID/通知/相册/录音/Pushover/新身份全流程（M4-b Sideloadly 装机后）。
5. **②完整登录 UI 循环（浏览器）**：✅ 已完成（2026-11-14 夜 2）——注册名 123 + 派生密钥 26670b…6720 实测：toast 自动消失、云端两条同步解密、发布页出现云端标签 chips。剩余仅 M5 真机回归。
6. **建议会话 A**：①02 手册回写 v4 契约（见契约缺口第 1 条）；②注册名唯一性语义确认（后端实测「不同 userId 可绑同一 userKey」——数据空间按 userId 分组，同一人起两个注册名=两个空间，与文案④「数据按注册名共享」一致，无冲突）；③**随机头像（EntryVO.avatar）契约增量回写**（2026-11-15 用户拍板：响应时现生成随机 cravatar URL、不落库、每次请求不同——02 §5 字段表未列，客户端已按可选字段兼容；**晨 4 起客户端展示改本地确定性生成，该字段客户端不再消费**）。
7. **小项**：发布页「发布」禁用态颜色；demo 模式热力图底注 17 天固定文案。

## 本夜产出小结

- 工程：feature-first 结构完全按 03 §1（core/{e2ee,db,api,holiday,config,session,model,repo,util,notify} + features/{shell,feed,compose,calendar,memory,me,lock,theme} + widgets）。
- 代码约 4800 行 Dart（不含 codegen）；测试 38 项全绿；analyze 零警告。
- 加密核心 100% 公开库组装（零手搓算法），golden 钉死字节协议。
- Chrome 视觉复现命令：`flutter build web --release && node tool/serve.js 8123` → 浏览器开 `http://127.0.0.1:8123`（演示数据）。
