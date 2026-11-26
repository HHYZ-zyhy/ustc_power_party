# 科大战力党 — 上下文交接文档（CONTEXT.md）

> 用途：切换模型 / 软件 / 设备时的唯一接手入口。读完本文件 + `DESIGN.md` 即可继续工作。
> **最后更新：2026-11-26（选骰 UI 第五轮微调）**
>
> 本轮无规则/数值改动：选中金边壳层 1.06→1.10；DiceTip 上提 16px（y664–692）；敌方骰块移出敌方信息条，放到框外名字正下方（Grid 5 列、第 6 颗换行、来源标题行右侧「总计 N」、与玩家骰共用同一 `display_rotation`/正交镜头/灯光/材质）。此前同日代码整理（`ButtonStyles` / `make_die_instance` / 骰行池化 / `_phase_passives`）与 3D 骰外观重做见 §5.3/§7。
>
> **最近节点**
> - 2026-11-26 第五轮 UI 微调：选中金边加粗、DiceTip 上提、敌方骰块外移并改 5 列 Grid（第 6 颗换行），无规则/数值改动。
> - 2026-11-26 3D 骰外观重做 + 同日第二轮（对手骰行移入信息栏，已于第五轮外移）+ 同日第四轮（选骰静态视图改为结果面朝玩家、18°/28° 上仰 + 正交镜头，取代 62° 顶面方案）。
> - 2026-11-25 方向调整（云存储暂停，稳定性→LAN→AI→美术）与稳定性两轮（测试骨架、幂等守卫）。
> - 2026-11-17 界面打磨三轮；更早见 `DESIGN.md` §10。
>
> 规则细节以 `DESIGN.md` 为准，数值以 `参考素材/角色，骰子参数.xlsx` 为准；本文件负责「背景、约定、架构、代码索引、进度、坑」。
> 只想知道「改某功能去哪个文件」→ 直接看 §5.1 代码索引；只想知道「别踩什么雷」→ §2 约定 + §8 坑。

## 1. 项目是什么

- 用户自研骰子对战游戏 **科大战力党**（Godot 4.7，GDScript），借鉴《崩坏：星穹铁道》「上骰了！战力党！」玩法，角色为科大院系。
- 1v1 攻防：双方按攻击/防御等级选骰，点数和比大小扣血，关键词（攻击等级/防御等级/连击/洞穿/反击/骇入/力场/荆棘/中毒/韧性/力量/不屈/跃升/瞬伤/虹吸/治愈/升级/命定）与角色被动、曜彩骰面效果叠加。
- v1 范围：单机 PVE（贪心 AI）、12 角色、11 曜彩骰、2D 界面 + 投骰、选骰与敌方骰子 3D。中期局域网 PVP、后期天气模块。
- **当前状态（2026-11-26）**：v1 全流程可玩（选卡 → 战斗 → 终局战绩页），验证链全绿；3D 投骰/选骰/敌方骰均为真骰型，重投有 1.3s 短版翻滚。
- 2026-11-26 完成代码整理轮与 3D 骰外观重做：共享按钮样式、骰体装配、骰行池化、阶段被动过滤；数字贴面、全不透明、精确正多面体、选骰静态视图「结果面朝玩家 + 18°/28° 上仰」（正交镜头 size 2.0）；同日第五轮把选中金边加粗（壳层 1.10）、DiceTip 上提、敌方骰块移到信息条框外名字正下方（96×132、Grid 5 列、第 6 颗换行）。待用户开窗确认视觉。
- 2026-11-25 完成稳定性两轮（测试骨架 + 同回合 API 幂等守卫）；当前优先级 **P1 稳定性（收尾）→ P2 局域网 1v1 → P3 AI → P4 美术**；AI 强化开工前仍需提醒用户。详见 §7 与 `DESIGN.md` §11。

## 2. 协作约定（必须遵守）

- **用户是设计师，拥有全部数值所有权**：`参考素材/角色，骰子参数.xlsx` 是数值唯一依据；改任何数值必须先列方案给用户批准，批准后同步改 xlsx 与 `gamedata.gd`。
- **不做平衡调整**：机制与数值对齐米哈游官方版本（用户 2026-10-11 确认），离群值仅记录不处理；sim（随机曜彩）定位为回归监控。已知离群（2026-11-11 复核）：信息 83.3%、核科学 75.0%、工程 76.5% 偏高，数学 14.4% 偏低（管理 67.4% 仍在历史区间；Crypto 无种子，逐次波动可达数个百分点；核科学经骰池对齐官方三月七后由 ~92-98% 回落）。
- **严格按用户指令执行**：用户给的命令/exe 名/流程照原样用；不要因自己探测失败就宣称工具不可用。
- **改完代码必须无头验证再汇报**（命令见 §6）；无法验证时要明说，不得暗示成功。
- **规则空白不擅自定**：遇到参考素材与文档都没定义的情形（例：被击倒方是否还触发「受到伤害」被动），先查 `DESIGN.md` §9 已定约定 / §10 决策日志；查不到就把方案与影响列给用户裁决，批准后改代码并回写 §9/§10。
- **外部结论一律复核**：第三方审计报告、网络抓取资料（如曾出现的《银河战力党-官方资料汇编.md》，用户明示可能有误、且已不在仓库）必须先对代码与 xlsx 核实再采信。2026-10-15 一份外部审计报告声称"已有裁决"，经查 DESIGN/keywords 无实据，按未定义规则重新报裁决。
- **git 由用户主导**：仓库已跟踪（分支以仓库当前状态为准，`.gitignore` 为 Godot 4 标准模板）；git 提交与仓库状态由用户全权负责，AI 不执行 git 操作、不跟踪不汇报 git 状态，也不擅自改 `.gitignore`（用户 2026-10-16 指示）。
- **xlsx 数值表**：默认只读（Python zipfile 解 XML）；确需写入时先取得用户批准并备份（历史上写 sheet2 B 列前已备份 `_xlsx/original-backup.xlsx`）。
- 用户反馈逐条落实，并追加记录到 `DESIGN.md` §10 决策日志 / §11 进度（用户要求所有意见与进度都进文档）。
- 用户用中文交流；交付物偏好：xlsx、截图、mp4 作为规格输入，需要真实解析（xlsx 用 Python zipfile 解 XML；截图用 Read 看图）。

## 3. 环境事实（Windows）

- Godot 4.7.2 在 PATH，**exe 全名** `Godot_v4.7.2-stable_win64.exe`（不要简写成 godot）。
- 新增 `class_name` 脚本后，先跑 `--headless --path game --import` 刷新全局类缓存，否则 `-s` 脚本解析报 "Identifier not declared"。
- `-s` 无头模式**不注册 autoload** → 跨场景状态用静态类 `GameStateData`，不用 autoload。
- Godot 4.7 的 Crypto 随机方法名是 `generate_random_bytes`（不是 get_random_bytes）；`CryptoRandomNumberGenerator` 类不存在于该构建。
- 随机数必须走 Crypto（用户公平性要求），`GameRng` 无种子通道。
- Excel 打开着 xlsx 时（存在 `~$...xlsx` 锁文件）替换文件报 WinError 5 → 先请用户关 Excel。
- Python 3.13 可用于 xlsx zip 内 XML 修改；ffmpeg 在 `D:\App files\ffmpeg-n8.1.2-win64-gpl-8.1\bin`（抽帧看视频/截图用）。

## 4. 权威资料清单（项目根 `D:\warrior party\`，与磁盘实际文件一一对应）

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | 跨工具智能体交接入口：任何 AI 编程工具打开本项目先读它，内含硬规则、命令速查、常见任务菜谱 |
| `CONTEXT.md` | 本文件 |
| `DESIGN.md` | **规则权威**：冻结规则全文 + §5.1 数据驱动合法取值 + §10 决策日志 + §11 进度待办（改规则先改它） |
| `README.md` | 目录结构说明：根目录、`参考素材/` 与 game/ 每个文件/文件夹的用途登记、维护约定 |
| `GODOT_GUIDE.md` | 本机 Godot 4.7.2 使用手册：启动方式、无头验证与期望输出、截图自检、临时探针规范、API 踩坑、排错表 |
| `参考素材/角色，骰子参数.xlsx` | **数值权威**：sheet1 角色属性（12 行）、sheet2 骰子属性（11 曜彩骰，B 列面表已录入）。默认只读 |
| `参考素材/科大战力党-构思.txt` | 用户原始构思（Godot、Crypto 随机、2D+投骰3D、贪心 PVE、中期局域网、后期天气） |
| `参考素材/原作截图/*.png` | 原作战斗界面截图 5 张（进攻方选骰子 / 进攻方使用曜彩骰时 / 防御时显示界面 / 未选中时显示可能的效果 / 选中时高亮显示获得效果）——布局、曜彩弹窗、防御展示与逐骰效果标注的对照依据 |
| `参考素材/效果/page1~4.jpg` | 官方关键词解释截图 15 条（游戏内共 18 条，另 3 条用户补充，全文见 DESIGN §3） |
| `参考素材/曜彩骰定义/*.jpg` | 11 张曜彩骰面表与使用条件截图，gamedata 面表录入依据；**文件名仍为旧曜彩名**（只读素材，用户决定不改），新名对照见 README |
| `LICENSE` | GNU GPL v3 |
| `.gitignore` | Godot 4 标准模板（`.godot/`、`*.exe`、导出产物、`*.tmp` 等）；**未忽略 Excel 锁文件 `~$*.xlsx`** |
| `game/` | Godot 4.7.2 工程（可执行内容全在这里），结构见 §5 |
| `_frames/` | scratch：原作录屏抽帧 `ex1_*.jpg`(8)/`ex2_*.jpg`(14)（**唯一动态参考，勿删**）、shot.gd 输出的 `shot_*.png`(6)（覆盖生成；含 `shot_dice_selected.png`）；历史探针图已清理（2026-10-24） |
| `_xlsx/` | scratch：**仅存 `original-backup.xlsx`**（写 B 列前的原表备份，永久保留，勿删）；解包产物与解析记录已清理（2026-10-24） |

> 已不在仓库但文档里可能还被提到的：`示例1.mp4` / `示例2.mp4`（原作参考录屏，已移除，仅存 `_frames/ex*_*.jpg` 抽帧）；`银河战力党-官方资料汇编.md`（网络抓取件，用户明示可能有误、非权威，xlsx 优先）。
> 出现 `参考素材/~$角色，骰子参数.xlsx` 表示用户 Excel 正开着该表：此时替换 xlsx 会报 WinError 5，且不要把它提交进 git。

## 5. 代码架构（`game/`）

```
game/
  project.godot            主场景 scenes/select.tscn；全局主题 theme.tres（默认字号32）；
                           [display] 基准 1920×1080 + canvas_items 拉伸 + aspect=expand
  theme.tres               全局 GUI 主题（解决字体过小）
  scripts/core/
    die.gd                 Die：sides/value/yaocai/face；升级链 d4→d6→d8→d12
    gamedata.gd            12 角色 + 11 曜彩骰面表/使用条件（纯数据，照 xlsx 录入；
                           intro 字段 = Excel 介绍原文，界面展示不得简写）
    game_rng.gd            GameRng：仅 Crypto.generate_random_bytes
    battle.gd              Battle：分步回合 API（见下）；结算时序与关键词实现（跃升/骇入先改点
                           再求和、并列目标随机取；地球「攻击后」在攻击结算后、中毒前生效，不参与本次伤害；
                           多来源连击按 combo_count 逐段结算；do_reroll 强制带命定骰并返回实际集合）；
                           damage()/heal() 对 HP≤0 目标返回并钳 HP≥0，
                           damage() 写 hits 逐笔掉血事件；KO 后所有效果停止（逐迭代/逐效果 winner 守卫）
    ai.gd                  AIController：枚举选骰贪心（_trigger_bonus 条件口径与 eval_cond 一致；
                           不屈一次性已用不再估值）；choose_reroll 返回勾选数组（核心层会补命定骰）
    driver.gd              Driver：同步编排（模拟用）run_round/run_game；攻方 commit 致死后跳过阵亡方防御阶段
    game_state.gd          GameStateData：静态变量 char_id/yc_name（跨场景）
  scripts/ui/
    select_ui.gd           选卡：1 角色 + 1 曜彩骰（化学禁曜彩）；1280px 内容列居中；信息栏显示骰池构成与 Excel 原文介绍；少年班按钮显示「攻?」；开始按钮金色启用态（ButtonStyles.apply_primary）
    button_styles.gd       ButtonStyles：选卡页/战斗页共用按钮样式（选中金边、推荐金字、禁用暗色、主操作金色启用态）
    battle_ui.gd           战斗界面：人类=玩家0 异步编排；布局分区见 battle.tscn；
                           命定自动锁定；升序排骰；选中即重投（可选任意颗至全部，重投有 3D 短版翻滚）；
                           结算分行显示；扣血闪红+飘字；效果文案中文映射；曜彩六面表弹窗
                           （开关式，不可用时按钮副行与弹窗内明示中文原因）；信息条名字右侧
                           攻/防等级角标与状态栏（荆棘待结算/力场/不屈/中毒/力量/跃升）；
                           选骰效果预览（已选触发金色汇总行＋逐骰点数下方金色效果标注，
                           少年班/计数类/与骰值无关条件不标注）；
                           确认按钮整合 已选/需选 计数；
                           敌方提交选骰后骰子网格只显示其所选骰 + 「总计 N」；
                           攻方选骰期间敌方行显示守方上回合投出的骰子；
                           曜彩骰按钮底部标注当前面技能（金色有技能/灰色无效果）；
                           曜彩六面表卡片（_make_face_cell，3×2 点数+效果，_fit_yc_popup 窄窗降列）；
                           双方 HP 进度条（#E9517D，refresh 同步）；
                           掉血反馈（_flush_hits/_damage_feedback，主伤害/连击/反击/瞬伤/荆棘/中毒统一闪红+飘字）；
                           骰型配色（4 天蓝/6 紫/8 橙/12 与曜彩近黑+蓝紫，3D 材质由 DieVisuals 统一生成）；
                           效果显示弹窗（glossary.gd，原关键词图鉴；效果名点击展开，
                           列表可滚动查看全部 18 条并高亮/定位到所点效果）；
                           终局战绩汇总页（伤害与触发统计，battle.gd stats 支撑）；
                           曜彩骰 3D 演出（_animate_yaocai，演出期间锁输入）；
                           攻/防等级徽章随 refresh() 更新（_refresh_badges/_def_level_shown）；
                           选骰界面 3D 化：候选骰/敌方骰为 DieView 对象池（_die_views/_enemy_views），
                           _obtain_view/_prune_views 统一创建/复用/清理，_sync_dice_row/_sync_enemy_row 按 Die 增量刷新、
                           不重建 SubViewport；_phase_passives 统一「当前阶段生效被动」过滤；
                           投骰/重投/曜彩演出期间隐藏对应骰行，避免静态骰提前露点
    glossary.gd            GlossaryPanel：效果显示弹窗（18 条定义照录 DESIGN §3 / GameData.KEYWORDS；
                           列表可滚动，打开时高亮并定位到所点效果，行可点击切换高亮；
                           _fit_to_viewport 窄窗按边距收窄）
    dice_roll.gd           投骰 3D 演出（SubViewport 透明背景，普通投骰约 2.3s、重投 quick 约 1.3s；
                           真骰型 d4 正四面体/d6 立方/d8 正八面体/d12 正十二面体 + 曜彩立方，
                           d6/曜彩用官方 BoxMesh，其余用精确正多面体 ArrayMesh；每个面挂贴面 Label3D，
                           翻滚后停在所掷点数面；镜头按骰数推近；
                           几何/材质/刻字/灯光直接复用 DieVisuals 的静态缓存，本文件只做演出编排）
    die_visuals.gd         3D 骰几何/材质/刻字/停骰姿态（DieVisuals 静态类，按骰型静态缓存；
                           骰体全不透明、数字贴面、d4 逐面预旋转刻字；make_die_instance() 统一装配网格+逐面刻字；
                           dice_roll 与选中态静态骰共用同一套骰体）
    die_view.gd            DieView：单个骰子的静态 3D 视图（上部无边框 Button 内嵌 SubViewportContainer
                           与小 SubViewport（own_world_3d/透明/UPDATE_ONCE）+ 下部效果提示）；
                           选中金色/命定粉色不透明反壳描边（CULL_FRONT，无 additive 发光），悬停轻微放大；
                           静态视图结果面正对镜头，绕屏幕水平轴 18° 上仰（d4/d8 三角面 28°），正交镜头 size 2.0，露出底面/侧面；普通 cell 128×150，敌方 cell 96×132（带提示）
  scenes/select.tscn, battle.tscn
  tests/
    sim.gd                 792 局 AI vs AI 回归监控模拟（随机曜彩）
    keywords.gd            关键词级断言测试：无 RNG 摆定骰面直接断言结算数值
                           （36 组场景 1206 断言，改核心结算必跑，应 pass=1206 fail=0）
    ui_play.gd             无头假人：走人类 UI 全路径（含重投、曜彩使用）
    ui_smoke.gd            场景实例化冒烟 + 效果显示/推荐曜彩/HP 条/窄窗弹窗/效果名中文映射/预期效果连击×N 断言
                           + DiceRow 结构（点选切换/池化 id/命定锁定/逐骰提示精确性/敌方 96×132/敌方标题（含上回合）与总计/
                           选骰提示/确认按钮启用/状态栏独立行/战绩遮罩/布局 offset）（30 帧后检查）
    shot.gd                布局截图自检（开窗跑，输出 _frames/shot_*.png 六张：选卡/战斗/选中骰/曜彩弹窗/效果显示/战绩页；
                           等到人类首个可操作阶段（进攻或防御）直接截选中态；若人类首次操作前已分胜负则换一局；
                           战绩页由脚本自动打完真实对局后截图，不是手工摆数据）
    debug1.gd              单局日志调试
```

**战斗界面布局（1080p 坐标，参照原作截图定稿）**：敌方信息条 x360 起、y16 起（左右 20/上下 8px 内边距；名字/HP 文本/HP 进度条/曜彩行 → 被动 → 状态，只按内容收紧，不再包骰块）→ 敌方骰块在框外、名字正下方 x380（cell 96×132 = 3D 96×96 + 36px/13px 提示、不可点击；Grid 5 列、第 6 颗换行；来源标题行右侧「总计 N」；块宽上限 884，不越过居中横幅文字）→ 横幅 y252–312 / 预期效果 y318–368（居中）→ 结算 Big y380–560 → 回合数左中 → 投骰演出 RollView y380–680 居中透明 → 选骰提示 DiceTip y664–692（点击选择/取消 + 已选/需选，已上提避免贴骰顶）→ 骰子候选 DiceRow x±700、y720–870、separation 16（cell 128×150 = 上部 128×108 无边框 Button 内 3D 渲染区 + 下部 42px、16px 字号效果提示）→ 日志 LogLine y872–910 → 玩家信息条 y910–1064（左右 20/上下 8px 内边距；名字/HP/曜彩行 → 被动 → 状态独立行，被动/状态 22px）→ 操作按钮右列固定 260px、x1620–1880、y560–1040（重投/曜彩长文案强制双行，避免按钮文本撑宽 VBox 向左扩展压住玩家信息栏；确认按已选/需选数启用）→ 曜彩弹窗右上 x1300–1880、y100–600（580×500，六面卡片 3×2；窄视口按 40px 边距收窄并降列）。效果显示基准 1000×820 居中、战绩面板 1040 宽×内容高度（300~520）居中（SummaryView 全屏 65% 黑色遮罩 + 不透明面板），窄视口均按边距收窄。选卡页为 1280px 内容列居中（CenterContainer；CharScroll 固定最小高 330，角色 4 列、曜彩 6 列）。**约束：每颗骰的 SubViewport 尺寸 = cell 渲染区（普通 128×108、敌方 96×96），改 cell 尺寸必须同步 SubViewport 与镜头，否则骰子被裁切或过小。**

**Battle 分步 API（回合编排顺序，用户指定）**：
`round_open()`（清 sel、攻方重投=2，不投骰）→ 每方阶段：`roll_phase(idx)` → 可选 `roll_yaocai(idx,phase)` → 攻方可 `do_reroll(idx, dice数组)` ×2（返回实际重投集合；命定骰会被强制加入）→ `commit_selection(idx,phase,sel)`（确认即锁定）→ 双方完成后 `settle()` → `round_close()`。
结算时序：瞬伤立即 → 结算开始荆棘 → 主伤害/连击/洞穿/反击 → 攻击后被动（地球力量设置/治愈，不参与本次伤害）→ 回合结算后中毒；每次扣血即查 HP，无平局。

### 5.1 代码索引（要改 X 去哪个函数）

> `core/` = `game/scripts/core/`，`ui/` = `game/scripts/ui/`。行号会变，故只给函数名（用 Grep 定位）。

| 想改 / 想查 | 位置 |
|---|---|
| 角色数值、被动、曜彩面表、关键词文本 | `core/gamedata.gd`（`CHARACTERS` / `YAOCAI` / `KEYWORDS`）；数值须先看 xlsx 与 DESIGN §4/§6 |
| 被动条件判定 | `core/battle.gd eval_cond()`（static 纯函数；AI `_trigger_bonus`、界面预期效果/逐骰提示都必须复用它；合法 `c.t` 见 DESIGN §5.1） |
| 被动 / 曜彩面效果执行 | `core/battle.gd apply_fx()`（合法 `fx.op` 见 DESIGN §5.1） |
| 攻/防等级与上限 | `battle.gd atk_eff() / def_eff() / selection_count() / pool_count()`；`atk_set`（工程）优先于 `atk_perm`，一律按普通骰数封顶 |
| 一回合的结算流程 | `battle.gd settle()`（顺序注释在函数上方）；改骰点的 `_apply_leap()` / `_apply_hacks()` 必须在求和之前，且受 `winner < 0` 守卫；地球「攻击后」在主伤害/连击/反击之后、中毒之前评估（`_ctx_a.atk_value` 已更新为最终攻击值） |
| 「受到伤害」被动 | `battle.gd _eval_on_damaged()`——仅 settle 的主伤害/每段连击后调用，均有 `winner < 0` 守卫 |
| 扣血 / 治疗 / 胜负判定 / 逐笔掉血事件 | `battle.gd damage()`（HP≤0 直接返回；钳 HP≥0、设 winner、写 stats（实际扣血）、向 `hits` 记 `{target, amount, kind}`，返回实际扣血）/ `heal()`（HP≤0 不复活）；`amount` 为扣血前后差值（不屈时与名义伤害不同） |
| 掉血飘字 / 闪红 / HP 进度条 | `battle_ui.gd _flush_hits() / _damage_feedback()`（在 `refresh()` 末尾消费 `battle.hits` 新增事件，按 target 叠放）；HP 条节点 `%EnemyHpBar/%PlayerHpBar`，样式 `_style_hp_bar()`，数值随 `refresh()` 同步 |
| 弹窗尺寸自适应 | `glossary.gd _fit_to_viewport()`（效果显示 1000×820 居中）、`battle_ui.gd _fit_yc_popup()`（曜彩 580×500 右缘 40，窄窗 3→2→1 列）与 `_fit_sum_panel()`（战绩 1040 宽×内容高度 300~520 居中）；均接视口 `size_changed` |
| 曜彩可用性与中文原因 | `battle.gd yaocai_usable()` / `yaocai_reason()`（两者口径必须严格一致，keywords 有一致性断言） |
| 重投 / 命定锁定 | `battle.gd do_reroll()`（返回实际重投集合，命定骰强制加入）/ `is_mingding()` / `_enforce_mingding()`；人类/AI 重投动画必须用 `do_reroll()` 的返回值 |
| 结算横幅注记 | `battle_ui.gd _settle_notes()`（防御阶段跳过/commit 已分胜负/结算中 KO/力场/多段连击），由 `_round_ui()` 组装 |
| 回合收尾（buff 到期、曜彩消失、攻守互换、`round += 1`） | `battle.gd round_close()` |
| 战绩统计口径 | `battle.gd stats`（`dmg_dealt` / `dmg_taken` / `fx`），由 damage / apply_fx / roll_yaocai / do_reroll 写入；伤害按实际扣血累计（2026-11-10 起，与 hits/飘字/战绩统计同口径） |
| AI 选骰 / 重投 / 曜彩 | `core/ai.gd choose_selection() / choose_reroll() / choose_yaocai()`，组合枚举 `_combos() / combinations()`，被动估值 `_trigger_bonus()` 直接调用 `Battle.eval_cond()`（唯一条件实现）；只接收己方 `p` |
| 无头对局编排（sim 用） | `core/driver.gd run_round() / run_game()`（80 回合上限按 HP 判定） |
| 人类对局编排（异步） | `ui/battle_ui.gd _run() → _round_ui() → _phase_ui() / _ai_phase() / _human_phase()` |
| 界面中文文案（效果名/日志） | `battle_ui.gd _fx_text() / _fx_name() / _fx_list_text() / _log_text()` |
| 逐骰效果标注、预期效果汇总行 | `battle_ui.gd _phase_passives() / _die_fx_hints() / _refresh_preview()`：`_phase_passives` 统一「当前阶段生效被动」过滤；前者用 `AIController.combinations()` 穷举刚好 need 颗且含命定骰的选择、用 `Battle.eval_cond()` 判定；后者用实际 `_sel` 调用同一条件函数；提示渲染在 `DieView` 骰下的 RichTextLabel |
| 信息条徽章与状态栏 | `battle_ui.gd _add_stat_badges() / _refresh_badges() / _atk_badge_text() / _def_level_shown() / _status_text()`；状态栏是信息条 VBox 的独立第三行，不要塞回横向 Row；信息栏内边距由 `_pad_info_bar()` 统一设置 |
| 终局战绩页 | `battle_ui.gd _show_summary() / _summary_text()`（总回合数用 `battle.round - 1`，因 round_close 无条件 +1）；`shot.gd` 的战绩截图来自自动打完的真实对局 |
| 按钮样式（选中/推荐/禁用/主操作） | `ui/button_styles.gd` `ButtonStyles`：`apply()` 次级按钮、`apply_primary()` 主操作按钮；选卡页/战斗页共用，不要再各写一份样式函数 |
| 单个骰子的外观/选中态（cell、描边、悬停、提示） | `ui/die_view.gd` DieView：上部无边框 Button + SubViewportContainer（普通 128×150、敌方 96×132）；金色/命定粉色不透明反壳描边（CULL_FRONT，无 additive 发光）；`set_die()` 仅在骰面/选中/锁定变化时 `arm_render` |
| 3D 骰几何/材质/刻字/停骰姿态/灯光 | `ui/die_visuals.gd` DieVisuals（静态缓存；`make_die_instance()` 统一装配网格+逐面刻字；`dice_roll` 演出与静态选骰共用同一套骰体；`add_lighting()` 统一方向光/环境光） |
| 静态选骰正视姿态 | `ui/die_visuals.gd display_rotation() / _triangle_top_yaw() / align_display_labels()` + `ui/die_view.gd CAM_NORMAL`：结果面朝镜头、绕屏幕水平轴 18° 上仰（d4/d8 三角面 28°），正交镜头 size 2.0；投骰演出仍用 `_rest_rotation()` 的物理停姿，两者不要混用 |
| 选骰行刷新（池化/增量） | `battle_ui.gd _obtain_view() / _prune_views() / _sync_dice_row() / _sync_enemy_row()` + `_die_views` / `_enemy_views`（按 Die 对象池化，不重建 SubViewport；创建/清理只走前两个助手）；敌方标题/总计也在 `_sync_enemy_row` 维护 |
| 3D 投骰演出 | `ui/dice_roll.gd roll(dice_a, dice_b, quick=false)`（quick 为重投短版）；人类/AI 重投走 `battle_ui._animate_roll(picks, idx, true)`，曜彩演出走 `battle_ui._animate_yaocai()` |
| 效果显示（原关键词图鉴） | `ui/glossary.gd`（`GlossaryPanel.kw_bbcode()` 把任意文本里的效果词变成可点击链接；`open(kw)` 高亮并滚动到该效果，列表行可点击切换；`_fit_to_viewport()` 窄窗收窄） |
| 曜彩六面表 / 使用条件 | `battle_ui.gd _on_yc() / _make_face_cell() / _fit_yc_popup()`；可用性判定 `battle.gd yaocai_usable() / yaocai_reason()` |
| 选卡界面 | `ui/select_ui.gd`（初始空选/选角自动带推荐/上局恢复 `_ready()/_on_char()/_can_start()`；骰池文案 `_pool_text()`、少年班「攻?」`_atk_text()`、推荐曜彩 `_reco_line()/_refresh_yc()`、化学禁曜彩、主按钮 `ButtonStyles.apply_primary()`） |
| 跨场景传参 | `core/game_state.gd GameStateData.char_id / yc_name`（静态类，不用 autoload） |
| 随机数 | `core/game_rng.gd GameRng.randi_range() / coin_flip()`（仅 Crypto，无种子通道） |
| 骰子与升级链 | `core/die.gd`（`CHAIN` / `upgrade()` / `is_yaocai()`） |

### 5.2 玩家状态字段词典（`battle.gd _make_player()` 返回的 Dictionary）

改核心逻辑前先查这张表，字段互相牵连（尤其 pending → round 的转换时机）。

> `Battle.hits`（Battle 级字段，不在 player 字典里）：逐次掉血事件 `{target, amount, kind}`，由 `damage()` 唯一写入；`kind` = main/combo/counter/instant/thorns/poison，`amount` = 实际扣血。仅供界面反馈与测试，不影响结算；`battle_ui` 用 `_hit_seen` 记录消费位置，避免重复飘字。

| 字段 | 含义与生命周期 |
|---|---|
| `cfg` `hp` `hp_max` `dice` | 角色配置引用、当前/上限 HP、本回合实际存在的骰（常规 5 颗 + 已投出的曜彩） |
| `atk_perm` `def_perm` | 永久等级加成（AI 学院受伤≥8 双 +1、数学洞穿 +1），经 `atk_eff`/`def_eff` 按普通骰数封顶 |
| `atk_set` | 攻击等级**覆盖**值（工程触发后置 5）；`>=0` 时优先于 `cfg.atk + atk_perm` |
| `def_pending` `counter_pending` | 「下次防御」类临时效果（网安 防御等级+3 与反击）；防御 `commit_selection` 时 `counter_pending → counter_round`、`def_pending` 清零 |
| `counter_round` | 本回合反击生效标志，settle 末尾按 `def_value > atk_value` 判定差值回打；带洞穿的攻击不触发（`not summary.pierce`，2026-11-10） |
| `strength` | 力量层数组 `[{n, expire}]`：`expire = round+1` 为下回合到期（理实积淀），`-1` 为永久（地空）；`round_close` 清理 |
| `toughness` | 韧性层数，计入防御值；**当前无授予通道**（见 DESIGN §5.2） |
| `thorns` | 荆棘层数，结算开始扣自身血后清零（通宵鏖战加给自身）；一方 KO 后不再结算、层数保留 |
| `poison` | 中毒层数，结算后扣血并 -1（一方 KO 后不再结算）；**当前无授予通道** |
| `field` `unyielding_round` `unyielding_used` | 力场（挡非洞穿的主伤害与连击、洞穿可破）、本回合不屈、不屈是否已用（生命学院仅 1 次）；前两者 `round_close` 清除 |
| `leap_perm` `leap_round` | 永久跃升（管理/工程）→ `round_open` 复制到 `leap_round`，`settle` 前对攻守各触发一次 |
| `hack_pending` | 待结算骇入（信息学院被动 / 网络渗透面），由 `_apply_hacks()` 消费；全 1 时把其中一颗 1 抬到 2（用户 2026-11-10 裁决） |
| `yc_name` `yc_uses` `yc_rolled` `yc_triggered` | 携带曜彩名、整局剩余次数、本回合是否已投、已触发面效果次数（管理被动计数用） |
| `accum` | 自身历回合攻击值+防御值累加（工程 `accum_ge` 条件），`round_close` 累加 |
| `face_counts` | `{1: n, 4: n}`——选定过的 1 点 / 4 点累计次数（顶刊论文 / 重复试验解锁条件），`commit_selection` 写入 |
| `sel` `rerolls` `rolled` | 本阶段已锁定的选骰数组、本回合剩余重投次数（`round_open` 给攻方置 2）、本回合是否已 `roll_phase`（防止重复投掷改写点数）；三者在 `round_open` 重置，`commit_selection` 后 `sel` 非空即视为已提交 |

### 5.3 代码审查入口（2026-11-12 / 2026-11-26 整理轮）

**2026-11-26 代码整理轮（只去重/改文档，无规则/数值改动）**：

| 关注点 | 位置 | 应有结果 |
|---|---|---|
| 按钮样式只有一套 | `ui/button_styles.gd` | `select_ui`/`battle_ui` 都调 `ButtonStyles`；不应再有 `_make_btn_style`/`_style_primary` 副本 |
| 骰体装配只有一套 | `ui/die_visuals.gd make_die_instance()` | `die_view`/`dice_roll` 都调它；不应各自写 mesh+label 循环 |
| 骰行池化只有一套 | `battle_ui._obtain_view()/_prune_views()` | `_sync_dice_row`/`_sync_enemy_row` 复用；不应重复创建/清理视图 |
| 阶段被动过滤只有一套 | `battle_ui._phase_passives()` | `_refresh_preview`/`_die_fx_hints` 共用 |
| 静态选骰姿态 | `DieVisuals.display_rotation()` + `DieView.CAM_NORMAL` | 结果面朝镜头、18°/28° 上仰；`dice_roll` 仍用 `_rest_rotation()` |

**2026-11-12 代码整理轮**：本轮只做代码去重、bug 修复与界面可读性，未改任何数值/规则/xlsx。涉及文件：`core/battle.gd`、`core/ai.gd`、`core/gamedata.gd`、`ui/battle_ui.gd`、`ui/die_view.gd`、`ui/die_visuals.gd`、`ui/dice_roll.gd`、`ui/glossary.gd`、`ui/select_ui.gd`、`scenes/battle.tscn`、`tests/ui_smoke.gd`、`tests/shot.gd`、`tests/sim.gd`。建议按下面顺序抽查；表中「应有结果」可直接用 Grep/测试核对。

| 关注点 | 位置 | 应有结果 |
|---|---|---|
| 条件判定是否只有一套 | `core/battle.gd eval_cond()`（static） | AI `_trigger_bonus`、界面 `_refresh_preview`/`_die_fx_hints` 全部调用它；不应再有手写条件 `match` 副本 |
| 求和/对子/骰池计数 | `battle.gd dice_sum()/pairs_count()/pool_count()` | 结算/AI/界面共用；除 AI 构建 values 外不应散落 `sum +=` 循环 |
| 3D 骰外观是否共用 | `ui/die_visuals.gd`、`ui/dice_roll.gd`、`ui/die_view.gd` | 几何/刻字/网格/材质/灯光集中在 `DieVisuals`；`dice_roll` 无 `_faces_for` 等转发包装；Grep `roller._faces_for` 应为空 |
| 逐骰提示是否精确 | `battle_ui._die_fx_hints()` + `AIController.combinations()` | 穷举「刚好 need 颗且含全部命定骰」的选择后调用 `Battle.eval_cond`；`ui_smoke` 有网安 `sum_ge` + 命运签约的误报回归断言 |
| 小视口是否只在必要时重渲染 | `die_view.set_die()/set_selected()/set_locked()` | 骰面/选中/锁定变化才 `arm_render`；`refresh()` 不应无条件重渲染全部骰 |
| 重投权限 | `battle.gd round_open()/do_reroll()` | 每回合双方 `rerolls` 先清零，再给攻方 2；防守方（含残留次数）与 KO 后 `do_reroll()` 均返回 `[]`；keywords 有对应断言 |
| 回合结束/新回合状态 | `battle.gd round_close()` + `battle_ui._round_ui()` | `round_end` 被动逐被动/逐效果受 `winner` 守卫；新回合先清 UI `_sel`、攻方重投次数=2、`yc_rolled/field/unyielding/leap_round` 等按 `round_close` 清理 |
| 人类操作状态 | `battle_ui.refresh()/_on_confirm()/_on_die()` | 选够才启用确认；`DiceTip` 显示选择/取消与已选/需选；命定骰锁定不可取消；重投/曜彩演出期间锁输入 |
| 敌方骰展示边界 | `battle_ui.refresh()/_sync_enemy_row()` | 第 1 回合未投前为空；之后标题为「敌方骰子/敌方上回合/敌方所选」；`en.sel` 中已移除的曜彩骰不得计入「总计」 |
| 信息条布局 | `battle.tscn` 的 `EnemyStatus/PlayerStatus` | 状态是 VBox 第三行，不是名字/HP 横排里的子项；长状态不挤 HP 条（`shot.gd` 可目检） |
| 战绩页可读性 | `battle.tscn SummaryView` + `battle_ui._show_summary()` | 全屏 65% 黑遮罩 + 不透明面板，战斗文字不透出 |
| 截图工具稳定性 | `tests/shot.gd` | 等人类首个可操作阶段（进攻或防御）直接截图；首次操作前分胜负会换一局（最多 4 次） |
| 全链验证 | `keywords/sim/ui_play/ui_smoke/shot` | `pass=1206 fail=0`；sim 12 行无 `Out of bounds`；`UI PLAY DONE`；`UI SMOKE OK`；shot 六图更新 |

**审查时不必再报的既有设计取舍**：敌方缩小骰不可点击（光标箭头）、第 1 回合后显示敌方上回合骰、骰下提示玩家 42px（16px 字号）/敌方 36px（13px 字号）、确认按钮选够才可点、战绩页遮罩、`shot.gd` 抓不到投骰翻滚瞬间；P3 AI 的 `choose_reroll` 超池/少年班子集上限/`sum_ge` 估值等是已记录缺口（DESIGN §11），不是本轮回归。

## 6. 运行与验证命令（含期望输出与实测耗时）

```bash
cd "D:/warrior party/game"
Godot_v4.7.2-stable_win64.exe --headless --path . --import          # 新增 class_name 后必跑（数十秒，无关键输出）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/keywords.gd  # 期望 KEYWORDS pass=1206 fail=0（<1s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/sim.gd       # 期望 12 行胜率表、stderr 无 Out of bounds（约 1-2s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_play.gd   # 期望 UI PLAY DONE winner=N round=N（约 1 分钟，逐帧驱动）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_smoke.gd  # 期望 UI SMOKE OK（<1s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/soak.gd      # 期望 SOAK OK games=2000 fails=0（约 5-15s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/fuzz_actions.gd # 期望 FUZZ OK steps≥20000（默认 valid；invalid 模式另测）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/ui_stress.gd    # 压力测试（开窗；默认 30 局 + 100 次往返；加 --headless -- --mode=lifecycle 只跑生命周期）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/shot.gd          # 布局截图自检（开窗，非 headless；无 stdout，看 _frames/shot_*.png）
Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"        # 开窗游玩（最终视觉确认靠用户）
```

- 标准流程：改代码 → （新增 class_name 才 import）→ keywords + sim + ui_play（+ ui_smoke）→ 稳定性阶段加跑 soak + fuzz（+ ui_stress）→ 改布局/字号/演出加跑 shot.gd 并 Read 六张图核对 → 汇报并提醒用户开窗确认视觉。
- **不要给这些命令追加 Unix 管道/重定向**（`| tail`、`2>/dev/null` 等）：部分环境的 Bash 工具实为 cmd.exe，会报 "'tail' 不是内部或外部命令"。要看完整输出就整条直跑。
- 控制台打印中文可能乱码（GBK 控制台）：需要读大段中文输出时，让脚本写 UTF-8 文件再用 Read 看。
- keywords/sim 的期望值会随改动变化（断言数、胜率）；改动后把新数字回写到文档（本文件 §7、DESIGN §11、AGENTS、README、GODOT_GUIDE 五处）。

## 7. 当前进度（2026-11-26）

- 核心：v1 单机 PVE 全流程可玩；battle.gd 分步 API + 结算时序（KO 后停止、地球攻击后、连击叠加、命定锁定/重投必带）；12 角色/11 曜彩；Crypto。
- 测试：keywords 36 组 1206（`pass=1206 fail=0`）；sim 792 局；ui_play；ui_smoke；shot 六图（含人类可操作阶段选中态 `shot_dice_selected.png`）；2026-11-25 新增 soak（2000 局）/ fuzz_actions（2 万步 valid）/ ui_stress（完整 UI 对局 + 场景往返 + 泄漏检查），基线全绿。
- UI：选卡（空选/推荐曜彩/保留选择）、战斗布局、曜彩六面表、HP 条+掉血飘字、效果显示、窄窗自适应、战绩页（已删折线图）、3D 真骰+重投短动画、选骰界面 3D 化（双方候选骰/敌骰为静态 3D 骰、描边选中、骰下提示；敌方骰行/骰块为玩家行的 96×132 缩小版+提示/总计，2026-11-26 第五轮移到信息条框外名字正下方）；选骰提示、状态栏独立行、确认按已选/需选启用、预期效果居中（2026-11-12 打磨）；2026-11-17 三轮界面打磨（首轮：选卡页选中态金色描边、战绩面板按内容自适应、曜彩弹窗全屏遮罩+点外部关闭、曜彩区滚动条修复；第二轮：选卡页 1280px 居中、主操作按钮金色启用态、选满提示/确认变金、日志「战报｜」前缀、战绩三列表格、Esc 关闭弹窗；第三轮：双方信息栏 20/8px 内边距、按钮长文案双行化使按钮列固定 260px、修复信息栏与确认按钮重叠、日志/玩家条上移修复长被动越出屏幕下缘）；2026-11-26 第五轮：选中金边加粗、DiceTip 上提、敌方骰块移到信息条框外名字正下方（Grid 5 列、第 6 颗换行）。
- 2026-11-26 代码整理轮：新增 `ui/button_styles.gd`（选卡/战斗共用按钮样式）；`DieVisuals.make_die_instance()` 共用骰体+刻字装配；`battle_ui._obtain_view()/_prune_views()` 共用玩家/敌方骰行池化；`_phase_passives()` 共用阶段被动过滤；`DieVisuals._cube_faces()` 合并立方骰面表。验证：keywords 1206、sim 12 行、ui_play DONE、ui_smoke OK、soak 2000 局 0 失败、fuzz 20003 步 0 失败、ui_stress 30 局 + 100 次往返 290 项 0 失败 0 泄漏；shot 六图重跑并目检（无布局回归）；无规则/数值改动。
- 文档：五份文档持续同步；规则见 DESIGN §9、决策日志 §10、待办分级 §11。
- 2026-11-25 方向调整：云服务/战绩存储暂停（`server/` 原样保留，不删除、不继续投入）；优先级改为 **稳定性 → 局域网 1v1 → AI → 美术**。阶段 0 文档已重排；阶段 1 先建 `soak.gd` / `fuzz_actions.gd` / `ui_stress.gd` 再修 P0；LAN v1 已确认自动发现 + 手动 IP 兜底、昵称、会话胜负统计、再来一局。
- 2026-11-25 稳定性第一轮：三份测试已落地；`battle.gd` 入口/索引/归属/幂等守卫、`battle_ui` 异步生命周期（`_wait` 帧驱动、投骰看门狗、人类阶段轮询、输入锁恢复）、`GameStateData.sanitize`、`select_ui` 防重入、`dice_roll` 重入令牌已完成。验证：keywords 1193、sim 12 行、soak 2000 局 0 失败、fuzz 5 万步 0 失败、fuzz invalid 60 步 0 脚本错误、ui_play/ui_smoke 绿；ui_stress 30 局 + 100 往返 0 失败 0 泄漏；shot 六图复核通过。
- 2026-11-26 3D 骰外观重做：数字贴面（法线外 0.0015、单面/深度测试）、骰体全不透明、d6/曜彩用 `BoxMesh`、d4/d8/d12 用精确正多面体 `ArrayMesh`、选中/命定 `CULL_FRONT` 不透明反壳描边、d4 逐面刻字扶正。同日第二轮：敌方骰行改为玩家骰行的 96×132 缩小版（带提示、不可点击、总计）；同日第四轮按参考截图改为选骰静态视图「结果面朝玩家 + 18°/28° 上仰」（正交镜头 size 2.0，取代 62° 顶面方案）。同日第五轮：选中金边壳层 1.06→1.10、DiceTip 上提 16px 到 y664–692、敌方骰块移出敌方信息条并放到框外名字正下方（Grid 5 列、第 6 颗换行、总计在来源标题行右侧）。验证：keywords 1206、sim 12 行、ui_play DONE、ui_smoke OK、ui_stress 30 局 + 100 次往返 290 项 0 失败 0 泄漏、shot 六图目检通过；无规则/数值改动。
- 2026-11-25 稳定性复查（第二轮）：同回合 API 幂等收紧——`commit_selection` 重复提交、`roll_phase` 重复投掷、提交后 `do_reroll`/`roll_yaocai` 全部拒绝（防双击/网络重放二次触发瞬伤、治愈、被动）；`round_close` 要求先 `settle`；新增玩家字段 `rolled`；`apply_fx` 对最小上下文缺键容错；`settle/round_close/round_open` 增加 attacker 守卫。测试：`keywords` 新增 `_t_api_guards`（36 组 1206）并把 `_t_field/_t_heal/_t_strength` 改为一次提交到位；`fuzz invalid` 增加确定性守卫用例；soak/fuzz 检查 `setup` 返回值与参数合法性；`ui_play` 超时改为退出码 1；`ui_stress` 首帧校验 Battle 初始化与收尾强制泄漏比较；`shot` 未到战绩页判失败。验证：keywords 1206、sim 12 行、soak 2000 局 0 失败、fuzz valid 5 万步 0 失败、fuzz invalid 60 步 0 失败、ui_play DONE、ui_smoke OK、ui_stress 30 局 + 100 往返 290 项 0 失败 0 泄漏、shot 六图复核通过。详见 DESIGN §10 同日条。

关键节点（详细裁决见 DESIGN §9/§10）：
- 2026-10-11：骇入失效修复；keywords 测试上线；平衡冻结。
- 2026-10-13：等级上限=普通骰数；受伤被动仅防御正式结算逐次且 KO 后不触发；审计五处。
- 2026-10-14~17：战绩页/效果显示/配色；核科学池对齐+11 曜彩改名；跃升先于骇入；KO 后效果停止；KO 守卫补齐。
- 2026-10-24~27：参考素材归位；效果显示改版；选卡流程/曜彩六面表/HP 条/窄窗；数据服务器暂缓（只存场次/胜场）。
- 2026-11-10：统计/横幅改实际掉血；洞穿无视防御/不触发反击；骇入全 1 抬一颗。
- 2026-11-11：3D 真骰+重投动画；KO 边界；地球攻击后；命定可重投/不可取消/重投必带；多来源连击叠加；删 HP 折线图；本轮复核（AI 不屈估值、横幅注记、升级口径/attack_after 文档修正）。
- 2026-11-12：用户裁决升级不重投、只改骰子类型保留点数（关闭 11-11 遗留疑问，代码/断言原本已一致，仅文档定案）；选骰界面 3D 化（用户「不要方框，直接选择立体的骰子」：DieView/DieVisuals、双方静态 3D 骰、描边选中、骰下提示、敌方左上 3 列网格、shot 六图；后于 2026-11-26 改为 96×132 缩小行，第五轮再移到信息条框外名字正下方）；代码去重与逐骰提示精确化（统一 `Battle.eval_cond`/静态计数、命定强制入选纳入提示穷举）、界面易读性（选骰提示/敌方骰来源标题/状态栏独立行/确认按数量启用）。
- 2026-11-17：P1 界面打磨首轮（选卡页选中态金色描边/文字色、战绩面板按内容自适应高度、曜彩弹窗全屏遮罩+点外部关闭、曜彩区滚动条修复；验证链全绿；详见 DESIGN §10 同日条）。
- 2026-11-17（第二轮）：P1 可读性与易操作性（选卡页 1280px 居中、主操作按钮金色启用态、选满提示/确认变金、日志「战报｜」前缀、战绩三列表格、Esc 关闭弹窗；验证链全绿；详见 DESIGN §10 同日第二轮条）。
- 2026-11-26：3D 骰外观重做（数字贴面、骰体全不透明、d6/曜彩 BoxMesh + d4/d8/d12 精确正多面体、CULL_FRONT 不透明反壳描边、d4 刻字扶正）；同日第二轮：敌方骰行改为 96×132 缩小版（提示、总计）；同日第四轮：选骰静态视图改为结果面朝玩家 + 18°/28° 上仰（正交镜头 size 2.0），取代 62° 顶面方案；同日第五轮：选中金边加粗（1.10）、DiceTip 上提、敌方骰块外移到名字正下方（Grid 5 列）；验证链全绿；详见 DESIGN §10 同日条。

## 8. 踩过的坑（避免重犯）

- GDScript 字典值用 `.get()` 防缺键；`var x := dict.field` 会因 Variant 推断失败，需显式类型。
- SceneTree 测试脚本的 assert/运行时错误会中断 `_init`，后面的 `quit(0)` 不会执行，进程会挂住（ui_smoke/ui_play 均踩过）；报错后手动结束 Godot 进程。
- **新测试不要用 `assert`**：release 构建会剥离断言，且 `ui_smoke` 历史上失败时 `quit(0)` 可能执行不到；稳定性测试统一 `_check` 计数 + `quit(1)`。
- **`SceneTreeTimer` 不属于场景**：旧版 `battle_ui._wait()` 用它，场景切换后计时器仍会 timeout，协程可能在已释放节点上恢复；现改为帧驱动（`await process_frame` + `get_process_delta_time()`，每轮检查 `is_inside_tree()`），`dice_roll` 的演出计时也有 token 守卫。
- **`Battle` 公共入口的守卫（2026-11-25）**：`setup` 校验数据并返回 bool；`roll_phase/do_reroll/commit_selection/roll_yaocai/settle/round_close` 均有索引、阶段、骰归属、KO、每回合幂等守卫；合法路径行为不变。新增入口照此办理，先用 fuzz invalid 打一遍再补合法链回归。
- **异步流程必须在每个 await 后检查 `is_inside_tree()`/token**：2026-11-25 已给 `battle_ui` 主协程、投骰看门狗、`dice_roll` 加重入/存活守卫，但新增 await 点仍要自己检查，不能假设节点还活着（`game/scripts` 现有关键入口用 `push_error`/`is_inside_tree`，不用 assert）。
- **浸泡测试复现不靠种子**：`GameRng` 是 Crypto、无种子且禁止加；失败时记录双方角色/曜彩、动作序列与掷骰结果/快照，用回放复现，不要给 `game_rng.gd` 加 seed。
- **LAN 视图置换**：现有 `battle_ui` 把“玩家 0 = 我”写死；客机不要逐处改 0，而是让网络层把快照按本地玩家重排（自己永远在 0 号位），动作再映射回真实 idx。
- **`_ctx_a/_ctx_d` 不能是空字典**：`settle()` 在未 commit 的异常路径会读 `_ctx_a.flags`；`setup/round_open` 统一用 `_empty_ctx()`（含 flags/sel/values/atk_value/bonus/face_points），否则 fuzz 的“未 commit 就 settle”会脚本报错。
- **同回合 API 幂等（2026-11-25 复查）**：`commit_selection` 用 `p.sel` 非空判定“本回合已提交”，重复提交直接拒绝；`roll_phase` 用 `p.rolled` 每回合只投一次；`do_reroll`/`roll_yaocai`/`yaocai_usable` 在提交后一律拒绝；`round_close` 必须先 `settle`（`_settled` 为 true），否则返回 false。`keywords.gd` 里原先“`_basic()` 后改骰重提”的 `_t_field/_t_heal/_t_strength` 已改为一次提交到位；新增摆状态用例不要再重提同一方。`battle_ui._human_active` 仍保留为界面层第一道锁。
- **`ui_stress` 在 `_init` 里 `add_child` 后必须先 `await process_frame`**：否则第一局 `@onready` 变量还是 null，脚本错误会让场景不被释放，表现为“1 个根节点 + 几十个 Timer”的假泄漏（2026-11-25 实测踩过）。
- **共享 UI 组件（2026-11-26）**：按钮样式统一 `ButtonStyles`；骰子网格+刻字统一 `DieVisuals.make_die_instance()`；玩家/敌方骰行池化统一 `_obtain_view()/_prune_views()`；预览与逐骰提示的阶段被动统一 `_phase_passives()`。新增同类逻辑先复用，不要复制粘贴。
- `str.replace` 不接受函数回调（Python 习惯会踩）。
- Node 未入树时 `look_at` 报错 → 用 `look_at_from_position`。
- tscn 手写时新增 ext_resource 必须同步改 `load_steps`。
- 模拟/正式共用同一 RNG 通道（Crypto），不要为复现性私加种子（用户禁止）。
- 界面视觉问题（字号、醒目度）无头测不出：改布局/字号先跑 tests/shot.gd 截图自核，再提醒用户开窗确认。
- 读 xlsx 用 Python zipfile 解 `xl/worksheets/sheetN.xml` + `xl/sharedStrings.xml`：单元格 `t="s"` 时 `<v>` 是 sharedStrings 下标，需映射回原文（直接读 `<v>` 会得到数字索引）。
- **CenterContainer 下的 ScrollContainer 最小高度为 0**：选卡页改居中列后，CharScroll 不给固定最小高会把角色网格压成 0 高（2026-11-17 截图复现）；固定最小高 330 后正常。新增居中布局里的滚动区时同样检查。
- **锚定右下的 VBox 会被长文案撑宽并向左扩展**：战斗按钮列名义宽 260px，「重投所选5颗（剩2次）」在默认 32px 字号下单行最小宽 333px，整列因此左移压住玩家信息栏（2026-11-17 探针复现）。按钮文案必须双行或缩短；`ui_smoke.gd` 已加最长文案 `combined_minimum_size.x <= 260` 回归断言。
- **信息栏默认 panel 样式 content margin 为 0**：文字会贴黑框；`battle_ui._pad_info_bar()` 复制主题样式后加左右 20/上下 8px，并设 `clip_contents=true` 防止内容越界。
- **面板最小尺寸会撑破固定 offset**：`PanelContainer` 内容最小高超过 offset 高度时会向下增长（不是裁切）。玩家条原 y936 + 长被动/状态最小高 162 = 越出 1080 下缘；现日志收为 y872–910、玩家条上移 y910，被动/状态 22px，最坏 1072 仍可见。改信息条字号/内边距后必须复测最坏组合。
- shot.gd 必须开窗跑（不加 --headless），会闪窗后自动退出，属正常；纯无显示环境跑不了。
- settle() 中改骰点数的效果（跃升/骇入）必须放在攻防值求和之前，否则伤害用旧值——骇入曾因此整体失效（2026-10-11 修复）。
- **「攻击后」类被动不能在 commit_selection 里结算**：地球的 `strength_set` 若在 commit 写入力量，settle 重算攻击值时会把它吃进本次伤害（用户 2026-11-11 裁决：攻击后必然在结算后触发）。现实现放在 `settle()` 内攻击结算之后（中毒之前），`_ctx_a.atk_value` 已更新为跃升/骇入后的最终攻击值；新增 attack_after 效果时沿用此处。
- **连击多来源已改为计数**：`apply_fx` 写 `flags.combo_count`（不是 `flags.combo`），`settle()` 按次数逐段结算、`summary.combo_n` 记实际段数；写测试/探针直接摆上下文时用 `combo_count = N`。多来源骇入仍是布尔 `hack_pending`（用户暂缓叠加），不要误改成计数。
- **`round_open()` 必须清空 `_ctx_a`/`_ctx_d`/`atk_value`/`def_value`**：攻方 commit 瞬伤致胜时防御阶段会被跳过，若不清空，settle 会读到上一回合的 bonus/攻防值（2026-11-11 修复）；新增跨阶段缓存时同样在回合开始重置。
- **AI `_trigger_bonus()` 的条件判定必须与 `eval_cond()` 口径一致**：2026-11-11 发现 `all_same` 只判「非空」，导致生命学院防御任意组合都被估成不屈 +6；改 AI 评估时逐条件对照 `eval_cond`，改完跑 sim 观察。
- `roll_yaocai()` / `do_reroll()` 现在自带入口兜底（统一过 `yaocai_usable()` / `rerolls > 0`）：新增调用点不要绕过；直接改 `p.dice`/`yc_uses` 的旧写法会绕过计数与 KO 守卫。
- **命定骰不可取消选中，且重投必带**：`battle.is_mingding(d)` 是唯一判定；`commit_selection` 强制入选、`do_reroll` 强制把命定骰加入重投并**返回实际重投集合**。调用 `do_reroll` 后要用返回值驱动动画（人类/AI 已改），不要继续用传入的 picks，否则强制加入的命定骰不会被演出（2026-11-11）。
- `battle_ui._on_confirm()` 在 commit 后立即把 `_human_active=false`：commit 可能有瞬伤，信号恢复前若再次点击会二次提交（2026-11-11 加固）；新增确认/提交类入口时同样先锁输入。
- 骇入在对手全部已选骰为 1 时会把其中一颗 1 抬到 2（不是 bug，用户 2026-11-10 裁决）；不要改成「≤2 时不变」。
- 攻/防等级可被被动无限累积（数学洞穿+1、AI学院受伤≥8 双等级+1），超过骰池上限会令 AI 组合枚举空数组越界、人类软锁——selection_count 已钳制到可用骰数（2026-10-13 修复）；今后新增「等级+N」类被动时注意此上限。
- `round_close()` **无条件** `round += 1`（终局那一回合也加），所以任何「总回合数」展示都要用 `round - 1`；2026-10-14 重写战绩页时忘了这点，把 10-13 的修复覆盖成差一 bug（10-15 修回）。
- **重写既有 UI 模块前，先读该模块在 DESIGN §10 / 本节 §8 里的历史修复记录**——战绩页两次翻车都是重写时丢了旧修复。
- 只在 `_ready`/`_refresh_static` 里求值一次的界面元素不会自动更新：凡随对局变化的文本（如攻/防等级徽章）必须存引用并挂进 `refresh()`（2026-10-15 修复）。
- **化学「升级」只提升骰型/最大面数，保留当前点数，不重投**（用户 2026-11-12 裁决确认；DESIGN §2/§9；`_t_upgrade` 断言「升级当回合保留点数」）。不要给 `upgrade_sel` 补重投逻辑。
- `eval_cond()` / `apply_fx()` 的 `match` 未命中是**静默失败**（返回 false / 什么都不做），条件或效果字符串拼错不会报错、只会"没效果"；新增被动后必须写 keywords 断言确认真的触发了。
- Godot 4.7 的 `RichTextLabel` 没有 `set_bbcode()`：赋 `.text` 并把 `bbcode_enabled = true`；可点击词用 `[url=...]` + `meta_clicked` 信号（效果显示入口即此机制）。
- 界面上「扣血」要用实际值：`Battle.hits[*].amount`、`stats.dmg_taken/dmg_dealt` 均为扣血前后差值；`s.dmg`（横幅「主伤害」）是名义伤害，溢出/不屈时与「共掉血」不同（2026-11-10 起 stats 也改为实际值）。
- 固定尺寸 + 锚定的弹窗（曜彩/效果显示/战绩面板）在视口宽度小于基准时会溢出：按 `get_viewport_rect()` 收窄后，还要同步处理**内容最小尺寸**（曜彩六面卡固定 170 最小宽度会把弹窗重新顶宽，须按列数降最小宽度或降列）；基准 1080p 尺寸不变（2026-10-25）。
- 重投 3D 演出：不要调用整轮 `roll` 显示双方骰行，用 `battle_ui._animate_roll(picks, idx, true)` 只滚本次重投的骰（约 1.3s，期间锁输入）；`dice_roll` 的 spec/mesh/material 缓存键必须区分骰型（曜彩按名称），新增骰型/改面表时同步检查，否则标签或颜色会串。
- 批量掉血飘字要按目标叠放：敌方信息条在屏幕顶部，向上叠会把第二笔顶出屏幕——敌方向下、我方向上（2026-10-25 探针发现）。
- AI 工具的 Grep 偶发漏报（字符串明明存在却 "No matches found"）：换个 pattern 或直接 Read 文件确认；ripgrep 默认不支持 look-behind（`(?<!x)` 会直接报错），需要"排除某前缀"时改为全量匹配再人工筛。
- 结算横幅有两套口径：`s.dmg`/`s.dmg2` 是结算公式算出的名义伤害（`dmg2` 为所有连击段合计，含洞穿/力场判断），`hp_before - hp_after` 才是守方实际共掉血（可含连击/荆棘自伤/中毒）；展示时不要用一个替代另一个；战绩统计、飘字一律用实际值（2026-11-10 改动，旧「stats 名义口径」约定已废弃）。
- 洞穿/力场/反击的边界：力场只挡非洞穿的主伤害与连击各段；洞穿取攻击值、破力场，且不满足反击的「防御值更大」条件（`settle()` 反击条件必须保留 `not summary.pierce`）；瞬伤/荆棘/中毒不吃力场（2026-11-10 修正，旧实现洞穿仍会触发反击）。
- 3D 骰面数字用每个面挂 `Label3D`：Label3D 文字面朝本地 +Z，须用「面法线当 +Z、投影 up 当 +Y」构造 Basis；`double_sided=false` 防止背面反字；数字大小按面内切圆半径算（1.35×inradius/字号）。Godot 4.7.2 没有内置正四面体/正八面体/正十二面体 Mesh（只有 `BoxMesh`），d6/曜彩用 `BoxMesh`，其余用精确正多面体顶点生成 `ArrayMesh`；自定义网格必须按 Godot 顺时针正面绕序 `[0,i+1,i]`，否则 `CULL_BACK` 显示的是内壁。数字贴面只沿法线外移 0.0015，单面且开深度测试；d4 逐面预旋转刻字，使该面作为结果面停姿时数字尽量竖直（2026-11-26）。正十二面体面法线由顶点凸包支撑面算法生成（2026-11-11）。
- KO 后边界：所有扣血/治疗/改点的循环必须逐迭代或逐效果检查 `winner`；commit 瞬伤致死后 `settle()` 仍会先跑跃升/骇入（已加 winner 守卫）；`battle_ui`/`driver` 在攻方 commit 致死后跳过阵亡方防御阶段；`damage()`/`heal()` 对 HP≤0 目标直接返回（2026-11-11）。
- **选骰界面 3D 化（2026-11-12）的必守点**：每颗骰必须独立 `SubViewport` 且 `own_world_3d=true`（共用世界会让各骰的相机/灯光/网格互相干扰，出现错位或空白）；静态骰用 `UPDATE_ONCE`（`UPDATE_ALWAYS` 会让 N 个 SubViewport 持续烧 GPU，改骰面/描边后手动重渲染一次）。
- **`refresh()` 只能增量刷新骰行**：`_sync_dice_row`/`_sync_enemy_row` 按 Die 复用 `_die_views`/`_enemy_views` 池，不要每次重建 DieView/SubViewport（会掉帧、闪白）；`_on_die`/`_sel`/命定锁定/重投接口保持不变。
- **`SubViewport.size` 必须与 cell 渲染区一致**（普通 128×108、敌方 96×96）；`SubViewportContainer.stretch=false` 时容器最小尺寸取子视口尺寸，因此尺寸设 0 会被布局压成空白。改 cell 尺寸要同步 SubViewport 与镜头。
- **选中描边壳是 `CULL_FRONT` 不透明反壳**：壳放大 1.06、只渲染背面，在骰子轮廓外形成描边；骰体本身 `CULL_BACK` + `TRANSPARENCY_DISABLED`。旧实现因自定义网格绕序反了，只能 `CULL_BACK` + 半透明 additive 发光，已废弃；不要再把壳或骰体改成半透明/发光（压暗只改 RGB，alpha 保持 1）。
- **骰下提示 `RichTextLabel` 的 `mouse_filter` 不能设 `IGNORE`**（否则关键词点不到），点击 3D 骰本体由上部无边框 Button 承担，两者区域不要重叠。
- **敌方骰块在信息条框外、名字正下方**：`EnemyDiceBlock` 是 root 直系子节点（x = 敌条左 + 20）→ `EnemyDiceHead`（来源标题 + 右侧「总计 N」）+ `EnemyDice`（`GridContainer`，5 列，第 6 颗换行）。每个 DieView 用 `setup_enemy()`（96×132：3D 96×96 + 36px/13px 提示），不可点击；与玩家骰共用 `DieVisuals.display_rotation`/正交镜头/灯光/材质，只是尺寸缩小。信息条只按名字/被动/状态内容收紧，不再为骰块预留高度。块宽上限 884（不越过居中横幅文字）；改列数/尺寸必须同步 `_sync_enemy_row` 的 `block_w`/`block_h` 计算。`en.sel` 在 round_close 后仍可能含已移除的曜彩骰，展示/总计前必须按 `en.dice` 过滤。
- **状态栏必须独立成行**：`EnemyStatus/PlayerStatus` 是信息条 VBox 的第三行（被动下方），不要塞回名字/HP/HP 条所在的 HBox——长状态会把 HP 条挤窄或把文本顶出条外。1080p 下 3 行仍放得下，`shot.gd` 自检可确认。
- **逐骰提示只有一套条件口径**：`_die_fx_hints()` 用 `AIController.combinations()` 穷举「刚好 need 颗且含全部命定骰」的选择，再用 `Battle.eval_cond()` 判定；新增骰值相关条件时把 `c.t` 加进 `HINT_COND_TYPES` 即可，不要另写近似判断（曾因忽略命定强制入选误报 sum_ge）。
- **`shot.gd` 现为六图**（`shot_dice_selected.png` 只截人类可操作阶段的静态选中态）：脚本等到人类首个可操作阶段（进攻或防御）直接截图；若人类首次操作前已分胜负则换一局（最多 4 次）。静态六图仍抓不到投骰翻滚瞬间。
- **服务端（`server/`）实现要点（2026-11-12）**：
  - SQLite 用 WAL + 写事务 `BEGIN IMMEDIATE` + `busy_timeout=5000`，应用层遇 `locked`/`busy` 有限重试；每次调用独立短连接、不跨线程共享连接；单实例部署，别并行起第二个写进程。
  - `event_id` 幂等必须在同一写事务内完成「查重 → 写事件 → 计数 → 清理」，重复提交返回 `duplicate: true` 且不计数；每玩家只保留最近 2000 条幂等记录。
  - token 只在注册响应返回一次，服务端只存 `SHA-256(token)`（配 pepper 时 HMAC-SHA256、常数时间比较）；pepper 设置后不可更改；日志/响应不得出现 token。
  - 默认只监听 `127.0.0.1:8080`；手写 `http.server` 有边界（契约：请求体上限 8 KiB、不支持 chunked；单进程），公网/HTTPS 交给 nginx，只有前置可信反代时才开 `WARRIOR_STORE_TRUST_PROXY=1`。

## 9. 未决事项（等用户输入；当前无阻塞项，v1 可完整游玩）

1. **开窗 playtest 反馈**：2026-11-26 的 3D 骰外观重做（数字贴面/全不透明/精确正多面体/选中反壳描边/d4 刻字/选骰静态视图结果面朝玩家 + 18°/28° 上仰）及同日第五轮（选中金边加粗、DiceTip 上提、敌方骰块移到信息条框外名字正下方、96×132、Grid 5 列）需要用户亲眼确认；2026-10-15 修的攻/防等级徽章成长、曜彩骰 3D 演出、战绩页总回合数，此前的效果显示/选卡流程/配色，2026-10-25 新增的双方 HP 进度条、非主伤害飘字与窄窗弹窗，2026-11-10 的结算横幅「主伤害/共掉血/连击」与战绩统计实际扣血，2026-11-11 的 3D 真骰型/逐面数字/放大，2026-11-12 的选骰界面 3D 化（候选骰/敌骰立体骰、描边选中、骰下提示），以及 2026-11-17 三轮的选卡页选中态/1280px 居中、战绩面板尺寸与三列表格、曜彩弹窗遮罩、主操作按钮金色启用态、日志前缀与选满就绪态、信息栏内边距/按钮列防重叠/长被动边界，都需要用户亲眼确认（视觉问题无头测不出）。2026-11-25 起优先稳定性/LAN，视觉细修按 playtest 反馈随时插入。
2. **P3 AI 强度改进（原 P2）**：用户 2026-10-14 指示暂缓另议，但要求在提起可玩性/难度时主动提醒；现排在 P2 局域网之后，开工前必须先提醒并获同意；清单见 DESIGN §11 P3。
3. **参考录屏 mp4 已不在仓库**：后续若需对照原作演出/节奏，请用户重新提供（抽帧仍在 `_frames/`）。
4. ~~scratch 清理~~ 已完成（2026-10-24：`_frames/probe_*.png` 与 `_xlsx/` 解包产物已删，`original-backup.xlsx` 保留）。
5. 历史 ⚠ 规则提案均已由用户裁决关闭（见 DESIGN §9/§10）；2026-11-10 的骇入与洞穿/反击也已完成裁决；2026-11-11 全量排查新发现 3 条口径中，地球攻击后时序、命定重投、多来源连击叠加均已裁决关闭，多来源跃升/骇入按用户指示暂缓（见第 8 条）。
6. **联机战斗数据存储（原 P3；2026-11-25 起暂缓）**：2026-10-27 暂缓、曾排在 PVP 之后；2026-11-25 用户决定云服务/战绩存储整体暂停，`server/` 保持原样、不删除、不继续投入，Ubuntu 部署验收暂停；恢复前需用户明确指示并重新裁决公网/隐私/反作弊等口径。其余历史口径与验证状态见下：**2026-11-12 用户指示先落地独立服务端**，服务端已实现（`server/`，Python 3 标准库 + SQLite、零第三方依赖、默认只监听 `127.0.0.1:8080`）。口径不变：只存每位玩家的 PVE/PVP 场次与胜场（胜率查询时计算），服务端生成唯一玩家 ID，玩家可自取昵称（可重名，展示带短 ID），PVE/PVP 分开存储与展示；不存每场对局明细，**也不统计伤害/扣血、回合数、角色/曜彩使用等任何其他数据**。**状态：本机单测 131 项（2 项 POSIX-only 跳过）与冒烟通过；2026-11-14 完成多轮健壮性复核与文档完善；待用户在 Ubuntu 24.04 VM 按 `server/README.md` 部署验收**。排行榜/公网入口/隐私保留期仍待裁决；客户端未接入（本轮不改 `game/`），PVP 与客户端接入顺序不变。详见 §11。
7. ~~骇入规则待裁决~~ 已于 2026-11-10 裁决：对手全部骰子为 1 时把其中一颗 1 抬到 2（保持现有实现，已有回归断言）；洞穿与反击同日澄清并修正（带洞穿不触发反击）。
8. **多来源跃升/骇入叠加（用户 2026-11-11 指示暂缓）**：多来源连击已于同日裁决为叠加并落地（`combo_count` 计数 + 逐段结算）；骇入现仍为布尔 `hack_pending`（信息学院被动 + 网络渗透面同场时只改 1 颗），跃升无多来源授予路径。用户表示「暂时还不会有多来源的跃升和骇入吧，这个先放一放，等以后再说」，故暂不改代码；日后重启时参考连击的计数方案。~~地球「攻击后」力量是否影响本次伤害~~ 已于同日裁决：不影响，攻击结算后生效；~~命定骰能否被重投~~ 已于同日裁决：可以，但不可取消选中、重投时必须一起重投，重投后仍须用于结算。
9. **局域网 v1 口径（2026-11-25 已确认）**：主机权威；自动发现 + 手动 IP 兜底；昵称 1–16 字符；连续对局会话胜负统计 + 再来一局；允许镜像；断线方判负/不重连；单步 60 秒超时；v1 不做观战/重连/跨会话持久化。实现排在稳定性之后；端口/发现协议在 M1 验证（暂定战斗 UDP 42420、发现 UDP 42421）。

## 10. 交接指引（新设备 / 新软件 / 新模型）

1. 把整个 `D:\warrior party\` 文件夹原样拷贝到新设备，或 git clone 本仓库（分支以远端当前分支为准）。注意：git 只含已跟踪文件（参考录屏 mp4 从未入库、现已不在磁盘）；`game/.godot/` 可不带（首次 import 自动重建）；`_frames/`、`_xlsx/` 为 scratch（`_xlsx/original-backup.xlsx` 必须保留）。
2. 新设备装 Godot 4.7.2 并加入 PATH（保持 exe 全名 `Godot_v4.7.2-stable_win64.exe`，见 GODOT_GUIDE.md §1）；装 Python 3.x（解析/改 xlsx 用；服务端测试另需 Python 3.10+，本机 3.13、Ubuntu 24.04 自带 3.12，零第三方依赖）；ffmpeg（仅重新抽帧时需要）。
3. 打开项目后按顺序读：`AGENTS.md`（硬规则 + 常见任务菜谱）→ 本文件（§5.1 代码索引、§5.2 字段词典、§8 坑）→ `DESIGN.md`（规则与决策日志，尤其 §5.1 合法取值、§9 已定约定、§11 待办）→ 需要细节时 `README.md`（文件清单）/ `GODOT_GUIDE.md`（引擎操作）。
4. 跑一遍 §6 验证链确认环境可用：`--import` → `keywords.gd`（应 `pass=1206 fail=0`）→ `sim.gd`（792 局，每角色 132 局胜率表）→ `ui_play.gd`（应 `UI PLAY DONE`，约 1 分钟）→ `ui_smoke.gd`（应 `UI SMOKE OK`）→ `soak.gd`（应 `SOAK OK`）→ `fuzz_actions.gd`（应 `FUZZ OK`）→ `ui_stress.gd`（开窗，应 `UI STRESS OK`；`--headless -- --mode=lifecycle` 只跑生命周期）；改布局再跑 shot.gd 并 Read 六张截图。
5. 继续工作的规矩：数值/规则改动必须先列方案给用户批准并同步 xlsx 与文档；每次用户反馈逐条落实后写入 DESIGN.md §10/§11；改完代码必须无头验证（keywords + sim + ui_play + ui_smoke + soak/fuzz，改布局加 shot.gd）再汇报，视觉最终由用户开窗确认；稳定性测试失败时记录动作+掷骰结果回放，**不要给 `game_rng.gd` 加种子**；不擅自 git commit。
6. 服务端（`server/`）验证（**2026-11-25 起整体暂缓，以下命令仅供将来恢复时参考**）：`cd server && python -m unittest discover -s tests -v`（131 项应 OK、2 项 POSIX-only 跳过）→ `python tools/smoke.py`（应 `SMOKE OK`）→ `python -m compileall app tests tools`（退出码 0）；只需 Python 3.10+、零第三方依赖。Ubuntu 部署/备份/恢复按 `server/README.md` 验收，接口字段见 `server/API.md`。
7. 本仓库已纳入 git（分支以仓库当前状态为准，`.gitignore` 忽略 `.godot/`、`*.exe` 等）：交接可 git clone / 整仓拷贝。git 提交与仓库状态由用户全权负责，AI 不执行、不跟踪。若使用带持久记忆的 AI 工具，其项目记忆应与本文件保持一致；冲突时以仓库内文档为准。
8. shell 注意：部分环境（如 ZCode 本机会话）Bash 工具实为 cmd.exe，Unix 管道（`| tail` 等）不可用，Godot 命令整条直跑即可；控制台中文可能乱码，需要时让脚本写 UTF-8 文件再 Read。
9. 第一次动手前建议先做一件小事验证链路（如把某处文案改一个字→跑 keywords+ui_smoke→改回），确认工具链与权限都正常，再开始正式任务。

## 11. 服务端（`server/`，2026-11-12 交付；2026-11-14 复核；2026-11-25 起暂缓）

> 用户 2026-11-12 指示先落地独立的玩家数据存储服务端；本轮不改 `game/`，Godot 客户端尚未接入。**2026-11-25 用户决定云服务/战绩存储整体暂停：`server/` 保持原样，不删除、不修改、不继续投入，Ubuntu 验收暂停。** 使用与部署入口是 `server/README.md`，接口契约是 `server/API.md`（两者冲突时先改 `API.md`）。

- **用途与数据口径**：玩家注册后获得服务端生成的 ID（`p_` + 16 位小写十六进制）与一次性 token；客户端上报自己的 PVE/PVP 胜负；查询返回场次、胜场、胜率（查询时计算）。只存 ID、昵称（可重名，展示用前 6 位短 ID）、创建/更新时间、PVE/PVP 的 `games`/`wins`；**不存对局明细，也不统计伤害/扣血、回合数、角色/曜彩使用**；PVE/PVP 分开。
- **目录**：`app/`（`config.py` 配置、`auth.py` token 哈希、`db.py` SQLite 存储、`validation.py` 校验、`errors.py`/`log.py`、`http_api.py` HTTP 路由、`ratelimit.py` 限流；入口 `app/main.py`：`make_server(config)` / `run(config)`）、`tests/`（unittest）、`deploy/`（systemd unit/timer、env 样例、`backup.py`/`restore.py`、`install-ubuntu.sh`）、`tools/smoke.py`、`README.md`、`API.md`。
- **启动与配置**：`cd server && python3 -m app`（默认 `127.0.0.1:8080`，DB `data/store.sqlite3`）；也支持 `--host/--port/--db/--log-level`，优先级命令行 > 环境变量 > 默认。生产环境由 `/etc/warrior-store.env` 配置（样例 `deploy/warrior-store.env.example`），systemd 以 `warrior-store` 用户运行，数据库默认 `/var/lib/warrior-store/store.sqlite3`。
- **API 一览**：`POST/GET /api/v1/players`（注册/批量，批量最多 50 个 ID）、`GET/PATCH/DELETE /api/v1/players/{id}`、`POST /api/v1/players/{id}/results`、`GET /healthz`。注册返回一次性 token（服务端只存 SHA-256(token)，可配 pepper 改 HMAC）；`event_id` 幂等（每玩家保留最近 2000 条）；DELETE 为自助删除；错误码/字段/限流见 `API.md`。
- **实现边界**：SQLite WAL、`BEGIN IMMEDIATE` + `busy_timeout`、短连接、参数化 SQL；单实例，限流计数在进程内存；手写 `http.server`（契约上限 8 KiB、唯一 `Content-Length`、不支持 chunked，见 `API.md` §1 与 §3）；默认只监听本机，公网/TLS 由 nginx 等外部组件负责（默认不需要）。
- **2026-11-14 复核修复**：短读拒绝、错误响应排空/`Connection: close`、JSON 解析异常统一 400、schema/健康检查 fail-fast（文件 + `user_version` + 三表）、批量查询读快照、幂等窗口 2000、胜率 `ROUND_HALF_UP`、未知方法 JSON 405/404；备份轮转按文件名时间戳并排除源库/本次文件、备份/恢复校验 schema 与三表、恢复 `--allow-running`/`--remove-wal`/符号链接拒绝、安装 staging 换入与 `is-active` 检查。文档新增审查者路径/设计取舍/数据模型/术语/FAQ。
- **验证**：`cd server && python -m unittest discover -s tests -v`（131 项 OK、2 项跳过；本机 Python 3.13 通过）→ `python tools/smoke.py`（应 `SMOKE OK`）→ `python -m compileall app tests tools`。**未验证**：Ubuntu 24.04 的 systemd 安装、备份 timer、恢复演练（本机 Windows 无 systemd），需按 `server/README.md` §11 在 VM 验收。
- **待裁决**：排行榜口径、公网入口/域名/HTTPS、隐私与数据保留期、客户端接入、反作弊/互证。本轮无任何游戏数值/规则改动。
