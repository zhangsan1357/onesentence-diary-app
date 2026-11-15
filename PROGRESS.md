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

## 测试清单（`flutter test` 82 项全绿；后端未启动时 live 14 项自动 SKIP）

- **golden 向量 9 项**（`test/core/e2ee/golden_test.dart`，02 §7 固化向量）：Argon2id masterKey、X25519 公钥推导（clamp）、sharedSecret、HKDF encKey、92B EncryptedCEK 字节布局、AES-GCM cipher+tag 布局、完整 JSON fixture 解密、确定性加密复现完整 JSON、随机往返。**一次实现全绿**，Dart 端与 Go 参考实现逐字节互通。
- **恢复词 7 项**（`test/core/session/recovery_words_test.dart`）：BIP39 黄金向量（熵全 0 短语+seed，Node 互证）、生成多轮校验、抄写错误四类拒绝（换词/缺词/词表外/错序）、空白归一化、hex 判定、**diaryPass 动态口令向量（活后端实测）+窗口边界**。
- **身份 6 项**（`test/core/session/identity_test.dart`）：同短语同身份、异短语异身份、**hex 导入=短语导入往返**、空白归一化、deviceNo 随机 UUID v4（不复用）、非法输入拒绝。
- **身份流程 7 项**（`test/core/session/identity_flow_test.dart`）：createIdentity 落盘/校验失败不留痕/注册名 gate、loginIdentity 同词同公钥（跨设备等价）/词校验拒绝、存量补设注册名（deviceNo 保留）、**注销账号（KV 全清 + 状态回引导 + 原词可重登）**。MemoryLocalStore 注入（debugUseStore/debugRestorePlainSession 钩子）。
- **面容解锁 4 项**（`test/core/session/bio_unlock_test.dart`）：启用（生物识别确认 → 私钥入库 + ui.bio）、锁定后面容免口令解锁（bio-missing 回退信号 + 口令回退仍可用）、拒绝启用（识别未过/设备不可用）+ 关闭清除、注销清除钥匙串存档。FakeBioVault 注入。
- **core 单测 8 项**：tagColor 哈希与 JS 参考实现一致、payload 序列化往返、容错解码、天分组、调休合并/说明行/命中。
- **UI 冒烟 21 项**（390×844 手机视口）：feed 渲染（**头像头部/年月一行/若隐若现分割线**）/折叠/**下拉刷新头拖拽箭头**/**关键词搜索（正文/标签/无结果/还原）**/**评论展开（第三方随机头像 + 存量 HH:mm 补日期标准格式）**/日历/**跨月双休红显（outside weekend）**/回忆/我的页全行/发布流（标签 chips 点选）/TagChip/标签管理回归/**标签调色板改色（粉→0xFFFF2D55 断言）+ 心情管理列表**/**长按编辑**/**长按删除（二次确认）**/主题三档/**onboarding（12 宫格优先+随机生成+黄金向量提交）/401 横幅**/**ToastHost 3 项**。
- **显示配置 4 项**（`test/core/session/display_cfg_test.dart`）：标签库增删（初始含默认三项）+ KV 重载（'[]' 空库语义）、调色板覆盖/恢复自动/非法色名忽略、心情增删改（默认仅改显示）+ KV 重载、cfgVersion 自增。MemoryLocalStore 注入 + debugLoadCfg 钩子；静态表 setUp/tearDown 复位防污染。
- **光晕像素采样 2 项**（`test/features/glow_pixel_test.dart`；深色期望改为可见 Δ≥4 ≤48——用户覆盖原版 0.15）。
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
6. **注册名不可变更**：文案①「终身使用」——客户端无改名入口；如需改名需后端先定义语义（同名异钥已被拒绝，改名=数据空间迁移，涉及服务端）。

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
