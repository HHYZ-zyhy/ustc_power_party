# D:\warrior party — 文件夹说明

> 科大战力党（骰子对战游戏）项目根目录。接手先读 `AGENTS.md`（硬规则速查），再读 `CONTEXT.md`（背景与架构），规则读 `DESIGN.md`，Godot 操作读 `GODOT_GUIDE.md`。本文件是**项目概览与文件夹用途登记表**，新添文件必须在此登记一行。
> 最后校订：2026-11-26（选骰 UI 第五轮微调；无规则/数值改动）
>
> **最近更新**
> - 2026-11-26 选骰 UI 第五轮：选中金边壳层 1.06→1.10 加粗；DiceTip 上提 16px（y664–692）；敌方骰块移出敌方信息条，放到框外名字正下方（96×132、`GridContainer` 5 列、第 6 颗换行、来源标题行右侧「总计 N」；与玩家骰共用同一 `display_rotation`/正交镜头/灯光/材质）。
> - 2026-11-26 代码整理：抽出 `ButtonStyles` 共用按钮样式、`DieVisuals.make_die_instance()` 共用骰体+刻字装配、`_obtain_view()/_prune_views()` 共用骰行池化、`_phase_passives()` 共用阶段被动过滤；`select_ui`/`battle_ui`/`die_view`/`dice_roll` 已接入。验证链见下。
> - 2026-11-26 3D 骰外观：数字贴面、骰体全不透明、d6/曜彩官方 `BoxMesh` + d4/d8/d12 精确正多面体、`CULL_FRONT` 不透明反壳描边；选骰静态视图改为「结果面正对玩家 + 绕屏幕水平轴 18° 上仰（d4/d8 三角面 28°）」（正交镜头 size 2.0，露出底面/侧面）；敌方骰块为玩家骰行的 96×132 缩小版（提示/总计/不可点击）。
> - 2026-11-25 方向调整：云服务/战绩存储暂停，`server/` 原样保留；优先级 **P1 稳定性 → P2 局域网 1v1 → P3 AI → P4 美术**；LAN v1 口径（自动发现+手动 IP、昵称、会话胜负统计、再来一局）已确认；稳定性两轮已完成。
> - 2026-11-17 界面打磨三轮：选卡选中态/1280px 居中、战绩面板自适应+三列表格、曜彩弹窗遮罩、主操作按钮金色启用态、信息栏内边距/按钮列防重叠/长被动边界。
>
> **5 份文档分工**：`AGENTS.md` 硬规则/命令/菜谱 · `CONTEXT.md` 架构/代码索引/进度/踩坑 · `DESIGN.md` 规则权威/裁决/待办 · `README.md` 文件登记（本文件）· `GODOT_GUIDE.md` 引擎操作/验证。

## 项目概览（给协作者）

- **是什么**：1v1 骰子对战游戏「科大战力党」；角色为科大院系，玩法借鉴《崩坏：星穹铁道》「上骰了！战力党！」。
- **技术**：Godot 4.7.2 + GDScript；2D 主界面 + 投骰、选骰与敌方骰子 3D；当前为单机 PVE（贪心 AI），下一步做局域网 1v1。独立玩家数据存储服务端 `server/`（Python 3 标准库 + SQLite）**2026-11-25 起暂缓**，保持原样、不参与游戏运行。
- **规模**：12 角色、11 曜彩骰、18 个关键词；规则见 `DESIGN.md` §1/§3，数值见 `参考素材/角色，骰子参数.xlsx`。
- **运行**：`Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"`（开窗游玩；从选卡界面开始）。
- **验证**：`cd game` → `keywords.gd`（应 `KEYWORDS pass=1206 fail=0`）→ `sim.gd`（12 行胜率表）→ `ui_play.gd`（应 `UI PLAY DONE`）→ `ui_smoke.gd`（应 `UI SMOKE OK`）→ `soak.gd`（应 `SOAK OK`）→ `fuzz_actions.gd`（应 `FUZZ OK`）→ `ui_stress.gd`（开窗，应 `UI STRESS OK`）；改布局再跑 `shot.gd` 六图（含选中态 `shot_dice_selected.png`）。详见 `GODOT_GUIDE.md` §3。
- **当前状态**：v1 PVE 全流程可玩（选卡 → 战斗 → 终局战绩页）；2026-11-26 完成代码整理轮（共享按钮样式/骰体装配/骰行池化/阶段被动过滤，无规则数值改动）与 3D 骰外观/对手骰行重做（数字贴面、全不透明、精确正多面体、选骰静态视图结果面朝玩家 + 18°/28° 上仰（正交镜头 size 2.0）、敌方 96×132 缩小行）；验证链全绿，待开窗确认。
- **下一步**：P1 稳定性收尾 → P2 局域网 1v1（自动发现 + 手动 IP、昵称、会话胜负统计、再来一局）→ P3 AI → P4 美术；云服务/战绩存储暂停（`server/` 原样保留）。已知缺口见 `DESIGN.md` §11 与 `CONTEXT.md` §9。
- **约定**：数值归用户（xlsx 唯一权威）；随机只用 Crypto；不用 autoload；git 提交由用户负责。

## 我想知道…该看哪份文档

| 问题 | 去处 |
|---|---|
| 这个项目是什么、有哪些硬规则、常用命令 | `AGENTS.md` |
| 改某个功能要去哪个文件/函数 | `CONTEXT.md` §5.1 代码索引 |
| 某个状态字段是什么意思、什么时候清零 | `CONTEXT.md` §5.2 玩家字段词典 |
| 想审查 2026-11-12 / 2026-11-26 代码整理轮、哪些不用重复报 | `CONTEXT.md` §5.3 代码审查入口 |
| 某条规则为什么这么定、谁拍的板 | `DESIGN.md` §9 已定约定 / §10 决策日志 |
| 写被动时能用哪些条件/效果字符串 | `DESIGN.md` §5.1（§5.2 是已知实现缺口） |
| 现在做到哪了、下一步做什么 | `DESIGN.md` §11（P1~P4 分级待办）+ `CONTEXT.md` §7 |
| 角色/曜彩的具体数值 | `参考素材/角色，骰子参数.xlsx`（唯一数值权威）→ 镜像在 `game/scripts/core/gamedata.gd` |
| Godot 怎么跑、测试期望输出是什么、报错了怎么办 | `GODOT_GUIDE.md` |
| 服务端怎么部署、接口字段是什么、排错 | `server/README.md`（中文使用与部署入口）+ `server/API.md`（冻结契约） |
| 某个文件是干什么的 | 本文件 |

## 根目录文件

| 名称 | 类型 | 说明 |
|---|---|---|
| `AGENTS.md` | 文档 | **任何 AI 编程工具/智能体打开本项目的第一入口**：项目一句话、阅读顺序、硬规则、命令速查、常见任务菜谱、架构速览、当前状态 |
| `CONTEXT.md` | 文档 | 交接主文档：背景、协作约定、环境事实、权威资料清单、代码架构 + 代码索引 + 字段词典、Battle 分步 API、验证命令与期望输出、进度、踩坑记录、未决事项、跨设备交接指引 |
| `DESIGN.md` | 文档 | **规则权威**：冻结规则全文、18 关键词定义、12 角色/11 曜彩骰表、§5 被动框架与合法取值、§9 已定约定、§10 决策日志（关键节点与全部裁决）、§11 进度与分级待办（改规则先改它） |
| `GODOT_GUIDE.md` | 文档 | 本机 Godot 4.7.2 使用手册：三种启动方式、无头验证流程与期望输出、临时探针规范、截图自检、工程约定、API 踩坑、故障排查表 |
| `README.md` | 文档 | 本文件：文件夹每个文件/目录的用途登记 |
| `LICENSE` | 元 | GNU GPL v3 开源许可证（仓库已纳入 git 版本控制，分支以仓库为准） |
| `.gitignore` | 元 | git 忽略规则（Godot 4 标准模板：`.godot/`、`*.exe`、导出产物、`*.tmp` 等）；**未忽略 Excel 锁文件 `~$*.xlsx`**，提交前留意 |
| `参考素材/` | **只读素材** | 全部参考素材的统一存放处：数值权威 xlsx 与原始构思 txt 在其根下，截图按 `原作截图/`、`效果/`、`曜彩骰定义/` 三个子目录分类（明细见下） |

**已不在仓库的文件（旧文档可能还提到）**：
- `示例1.mp4` / `示例2.mp4`（原作参考录屏，曾各 66MB / 156MB）——已移除，抽帧保留在 `_frames/ex1_*.jpg`(8 张)、`ex2_*.jpg`(14 张)；需要再看动态演出请用户重新提供。
- `银河战力党-官方资料汇编.md`（网络抓取的官方资料）——用户明示可能有误、**非权威**（xlsx 优先），且已不在磁盘。
- `参考素材/~$角色，骰子参数.xlsx` 若出现，是 Excel 打开该表时的锁文件（未跟踪）：此时替换 xlsx 会报 WinError 5，也别把它提交进 git。

### 参考素材/（只读，全部参考素材的统一存放处）

| 名称 | 类型 | 说明 |
|---|---|---|
| `参考素材/角色，骰子参数.xlsx` | **数值权威** | sheet1 角色属性（12 角色）、sheet2 骰子属性（11 曜彩骰，B 列面表已录入）。改数值需用户批准后同步 `gamedata.gd` |
| `参考素材/科大战力党-构思.txt` | 规格 | 用户原始构思：Godot 引擎、Crypto 随机、2D+投骰3D、贪心 PVE、中期局域网、后期天气 |
| `参考素材/原作截图/进攻方选骰子.png` | 参考 | 原作战斗界面截图（进攻方选骰态）——整体布局与逐骰效果标注的对照依据 |
| `参考素材/原作截图/进攻方使用曜彩骰时.png` | 参考 | 原作战斗界面截图（曜彩弹窗态）——曜彩六面表弹窗布局的对照依据 |
| `参考素材/原作截图/防御时显示界面.png` | 参考 | 原作战斗界面截图（我方防御时）——第八轮反馈「显示敌方所选骰+总计」的对照依据 |
| `参考素材/原作截图/未选中时显示可能的效果.png` | 参考 | 原作战斗界面截图（未选中骰子时）——第十一轮反馈「逐骰效果标注」的对照依据 |
| `参考素材/原作截图/选中时高亮显示获得效果.png` | 参考 | 原作战斗界面截图（选中骰子高亮）——第十一轮反馈「已选触发效果高亮」的对照依据 |
| `参考素材/效果/` | 参考 | 官方关键词解释截图 page1~4.jpg（官方 15 条）；游戏内关键词共 18 条（另 3 条用户补充，全文见 DESIGN §3） |
| `参考素材/曜彩骰定义/` | 参考 | 11 张曜彩骰面表与使用条件截图，gamedata.gd 面表录入依据。文件名仍用旧曜彩名（只读参考素材，未改），对应新名：理实积淀(蓄力.jpg)、命运签约(命运.jpg)、军训急救(医嘱.jpg)、重复试验(复读.jpg)、网络渗透(奇术师.jpg)、通宵鏖战(战狂.jpg)、东风导弹(魔弹.jpg)、选课盲赌(赌徒.jpg)、顶刊论文(奇迹.jpg)、实验防护(星盾.jpg)、铜砖誓言(誓言.jpg) |

## 子目录

| 名称 | 说明 |
|---|---|
| `参考素材/` | 只读素材统一存放处（根下 xlsx 与构思 txt；子目录：原作截图 5 张 / 效果 4 张 / 曜彩骰定义 11 张），明细见上 |
| `game/` | **Godot 4.7.2 工程**（可执行内容全在这里），结构见下 |
| `server/` | **Ubuntu 玩家数据存储服务**（2026-11-12，独立于游戏客户端；**2026-11-25 起暂缓，保持原样、不删除、不继续投入**）：Python 3 标准库 + SQLite、零第三方依赖；HTTP JSON `/api/v1`，默认只监听 `127.0.0.1:8080`，入口 `python3 -m app`；使用/部署见 `server/README.md`，契约见 `server/API.md`；本机单测/冒烟通过，Ubuntu 部署暂停，结构见下 |
| `_frames/` | 工作scratch：原作录屏的 ffmpeg 抽帧（`ex1_*.jpg` 8 张、`ex2_*.jpg` 14 张——**mp4 本体已移除，这些抽帧是唯一的动态参考**，勿删）；`tests/shot.gd` 每次覆盖生成的布局自检图（shot_selectscene / shot_select / shot_dice_selected / shot_yc / shot_glossary / shot_summary.png 六张）。历史探针截图已清理（2026-10-24） |
| `_xlsx/` | 工作scratch：**仅存 `original-backup.xlsx`（写入 B 列前的原表备份，永久保留，勿删）**；解包产物与解析记录已清理（2026-10-24，日后写 xlsx 需要时再重新解包） |

## game/ 工程结构

```
game/
  project.godot        工程配置：主场景 scenes/select.tscn、全局主题 theme.tres、gl_compatibility 渲染、
                       基准分辨率 1920×1080（canvas_items 拉伸 + aspect=expand，适配不同窗口）
  theme.tres           全局 GUI 主题（默认字号 32；调字号改这里，不要逐控件改）
  .godot/              引擎缓存（import 产物），可删，下次 import/运行自动重建
  scenes/
    select.tscn        选卡界面（1 角色 + 1 曜彩骰；1280px 内容列居中；信息栏显示骰池构成与 Excel 原文介绍；少年班显示「攻?」；开始按钮金色启用态）
    battle.tscn        战斗界面布局：敌方信息条顶部 x360 起（名字/HP/曜彩行 → 被动 → 状态，只按内容收紧，不包骰块）/
                       敌方骰块在框外、名字正下方（GridContainer 5 列、第 6 颗换行；96×132 缩小版，带骰下提示、不可点击、
                       来源标题行右侧「总计 N」，块宽上限 884 不压居中横幅）/
                       横幅+预期效果中上（预期效果居中）/
                       投骰 3D 子视口 RollView 居中透明 / 选骰提示 DiceTip y664–692 + 骰子候选 DiceRow x±700、y720–870
                       （DieView 3D 骰，选中金边加粗 + 骰下 16px 提示）/ 玩家信息条底部（名字/HP/曜彩行 + 被动 + 状态独立成行）/
                       操作按钮右列（曜彩/重投/确认；确认按已选/需选数启用）/
                       曜彩六面表弹窗 YcPopup（全屏遮罩 + 点外部关闭）/ 终局战绩汇总页 SummaryView（65% 黑色遮罩 + 按内容高度 + 三列表格 + 返回按钮金色）
  scripts/
    core/              纯逻辑层（不依赖 UI，可无头运行）
      die.gd           Die：sides/value/yaocai/face；升级链 d4→d6→d8→d12（升级只改骰型、保留当前点数，用户 2026-11-12 裁决）
      gamedata.gd      12 角色 + 11 曜彩骰面表/使用条件 + 关键词定义 + 骰型显示名 SIDES_TEXT
                       （照 xlsx 录入，勿手改数值；intro 字段为 Excel 介绍原文）
      game_rng.gd      GameRng：仅 Crypto.generate_random_bytes，无种子通道
      battle.gd        Battle：分步回合 API 与结算时序（跃升/骇入先改点再求和、并列随机取；
                       多来源连击按 combo_count 逐段结算；地球「攻击后」在 settle 内攻击结算后生效，不参与本次伤害）；
                       eval_cond/pairs_count/dice_sum/pool_count 为静态纯函数
                       （结算、AI 估值、界面预期效果与逐骰提示共用同一口径）；
                       yaocai_usable/yaocai_reason（可用性与中文原因）；do_reroll 返回实际重投集合
                       （命定曜彩骰强制加入，is_mingding 统一判定）；damage() 钳制 HP≥0 并写 hits 逐笔掉血事件；
                       stats 伤害按实际扣血累计（与 hits/飘字/战绩统计同口径）；
                       力场只挡非洞穿主伤害/连击，洞穿破力场且不触发反击；
                       KO 后所有效果停止（逐迭代/逐效果的 winner 守卫；damage/heal 对 HP≤0 目标返回）
      ai.gd            AIController：贪心枚举选骰/重投/曜彩启发式；_trigger_bonus 条件判定直接复用
                       Battle.eval_cond（唯一实现）；精确 k 组合 combinations() 同时供界面逐骰提示穷举
                       （待改进清单见 DESIGN §11）
      driver.gd        Driver：同步编排（无头模拟用）run_round/run_game；攻方 commit 致死后跳过阵亡方防御阶段
      game_state.gd    GameStateData：静态变量 char_id/yc_name（选卡→战斗跨场景，不用 autoload）
    ui/
      select_ui.gd     选卡逻辑：初始空选、选中角色自动带推荐、上局返回恢复；1280px 居中布局、骰池构成行、攻?显示、
                       推荐曜彩星标与信息栏（yc_reco）、化学禁曜彩、开始按钮金色启用态（ButtonStyles.apply_primary）
      button_styles.gd ButtonStyles：选卡页与战斗页共用的按钮样式（选中金边/推荐金字/禁用暗色/主操作金色启用态）
      battle_ui.gd     战斗界面逻辑（人类=玩家0 异步编排）：中文效果文案映射、命定锁定（不可取消选中、重投必带）、升序排骰、
                       选中即重投（带 1.3s 3D 翻滚短动画）、攻方 commit 致死后跳过阵亡方防御阶段、双方 HP 进度条（#E9517D）、掉血闪红+飘字（主伤害/连击/反击/瞬伤/荆棘/中毒）、
                       曜彩六面表卡片（3×2）+ 曜彩/战绩面板窄窗自适应 + 开关式 + 不可用原因、攻/防等级角标（随 refresh 更新）、
                       状态栏独立成行（荆棘待结算/力场/不屈/中毒/力量/跃升，长文本不挤 HP 条）、信息栏 20/8px 内边距（_pad_info_bar，防文字贴边/越界）、
                       逐骰效果标注（少年班不显示；精确组合判定并计入命定强制入选）、
                       选骰提示行（点击选择/取消 + 已选/需选）、预期效果汇总行（居中）、
                       确认按钮按已选/需选数启用并在选满时金色就绪（选骰提示同步变金）、按钮列固定 260px（重投/曜彩长文案双行，防压信息栏）、敌方骰来源标题（敌方所选/敌方上回合）+ 总计、守方上回合骰展示、
                       结算横幅（主伤害/连击段数/共掉血，名义与实际分列）、骰型配色（3D 材质由 DieVisuals 生成）、效果显示接入、
                       候选骰/敌骰 DieView 对象池（_die_views/_enemy_views；_obtain_view/_prune_views 统一创建与清理，
                       _sync_dice_row/_sync_enemy_row 增量刷新）、
                       曜彩骰 3D 演出、终局战绩汇总页（伤害与触发统计，伤害按实际扣血；三列表格对齐、返回按钮金色）、
                       日志「战报｜」前缀、Esc 关闭曜彩/效果显示弹窗
      glossary.gd      效果显示弹窗 GlossaryPanel（原「关键词图鉴」；18 条定义照录 DESIGN §3，
                       可滚动查看全部；打开时高亮并定位到所点效果，行可点击；定义内效果词均为可点击 meta 链接；
                       窄窗口按边距收窄；Esc 关闭）
      dice_roll.gd     投骰 3D 演出（SubViewport 透明背景，普通投骰约 2.3s、重投 quick 约 1.3s；真骰型 d4 正四面体/
                       d6 立方/d8 正八面体/d12 正十二面体，d6/曜彩用官方 BoxMesh、其余精确正多面体；每个面挂贴面 Label3D，
                       翻滚后停在所掷点数面；骰体明显放大，镜头按骰数推近；骰型同色系；旋转随机走 Crypto；
                       面数据/网格/材质/刻字/灯光复用 DieVisuals 静态缓存，本文件只做演出编排；
                       曜彩骰为蓝紫立方并刻实际面点数，普通骰与曜彩共用同一 roll() 接口）
      die_visuals.gd    3D 骰几何/材质/刻字/停骰姿态 + 共用灯光/环境光（DieVisuals 静态类，按骰型静态缓存；
                        骰体全不透明、数字贴面、d4 逐面预旋转刻字；make_die_instance() 统一装配网格+逐面刻字，
                        dice_roll 演出与静态选骰共用同一套骰体与照明）
      die_view.gd       DieView：单个骰子的静态 3D 视图（上部无边框 Button 内嵌 SubViewportContainer + 小 SubViewport：
                       own_world_3d / transparent_bg / UPDATE_ONCE；下部效果提示 RichTextLabel；
                       只在骰面/选中/锁定变化时重渲染；选中金（壳层 1.10，略加粗）/命定粉（1.06）不透明反壳描边（CULL_FRONT，无 additive 发光），
                       静态视图结果面正对镜头、绕屏幕水平轴 18° 上仰（d4/d8 三角面 28°，正交镜头 size 2.0，露出底面/侧面），悬停轻微放大；普通 cell 128×150、敌方 cell 96×132（与玩家同一姿态/镜头/灯光））
  tests/
    sim.gd             792 局 AI vs AI 回归监控模拟（12 角色有序两两 ×6 局，每角色 132 局；随机曜彩；
                       数值对齐官方版，仅监控不调参）
    keywords.gd        关键词级断言测试：无 RNG 摆定骰面直接断言结算数值，36 组场景 1206 项断言；
                       **改核心结算逻辑必跑**，期望 KEYWORDS pass=1206 fail=0
    ui_play.gd         无头假人全流程（含重投、曜彩使用路径），期望 UI PLAY DONE（约 1 分钟；超时退出码 1）
    ui_smoke.gd        场景实例化冒烟（30 帧）+ 效果显示/推荐曜彩/HP 条/窄窗弹窗/效果名中文映射/预期效果连击×N/命定锁定/
                       DiceRow 结构（点选切换/池化 id/逐骰提示精确性/敌方 96×132/敌方标题（含上回合）与总计/选骰提示/
                       确认按钮启用条件/状态栏独立行/战绩遮罩/布局 offset）/各骰型面数与刻字、BoxMesh/精确多面体网格、骰体与描边不透明、
                       数字贴面/停姿/d4 刻字竖直/静态正视姿态（结果面朝镜头 + 18°/28° 上仰）/压暗 alpha 断言，期望 UI SMOKE OK
    soak.gd            无头浸泡：2000 局随机角色/曜彩 + AI/随机策略，检查 HP/winner/回合/骰数/sel/rerolls/stats/log 不变量；
                       区分击倒与 80 回合 HP 判定；期望 SOAK OK games=2000 fails=0（约 3-5s）
    fuzz_actions.gd    随机动作 fuzz：valid 模式按合法状态机推进（2 万步，期望 FUZZ OK）；invalid 模式专测越界/错阶段/对方骰/
                       重复提交/重复投掷/提交后重投与曜彩（自包含确定性用例），最后一行 FUZZ INVALID step/case 即定位
    ui_stress.gd       UI 压力：完整 UI 对局 + select↔battle 往返 + 孤儿节点/Timer/Tween 泄漏检查；
                       full 模式需开窗（默认 30 局 + 100 次往返，time_scale=10），lifecycle 模式可无头只跑往返
    shot.gd            布局截图自检（开窗运行，输出 _frames/shot_*.png 六张：选卡/战斗/选中态/曜彩弹窗/效果显示/战绩页；
                       会等到人类首个可操作阶段（进攻或防御）直接截选中态；若人类首次操作前已分胜负则换一局；
                       战绩页由脚本自动打完真实对局后截图）
    debug1.gd          单局日志调试（临时排查用；正式验证不依赖它）
  *.gd.uid             Godot 自动生成的脚本 UID 文件，勿手改、勿删（新建脚本会自动生成，删脚本要连 .uid 一起删）
```

## server/ 服务结构

```
server/                Ubuntu 玩家数据存储服务（2026-11-12 交付，2026-11-14 复核；**2026-11-25 起暂缓，保持原样**；独立于游戏客户端，零第三方依赖）
  README.md            中文使用与部署入口：本机测试、Ubuntu 24.04 安装/systemd、配置、备份恢复、排错、验收清单
  API.md               冻结 HTTP 契约：/api/v1 字段、错误码、限流、数据口径（改接口先改它）
  app/                 服务代码：配置（命令行 > 环境变量 > 默认）、鉴权（token 哈希）、SQLite 存储层、输入校验、HTTP 路由/限流、错误与日志
  tests/               unittest 单元测试：存储/幂等/级联删除/并发 + 输入校验 + HTTP API/配置 + 部署脚本（131 项，2 项 POSIX-only 跳过）
  deploy/              Ubuntu 部署：systemd unit/timer、环境变量样例、backup.py/restore.py、install-ubuntu.sh
  tools/smoke.py       跨平台 HTTP 冒烟：自起临时服务与临时库，走注册/查询/上报/去重/批量/改名/删除
```

- 入口 `python3 -m app`（HTTP 层 `app/main.py`）；本机复核（2026-11-14）：`python -m unittest discover -s tests -v` 131 项 OK（2 项 POSIX-only 跳过）、`python tools/smoke.py` 输出 `SMOKE OK`、`python -m compileall app tests tools` 退出码 0。文档 `server/README.md` 含审查者路径/设计取舍/数据模型/术语/FAQ，契约见 `server/API.md`。
- 运行时生成的 `data/`、`*.sqlite3` 与 `__pycache__/` 为本地产物，不要提交版本库。
- 默认只监听 `127.0.0.1:8080`；公网入口/排行榜/数据保留期待用户裁决，Godot 客户端尚未接入；Ubuntu 24.04 的 systemd/备份/恢复待 VM 验收（见 `server/README.md` §11）。

## 提交前检查（代码提交用）

- [ ] 无头链全绿：`keywords.gd`（`pass=1206 fail=0`）、`sim.gd`（12 行）、`ui_play.gd`（`DONE`）、`ui_smoke.gd`（`OK`）、`soak.gd`（`SOAK OK`）、`fuzz_actions.gd`（`FUZZ OK`）；开窗 `ui_stress.gd`（`UI STRESS OK`）；新增 `class_name` 先跑 `--import`。
- [ ] 改布局/字号/演出：跑 `shot.gd` 六图并 Read 核对；视觉最终由用户开窗确认。
- [ ] 规则/时序改动：`DESIGN.md` §9/§10/§11 同步；数值改动已获用户批准，并同步 xlsx 与 `gamedata.gd`。
- [ ] 文档计数同步：`CONTEXT.md` §7、`DESIGN.md` §11、`AGENTS.md`、本文件、`GODOT_GUIDE.md`。
- [ ] 无临时文件：`game/tests/probe_*.gd`（含 `.gd.uid`）、`_frames/probe_*.png`、xlsx 解包产物；`_xlsx/original-backup.xlsx` 与 `_frames/ex*_*.jpg` 保留。
- [ ] 服务端：`cd server` → `python -m unittest discover -s tests -v`（131 项 OK、2 项跳过）→ `python tools/smoke.py`（`SMOKE OK`）→ `python -m compileall app tests tools`；改接口先改 `server/API.md`；不提交 `server/data/`、`*.sqlite3`、`__pycache__/`。
- [ ] 不带 `~$*.xlsx`（Excel 锁文件）；未改只读 `参考素材/`；未提交 `.godot/`、导出产物。
- [ ] git commit/push 由用户执行；AI 不执行 git 操作、不跟踪仓库状态。

## 维护约定

- 参考素材（截图/xlsx/构思.txt，以及曾在的 mp4）只读；AI 产物进 `game/` 与文档。
- scratch 目录 `_frames/`、`_xlsx/` 已清理至最小（2026-10-24）：`_xlsx/original-backup.xlsx` 永久保留勿删、`_frames/ex*_*.jpg` 是唯一动态参考勿删；日后产生的临时产物（探针截图、解包文件等）用完即删，删除前跟用户说一声。
- 参考素材新增/改名时，在「参考素材/」明细表登记或更新一行；根目录新增文档/目录时，在本表登记一行；`game/` 新增脚本/场景/测试时，在上面的工程结构里补一行；临时探针脚本（`game/tests/probe_*.gd`）用完即删，不登记。
- **改完东西要同步哪些文档**：数值 → `DESIGN.md` §4/§6 + `gamedata.gd`；规则/时序 → `DESIGN.md` §1/§3/§9 + §10 记一条决策；断言数或 sim 胜率变化 → `CONTEXT.md` §7 + `DESIGN.md` §11 + `AGENTS.md` + 本文件 + `GODOT_GUIDE.md`（五处都写了数字）；新增文件 → 本表登记。
- 文档冲突时以 `DESIGN.md` 为规则权威、`参考素材/角色，骰子参数.xlsx` 为数值权威；其余以更新时间新者为准。
- 本仓库已用 git 跟踪（分支以仓库当前状态为准）：`.gitignore` 忽略 `.godot/`、`*.exe` 等引擎/导出产物；git 提交与仓库状态由用户全权负责，AI 不擅自提交、不跟踪 git 状态。