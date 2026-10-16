# 科大战力党 — 上下文交接文档（CONTEXT.md）

> 用途：切换模型 / 软件 / 设备时的唯一接手入口。读完本文件 + `DESIGN.md` 即可继续工作。
> 最后更新：2026-10-16。规则细节以 `DESIGN.md` 为准，数值以 `角色，骰子参数.xlsx` 为准，本文件负责"背景、约定、架构、代码索引、进度、坑"。
> 只想知道「改某功能去哪个文件」→ 直接看 §5.1 代码索引；只想知道「别踩什么雷」→ §2 约定 + §8 坑。

## 1. 项目是什么

- 用户自研骰子对战游戏 **科大战力党**（Godot 4.7，GDScript），借鉴《崩坏：星穹铁道》「上骰了！战力党！」玩法，角色为科大院系。
- 1v1 攻防：双方按攻击/防御等级选骰，点数和比大小扣血，关键词（连击/洞穿/反击/骇入/力场/荆棘/中毒/韧性/力量/不屈/跃升/瞬伤/虹吸/治愈/升级/命定）与角色被动、曜彩骰面效果叠加。
- v1 范围：单机 PVE（贪心 AI）、12 角色、11 曜彩骰、2D 界面 + 仅投骰过程 3D。中期局域网 PVP、后期天气模块。
- **当前状态（2026-10-16）**：v1 已可完整游玩（选卡 → 战斗 → 终局战绩页），验证链全绿（keywords `pass=1110 fail=0`）；下一步以界面打磨与 AI 强度改进为主，详见 `DESIGN.md` §11 待办分级清单。

## 2. 协作约定（必须遵守）

- **用户是设计师，拥有全部数值所有权**：`角色，骰子参数.xlsx` 是数值唯一依据；改任何数值必须先列方案给用户批准，批准后同步改 xlsx 与 `gamedata.gd`。
- **不做平衡调整**：机制与数值对齐米哈游官方版本（用户 2026-10-11 确认），离群值仅记录不处理；sim（随机曜彩）定位为回归监控。已知离群（2026-10-16 复跑）：信息 75.0%、工程 74.2%、核科学 74.2%、管理 61.4% 偏高，数学 14.4% 偏低（Crypto 无种子，逐次波动可达数个百分点；核科学经骰池对齐官方三月七后由 ~92-98% 回落）。
- **严格按用户指令执行**：用户给的命令/exe 名/流程照原样用；不要因自己探测失败就宣称工具不可用。
- **改完代码必须无头验证再汇报**（命令见 §6）；无法验证时要明说，不得暗示成功。
- **规则空白不擅自定**：遇到参考素材与文档都没定义的情形（例：被击倒方是否还触发「受到伤害」被动），先查 `DESIGN.md` §9 已定约定 / §10 决策日志；查不到就把方案与影响列给用户裁决，批准后改代码并回写 §9/§10。
- **外部结论一律复核**：第三方审计报告、网络抓取资料（如曾出现的《银河战力党-官方资料汇编.md》，用户明示可能有误、且已不在仓库）必须先对代码与 xlsx 核实再采信。2026-10-15 一份外部审计报告声称"已有裁决"，经查 DESIGN/keywords 无实据，按未定义规则重新报裁决。
- **git 由用户主导**：仓库已跟踪（分支 main，`.gitignore` 为 Godot 4 标准模板）；git 提交与仓库状态由用户全权负责，AI 不执行 git 操作、不跟踪不汇报 git 状态，也不擅自改 `.gitignore`（用户 2026-10-16 指示）。
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
| `README.md` | 目录结构说明：根目录与 game/ 每个文件/文件夹的用途登记、维护约定 |
| `GODOT_GUIDE.md` | 本机 Godot 4.7.2 使用手册：启动方式、无头验证与期望输出、截图自检、临时探针规范、API 踩坑、排错表 |
| `角色，骰子参数.xlsx` | **数值权威**：sheet1 角色属性（12 行）、sheet2 骰子属性（11 曜彩骰，B 列面表已录入）。默认只读 |
| `科大战力党-构思.txt` | 用户原始构思（Godot、Crypto 随机、2D+投骰3D、贪心 PVE、中期局域网、后期天气） |
| `效果/page1~4.jpg` | 官方关键词解释截图 15 条（游戏内共 18 条，另 3 条用户补充，全文见 DESIGN §3） |
| `曜彩骰定义/*.jpg` | 11 张曜彩骰面表与使用条件截图，gamedata 面表录入依据；**文件名仍为旧曜彩名**（只读素材，用户决定不改），新名对照见 README |
| `进攻方选骰子.png` | 原作战斗界面截图（选骰态）——整体布局与逐骰效果标注的对照依据 |
| `进攻方使用曜彩骰时.png` | 原作战斗界面截图（曜彩弹窗态）——曜彩六面表弹窗布局的对照依据 |
| `防御时显示界面.png` | 原作战斗界面截图（我方防御时）——第八轮反馈「显示敌方所选骰+总计」的对照依据 |
| `未选中时显示可能的效果.png` | 原作战斗界面截图（未选中态）——第十一轮反馈「逐骰效果标注」的对照依据 |
| `选中时高亮显示获得效果.png` | 原作战斗界面截图（选中高亮）——第十一轮反馈「已选触发效果高亮」的对照依据 |
| `LICENSE` | GNU GPL v3 |
| `.gitignore` | Godot 4 标准模板（`.godot/`、`*.exe`、导出产物、`*.tmp` 等）；**未忽略 Excel 锁文件 `~$*.xlsx`** |
| `game/` | Godot 4.7.2 工程（可执行内容全在这里），结构见 §5 |
| `_frames/` | scratch：原作录屏抽帧 `ex1_*.jpg`(8)/`ex2_*.jpg`(14)、shot.gd 输出的 `shot_*.png`(5)、历史探针图 `probe_*.png`(11，可删) |
| `_xlsx/` | scratch：xlsx 解包产物与解析记录；**`original-backup.xlsx` 是写 B 列前的原表备份，永久保留** |

> 已不在仓库但文档里可能还被提到的：`示例1.mp4` / `示例2.mp4`（原作参考录屏，已移除，仅存 `_frames/ex*_*.jpg` 抽帧）；`银河战力党-官方资料汇编.md`（网络抓取件，用户明示可能有误、非权威，xlsx 优先）。
> 根目录出现 `~$角色，骰子参数.xlsx` 表示用户 Excel 正开着该表：此时替换 xlsx 会报 WinError 5，且不要把它提交进 git。

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
                           再求和、并列目标随机取）；damage() 钳制 HP≥0
    ai.gd                  AIController：枚举选骰贪心；choose_reroll 返回勾选数组
    driver.gd              Driver：同步编排（模拟用）run_round/run_game
    game_state.gd          GameStateData：静态变量 char_id/yc_name（跨场景）
  scripts/ui/
    select_ui.gd           选卡：1 角色 + 1 曜彩骰（化学禁曜彩）；信息栏显示骰池构成与 Excel 原文介绍；少年班按钮显示「攻?」
    battle_ui.gd           战斗界面：人类=玩家0 异步编排；布局分区见 battle.tscn；
                           命定自动锁定；升序排骰；选中即重投（可选任意颗至全部）；
                           结算分行显示；扣血闪红+飘字；效果文案中文映射；曜彩六面表弹窗
                           （开关式，不可用时按钮副行与弹窗内明示中文原因）；信息条名字右侧
                           攻/防等级角标与状态栏（荆棘待结算/力场/不屈/中毒/力量/跃升）；
                           选骰效果预览（已选触发金色汇总行＋逐骰点数下方金色效果标注，
                           少年班/计数类/与骰值无关条件不标注）；
                           确认按钮整合 已选/需选 计数；
                           敌方提交选骰后骰子行只显示其所选骰+行尾「总计 N」；
                           攻方选骰期间敌方行显示守方上回合投出的骰子；
                           曜彩骰按钮底部标注当前面技能（金色有技能/灰色无效果）；
                           骰型配色（4 天蓝/6 紫/8 橙/12 与曜彩近黑+蓝紫）；
                           关键词图鉴弹窗（glossary.gd，效果名点击展开）；
                           终局战绩汇总页（HP 曲线/伤害与触发统计，battle.gd stats 支撑）；
                           曜彩骰 3D 演出（_animate_yaocai，演出期间锁输入）；
                           攻/防等级徽章随 refresh() 更新（_refresh_badges/_def_level_shown）
    glossary.gd            GlossaryPanel：关键词图鉴弹窗（定义照录 DESIGN §3 / GameData.KEYWORDS）
    dice_roll.gd           投骰 3D 演出（SubViewport 透明背景，约 2.3s，与选骰框不重叠）
  scenes/select.tscn, battle.tscn
  tests/
    sim.gd                 792 局 AI vs AI 回归监控模拟（随机曜彩）
    keywords.gd            关键词级断言测试：无 RNG 摆定骰面直接断言结算数值
                           （26 组场景 1110 断言，改核心结算必跑，应 pass=1110 fail=0）
    ui_play.gd             无头假人：走人类 UI 全路径（含重投、曜彩使用）
    ui_smoke.gd            场景实例化冒烟
    shot.gd                布局截图自检（开窗跑，输出 _frames/shot_*.png 五张：选卡/战斗/曜彩弹窗/图鉴/战绩页）
    debug1.gd              单局日志调试
```

**战斗界面布局（1080p 坐标，参照原作截图定稿）**：敌方信息条 y16–160 居中 → 敌方骰子行 y172–242（仅敌方本回合投出后显示）→ 横幅 y252–312 / 需选信息 y318–368 → 结算 Big y380–560 → 回合数左中 → 投骰演出 RollView y380–680 居中透明 → 骰子候选 y720–840 居中 → 日志 y856–924 → 玩家信息条 y936–1064 → 操作按钮右列 x1620–1880、y560–1040 → 曜彩弹窗右上 x1360–1880、y100–560。

**Battle 分步 API（回合编排顺序，用户指定）**：
`round_open()`（清 sel、攻方重投=2，不投骰）→ 每方阶段：`roll_phase(idx)` → 可选 `roll_yaocai(idx,phase)` → 攻方可 `do_reroll(idx, dice数组)` ×2 → `commit_selection(idx,phase,sel)`（确认即锁定）→ 双方完成后 `settle()` → `round_close()`。
结算时序：瞬伤立即 → 结算开始荆棘 → 主伤害/连击/洞穿/反击 → 结算后中毒；每次扣血即查 HP，无平局。

### 5.1 代码索引（要改 X 去哪个函数）

> `core/` = `game/scripts/core/`，`ui/` = `game/scripts/ui/`。行号会变，故只给函数名（用 Grep 定位）。

| 想改 / 想查 | 位置 |
|---|---|
| 角色数值、被动、曜彩面表、关键词文本 | `core/gamedata.gd`（`CHARACTERS` / `YAOCAI` / `KEYWORDS`）；数值须先看 xlsx 与 DESIGN §4/§6 |
| 被动条件判定 | `core/battle.gd eval_cond()`（合法 `c.t` 见 DESIGN §5.1） |
| 被动 / 曜彩面效果执行 | `core/battle.gd apply_fx()`（合法 `fx.op` 见 DESIGN §5.1） |
| 攻/防等级与上限 | `battle.gd atk_eff() / def_eff() / selection_count() / _pool_n()`；`atk_set`（工程）优先于 `atk_perm`，一律按普通骰数封顶 |
| 一回合的结算流程 | `battle.gd settle()`（顺序注释在函数上方）；改骰点的 `_apply_leap()` / `_apply_hacks()` 必须在求和之前 |
| 「受到伤害」被动 | `battle.gd _eval_on_damaged()`——仅 settle 的主伤害/连击第二击后调用，两处都有 `winner < 0` 守卫 |
| 扣血 / 治疗 / 胜负判定 | `battle.gd damage()`（钳 HP≥0、设 winner、写 stats）/ `heal()` |
| 曜彩可用性与中文原因 | `battle.gd yaocai_usable()` / `yaocai_reason()`（两者口径必须严格一致，keywords 有一致性断言） |
| 回合收尾（buff 到期、曜彩消失、攻守互换、`round += 1`） | `battle.gd round_close()` |
| 战绩统计口径 | `battle.gd stats`（`dmg_dealt` / `dmg_taken` / `fx`），由 damage / apply_fx / roll_yaocai / do_reroll 写入 |
| AI 选骰 / 重投 / 曜彩 | `core/ai.gd choose_selection() / choose_reroll() / choose_yaocai()`，组合枚举 `_combos()`；只接收己方 `p` |
| 无头对局编排（sim 用） | `core/driver.gd run_round() / run_game()`（80 回合上限按 HP 判定） |
| 人类对局编排（异步） | `ui/battle_ui.gd _run() → _round_ui() → _phase_ui() / _ai_phase() / _human_phase()` |
| 界面中文文案（效果名/日志） | `battle_ui.gd _fx_text() / _fx_name() / _fx_list_text() / _log_text()` |
| 逐骰效果标注、预期效果汇总行 | `battle_ui.gd _die_fx_hints() / _refresh_preview()` |
| 信息条徽章与状态栏 | `battle_ui.gd _add_stat_badges() / _refresh_badges() / _atk_badge_text() / _def_level_shown() / _status_text()` |
| 终局战绩页 | `battle_ui.gd _show_summary() / _summary_text()`（总回合数用 `battle.round - 1`，因 round_close 无条件 +1） |
| 骰子按钮外观与配色 | `battle_ui.gd _style_die_button() / _die_colors() / _die_text()`；3D 侧 `ui/dice_roll.gd TIER_COLOR/TIER_TEXT` |
| 3D 投骰演出 | `ui/dice_roll.gd roll(dice_a, dice_b)`；曜彩演出走 `battle_ui._animate_yaocai()` |
| 关键词图鉴 | `ui/glossary.gd`（`GlossaryPanel.kw_bbcode()` 把任意文本里的效果词变成可点击链接） |
| 选卡界面 | `ui/select_ui.gd`（骰池文案 `_pool_text()`、少年班「攻?」`_atk_text()`、化学禁曜彩 `_refresh_yc()`） |
| 跨场景传参 | `core/game_state.gd GameStateData.char_id / yc_name`（静态类，不用 autoload） |
| 随机数 | `core/game_rng.gd GameRng.randi_range() / coin_flip()`（仅 Crypto，无种子通道） |
| 骰子与升级链 | `core/die.gd`（`CHAIN` / `upgrade()` / `is_yaocai()` / `face_points()`） |

### 5.2 玩家状态字段词典（`battle.gd _make_player()` 返回的 Dictionary）

改核心逻辑前先查这张表，字段互相牵连（尤其 pending → round 的转换时机）。

| 字段 | 含义与生命周期 |
|---|---|
| `cfg` `hp` `hp_max` `dice` | 角色配置引用、当前/上限 HP、本回合实际存在的骰（常规 5 颗 + 已投出的曜彩） |
| `atk_perm` `def_perm` | 永久等级加成（AI 学院受伤≥8 双 +1、数学洞穿 +1），经 `atk_eff`/`def_eff` 按普通骰数封顶 |
| `atk_set` | 攻击等级**覆盖**值（工程触发后置 5）；`>=0` 时优先于 `cfg.atk + atk_perm` |
| `def_pending` `counter_pending` | 「下次防御」类临时效果（网安 防御等级+3 与反击）；防御 `commit_selection` 时 `counter_pending → counter_round`、`def_pending` 清零 |
| `counter_round` | 本回合反击生效标志，settle 末尾按 `def_value > atk_value` 判定差值回打 |
| `strength` | 力量层数组 `[{n, expire}]`：`expire = round+1` 为下回合到期（理实积淀），`-1` 为永久（地空）；`round_close` 清理 |
| `toughness` | 韧性层数，计入防御值；**当前无授予通道**（见 DESIGN §5.2） |
| `thorns` | 荆棘层数，结算开始扣自身血后清零（通宵鏖战加给自身） |
| `poison` | 中毒层数，结算后扣血并 -1（一方 KO 后不再结算）；**当前无授予通道** |
| `field` `unyielding_round` `unyielding_used` | 力场（挡常规伤害、洞穿可破）、本回合不屈、不屈是否已用（生命学院仅 1 次）；前两者 `round_close` 清除 |
| `leap_perm` `leap_round` | 永久跃升（管理/工程）→ `round_open` 复制到 `leap_round`，`settle` 前对攻守各触发一次 |
| `hack_pending` | 待结算骇入（信息学院被动 / 网络渗透面），由 `_apply_hacks()` 消费 |
| `yc_name` `yc_uses` `yc_rolled` `yc_triggered` | 携带曜彩名、整局剩余次数、本回合是否已投、已触发面效果次数（管理被动计数用） |
| `accum` | 自身历回合攻击值+防御值累加（工程 `accum_ge` 条件），`round_close` 累加 |
| `face_counts` | `{1: n, 4: n}`——选定过的 1 点 / 4 点累计次数（顶刊论文 / 重复试验解锁条件），`commit_selection` 写入 |
| `sel` `rerolls` | 本阶段已锁定的选骰数组、本回合剩余重投次数（`round_open` 给攻方置 2） |

## 6. 运行与验证命令（含期望输出与实测耗时）

```bash
cd "D:/warrior party/game"
Godot_v4.7.2-stable_win64.exe --headless --path . --import          # 新增 class_name 后必跑（数十秒，无关键输出）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/keywords.gd  # 期望 KEYWORDS pass=1110 fail=0（<1s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/sim.gd       # 期望 12 行胜率表、stderr 无 Out of bounds（约 1-2s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_play.gd   # 期望 UI PLAY DONE winner=N round=N（约 1 分钟，逐帧驱动）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_smoke.gd  # 期望 UI SMOKE OK（<1s）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/shot.gd          # 布局截图自检（开窗，非 headless；无 stdout，看 _frames/shot_*.png）
Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"        # 开窗游玩（最终视觉确认靠用户）
```

- 标准流程：改代码 → （新增 class_name 才 import）→ keywords + sim + ui_play（+ ui_smoke）→ 改布局/字号/演出加跑 shot.gd 并 Read 五张图核对 → 汇报并提醒用户开窗确认视觉。
- **不要给这些命令追加 Unix 管道/重定向**（`| tail`、`2>/dev/null` 等）：部分环境的 Bash 工具实为 cmd.exe，会报 "'tail' 不是内部或外部命令"。要看完整输出就整条直跑。
- 控制台打印中文可能乱码（GBK 控制台）：需要读大段中文输出时，让脚本写 UTF-8 文件再用 Read 看。
- keywords/sim 的期望值会随改动变化（断言数、胜率）；改动后把新数字回写到文档（本文件 §7、DESIGN §11、AGENTS、README 四处）。

## 7. 当前进度（2026-10-16）

已完成总览（逐条细节见 DESIGN.md §10 决策日志 / §11 进度）：
- 核心与数据：battle.gd 分步 API 与结算时序（含等级上限=普通骰数、on_damaged 仅防御正式结算逐次且被击倒后不触发）、12 角色/11 曜彩（intro 与 KEYWORDS 照录 Excel/DESIGN）、贪心 AI、Crypto 随机
- 测试：keywords.gd（**26 组场景 1110 断言**，改核心结算必跑，实跑 `pass=1110 fail=0`）/ sim.gd（792 局回归监控，每角色 132 局）/ ui_play.gd / ui_smoke.gd / shot.gd（五张截图自检，输出目录随工程位置推导）
- UI：十一轮反馈全部落实；战斗布局定稿；曜彩六面表弹窗；骰型配色（4 天蓝/6 紫/8 橙/12 与曜彩近黑+蓝紫）；关键词图鉴（无入口按钮，界面内效果词点击展开）；终局战绩汇总页（HP 曲线/伤害/触发统计）；投骰 3D 演出（普通骰与曜彩骰均有）
- 修复与裁决：2026-10-13 等级超池潜伏 bug + 全量审计五处缺陷；2026-10-15 审计复核四处修复；用户三条裁决（等级上限=普通骰数；受伤被动仅防御正式结算逐次；被击倒后不触发受伤被动），均有 keywords 回归覆盖
- 文档：五份文档体系（AGENTS/CONTEXT/DESIGN/README/GODOT_GUIDE）持续同步，2026-10-16 完成一次面向交接的全面校订（修正场景数、清理失效引用、新增代码索引与字段词典）

关键节点回顾：
- 2026-10-11：第九~十一轮反馈落实；骇入失效修复；用户确认平衡冻结（对齐官方版）并授权 AI 工程决策（keywords 测试上线）
- 2026-10-13：交接验证 + 全量审计（五处缺陷修复）；用户裁决关闭审计规则疑点
- 2026-10-14：功能增补（战绩页/图鉴/配色/装饰随机 Crypto）；图鉴按用户反馈改为「无按钮、效果词可点击」；用户决定 AI 强度改进暂缓另议、暂不加音效
- 2026-10-15（白天）：用户以 xlsx 为准将核科学技术学院骰池对齐官方三月七（d8×2+d6×3 → d6×2+d4×3）；按 xlsx sheet2 将 11 个曜彩骰全部改为科大主题新名（蓄力→理实积淀 等）；同步 gamedata/DESIGN/README/keywords/select_ui/game_state 并跑通验证链
- 2026-10-15（晚）：复核用户转来的外部审计报告——修复战绩页总回合数差一、攻/防等级徽章不刷新、补曜彩骰 3D 演出；报告声称的"既有裁决"查无实据，作为规则空白重新报裁决，用户批准后被击倒方受伤被动加 `winner<0` 守卫（keywords 1090 → 1094）
- 2026-10-16：文档校订（本轮，代码零改动）；验证链全绿，sim 复跑离群值与 10-15 同量级；同日用户确认 Excel H 列已更新（xlsx ↔ gamedata `yc_reco` 核对 12 行一致），并明确 git 提交由其全权负责
- 2026-10-16（续）：用户裁决跃升与骇入同时结算时**先跃升后骇入**（10-15 记录的规则空白关闭）；keywords 新增「跃升骇入顺序」场景，断言 1094 → 1098（24 → 25 组场景），验证链全绿
- 2026-10-16（续二）：用户裁决**一方 KO 后所有效果均不再结算**——补齐 settle() 中虹吸（主伤害/连击两处）、中毒（含层数递减）与 round_close() 中回合结束被动的 `winner<0` 守卫；同日修复 shot.gd 五截图版重写时输出路径写死旧副本的回归（改为由工程位置推导并自动建目录）；keywords 新增「KO 后效果停止」场景，断言 1098 → 1110（25 → 26 组），验证链全绿

待办（分级清单与验收口径见 DESIGN.md §11）：等用户开窗 playtest 反馈；P1 界面打磨（瞬伤/荆棘/中毒扣血飘字等）；P2 AI 强度改进（暂缓另议，**开工前须提醒用户**）；P3 局域网 PVP（中期）/ 天气模块（后期）/ 音效暂不加；P4 数据与仓库杂项（scratch 可清理）。平衡不做调整（政策冻结）。

## 8. 踩过的坑（避免重犯）

- GDScript 字典值用 `.get()` 防缺键；`var x := dict.field` 会因 Variant 推断失败，需显式类型。
- `str.replace` 不接受函数回调（Python 习惯会踩）。
- Node 未入树时 `look_at` 报错 → 用 `look_at_from_position`。
- tscn 手写时新增 ext_resource 必须同步改 `load_steps`。
- 模拟/正式共用同一 RNG 通道（Crypto），不要为复现性私加种子（用户禁止）。
- 界面视觉问题（字号、醒目度）无头测不出：改布局/字号先跑 tests/shot.gd 截图自核，再提醒用户开窗确认。
- 读 xlsx 用 Python zipfile 解 `xl/worksheets/sheetN.xml` + `xl/sharedStrings.xml`：单元格 `t="s"` 时 `<v>` 是 sharedStrings 下标，需映射回原文（直接读 `<v>` 会得到数字索引）。
- shot.gd 必须开窗跑（不加 --headless），会闪窗后自动退出，属正常；纯无显示环境跑不了。
- settle() 中改骰点数的效果（跃升/骇入）必须放在攻防值求和之前，否则伤害用旧值——骇入曾因此整体失效（2026-10-11 修复）。
- 攻/防等级可被被动无限累积（数学洞穿+1、AI学院受伤≥8 双等级+1），超过骰池上限会令 AI 组合枚举空数组越界、人类软锁——selection_count 已钳制到可用骰数（2026-10-13 修复）；今后新增「等级+N」类被动时注意此上限。
- `round_close()` **无条件** `round += 1`（终局那一回合也加），所以任何「总回合数」展示都要用 `round - 1`；2026-10-14 重写战绩页时忘了这点，把 10-13 的修复覆盖成差一 bug（10-15 修回）。
- **重写既有 UI 模块前，先读该模块在 DESIGN §10 里的历史修复记录**——战绩页两次翻车都是重写时丢了旧修复。
- 只在 `_ready`/`_refresh_static` 里求值一次的界面元素不会自动更新：凡随对局变化的文本（如攻/防等级徽章）必须存引用并挂进 `refresh()`（2026-10-15 修复）。
- `eval_cond()` / `apply_fx()` 的 `match` 未命中是**静默失败**（返回 false / 什么都不做），条件或效果字符串拼错不会报错、只会"没效果"；新增被动后必须写 keywords 断言确认真的触发了。
- Godot 4.7 的 `RichTextLabel` 没有 `set_bbcode()`：赋 `.text` 并把 `bbcode_enabled = true`；可点击词用 `[url=...]` + `meta_clicked` 信号（图鉴入口即此机制）。
- AI 工具的 Grep 偶发漏报（字符串明明存在却 "No matches found"）：换个 pattern 或直接 Read 文件确认；ripgrep 默认不支持 look-behind（`(?<!x)` 会直接报错），需要"排除某前缀"时改为全量匹配再人工筛。

## 9. 未决事项（等用户输入；当前无阻塞项，v1 可完整游玩）

1. **开窗 playtest 反馈**：2026-10-15 修的攻/防等级徽章成长、曜彩骰 3D 演出、战绩页总回合数，以及此前的图鉴/配色，都需要用户亲眼确认（视觉问题无头测不出）。
2. **AI 强度改进何时启动**：用户 2026-10-14 指示暂缓另议，但要求在提起可玩性/难度时主动提醒；清单见 DESIGN §11 P2。
3. **参考录屏 mp4 已不在仓库**：后续若需对照原作演出/节奏，请用户重新提供（抽帧仍在 `_frames/`）。
4. **scratch 清理**：`_frames/probe_*.png`（11 张历史探针图）与 `_xlsx/` 解包产物可删（`original-backup.xlsx` 永久保留）；删前跟用户确认一句。
5. 所有历史 ⚠ 规则提案均已由用户裁决关闭（见 DESIGN §9/§10），当前没有在途的规则疑点。

## 10. 交接指引（新设备 / 新软件 / 新模型）

1. 把整个 `D:\warrior party\` 文件夹原样拷贝到新设备，或 git clone 本仓库（分支 main）。注意：git 只含已跟踪文件（参考录屏 mp4 从未入库、现已不在磁盘）；`game/.godot/` 可不带（首次 import 自动重建）；`_frames/`、`_xlsx/` 为可清理 scratch（但 `_xlsx/original-backup.xlsx` 建议保留）。
2. 新设备装 Godot 4.7.2 并加入 PATH（保持 exe 全名 `Godot_v4.7.2-stable_win64.exe`，见 GODOT_GUIDE.md §1）；装 Python 3.x（仅解析/改 xlsx 时需要）；ffmpeg（仅重新抽帧时需要）。
3. 打开项目后按顺序读：`AGENTS.md`（硬规则 + 常见任务菜谱）→ 本文件（§5.1 代码索引、§5.2 字段词典、§8 坑）→ `DESIGN.md`（规则与决策日志，尤其 §5.1 合法取值、§9 已定约定、§11 待办）→ 需要细节时 `README.md`（文件清单）/ `GODOT_GUIDE.md`（引擎操作）。
4. 跑一遍 §6 验证链确认环境可用：`--import` → `keywords.gd`（应 `pass=1110 fail=0`）→ `sim.gd`（792 局，每角色 132 局胜率表）→ `ui_play.gd`（应 `UI PLAY DONE`，约 1 分钟）→ `ui_smoke.gd`（应 `UI SMOKE OK`）；改布局再跑 shot.gd 并 Read 五张截图。
5. 继续工作的规矩：数值/规则改动必须先列方案给用户批准并同步 xlsx 与文档；每次用户反馈逐条落实后写入 DESIGN.md §10/§11；改完代码必须无头验证（keywords + sim + ui_play [+ ui_smoke]，改布局加 shot.gd）再汇报，视觉最终由用户开窗确认；不擅自 git commit。
6. 本仓库已纳入 git（分支 main，`.gitignore` 忽略 `.godot/`、`*.exe` 等）：交接可 git clone / 整仓拷贝。git 提交与仓库状态由用户全权负责，AI 不执行、不跟踪。若使用带持久记忆的 AI 工具，其项目记忆应与本文件保持一致；冲突时以仓库内文档为准。
7. shell 注意：部分环境（如 ZCode 本机会话）Bash 工具实为 cmd.exe，Unix 管道（`| tail` 等）不可用，Godot 命令整条直跑即可；控制台中文可能乱码，需要时让脚本写 UTF-8 文件再 Read。
8. 第一次动手前建议先做一件小事验证链路（如把某处文案改一个字→跑 keywords+ui_smoke→改回），确认工具链与权限都正常，再开始正式任务。
