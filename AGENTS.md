# AGENTS.md — 智能体接手入口（科大战力党）

> 任何 AI 编程工具 / 智能体打开本文件夹时，先读完本文件，再按"阅读顺序"深入。
> 本文件是速查与硬规则；细节以仓库内文档为准（冲突时：DESIGN.md > CONTEXT.md > 本文件）。

## 项目一句话

用户自研骰子对战游戏「科大战力党」：Godot 4.7.2 + GDScript，1v1 攻防选骰比点数，借鉴《崩坏：星穹铁道》「上骰了！战力党！」，角色为科大院系。工程在 `game/`。

## 阅读顺序

1. `CONTEXT.md` — 背景、协作约定、环境事实、代码架构、**§5.1 代码索引（要改 X 去哪个函数）**、§5.2 玩家字段词典、Battle 分步 API、进度、踩坑、交接指引
2. `DESIGN.md` — 冻结规则全文、关键词定义、角色/曜彩表、**§5.1 数据驱动合法取值 + §5.2 已知实现缺口**、§9 已定约定、§10 决策日志、§11 进度与待办分级（**改规则必须先改它**）
3. `README.md` — 文件夹每个文件/目录的用途登记表（新增文件必须登记一行）
4. `GODOT_GUIDE.md` — 本机 Godot 启动方式、无头验证与期望输出、截图自检、临时探针规范、API 踩坑、排错表

## 接手清单（新智能体 5 分钟上手）

1. 按阅读顺序读完四份文档（本文件 + CONTEXT + DESIGN 必读）。
2. 跑验证链确认环境：`--import` → `keywords.gd`（应 `KEYWORDS pass=1122 fail=0`）→ `sim.gd`（12 行胜率表）→ `ui_play.gd`（应 `UI PLAY DONE`，约 1 分钟）→ `ui_smoke.gd`（应 `UI SMOKE OK`）。命令与期望输出见下。
3. 记住硬规则（尤其：数值归用户、随机走 Crypto、不用 autoload、改完必验证、不擅自 commit）。
4. 有疑问先查 DESIGN §9 已定约定 / §10 决策日志——十一轮 UI 反馈与全部裁决都有记录；查不到再问用户，**不要自己定规则**。
5. 动手前先看两张表：DESIGN §5.1（数据驱动被动只能用哪些字符串，`match` 未命中会静默失败）与 CONTEXT §5.1（要改某功能去哪个函数）；改核心逻辑再查 CONTEXT §5.2（玩家状态字段词典）。
6. 待办清单在 DESIGN §11（分 P1~P4，含验收口径与"谁拍板"）。其中 **P2 AI 强度改进是用户明确要求"届时提醒"的**——用户提起可玩性/难度时主动提。

## 硬规则（违反即破坏用户信任）

- **数值所有权归用户**：`角色，骰子参数.xlsx` 是唯一数值依据。改任何数值/角色/曜彩参数 = 先列方案给用户批准，批准后同步改 xlsx 与 `game/scripts/core/gamedata.gd`。
- **不做平衡调整**：机制与数值对齐米哈游官方版本（用户 2026-10-11 确认），离群值仅记录不处理。已知离群（2026-10-16 复跑）：信息 75.0%、工程 74.2%、核科学 74.2%、管理 61.4% 偏高，数学 14.4% 偏低（Crypto 无种子，逐次波动数个百分点属正常）。
- **随机数必须走 Crypto**（`Crypto.new().generate_random_bytes`，Godot 4.7 方法名；禁止加种子通道）。
- **不要用 autoload**：`-s` 无头模式不注册 autoload；跨场景状态用静态类 `GameStateData`。
- **exe 全名调用**：`Godot_v4.7.2-stable_win64.exe`（在 PATH 中；不要简写、不要改名）。
- **改完代码必须无头验证再汇报**；无法验证时明说，不得暗示成功。
- **用户反馈逐条落实**，并追加到 `DESIGN.md` §10（决策日志）与 §11（进度）；用户用中文交流，界面文案全中文。
- 界面介绍文字（角色/曜彩）必须与 Excel 原文一致（gamedata.gd 的 intro 字段），不得简写。
- 参考素材（截图/xlsx/构思.txt）只读；scratch 目录 `_frames/`、`_xlsx/` 中除 `original-backup.xlsx` 外可清理（删前跟用户说一声）。
- **不擅自 git commit / push、不擅自改 `.gitignore`**：提交时机由用户决定；`~$*.xlsx`（Excel 锁文件）未被忽略，别提交进去。
- **不擅自改 xlsx**：默认只读解析（Python zipfile）；确需写入先取得批准并备份。
- **外部结论一律复核**：第三方审计报告、网络抓取资料先对代码与 xlsx 核实再采信（2026-10-15 一份审计报告声称"已有裁决"，查证无实据）。
- **规则空白报裁决**：文档没定义的情形列方案给用户拍板，批准后改代码并回写 DESIGN §9/§10。

## 命令速查（cwd 任意；本机 cmd/Git Bash 均可，勿加 Unix 管道）

```bash
cd "D:/warrior party/game"
Godot_v4.7.2-stable_win64.exe --headless --path . --import        # 新增 class_name 后必跑（数十秒）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/keywords.gd # 期望 KEYWORDS pass=1122 fail=0（<1s；改核心结算必跑）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/sim.gd      # 期望 12 行胜率表、stderr 无 Out of bounds（约 1-2s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_play.gd  # 期望 UI PLAY DONE winner=N round=N（约 1 分钟）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_smoke.gd # 期望 UI SMOKE OK（<1s）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/shot.gd     # 布局截图自检（开窗，输出 _frames/shot_*.png 五张）
Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"      # 开窗游玩
```

标准流程：改代码 → import（如新增 class_name）→ keywords + sim + ui_play（+ ui_smoke）→ 改布局/字号加跑 shot.gd 并 Read 截图核对 → 汇报并提醒用户开窗确认视觉。

## 常见任务怎么做（菜谱）

| 任务 | 步骤 |
|---|---|
| 改角色/曜彩**数值** | 列方案给用户批准 → （用户或经批准后 AI）改 xlsx → 改 `gamedata.gd` → 改 DESIGN §4/§6 → 若 keywords 里有写死该数值的断言一并改 → 跑全链 → 把 sim 胜率变化贴给用户（**不调参**） |
| 改**规则/时序** | 先改 DESIGN（§1/§3/§9）→ 改 `battle.gd`（注意 §5.1 合法取值、结算顺序：改骰点的效果必须在求和前）→ keywords 加/改断言 → 全链 → §10 记一条 |
| 加**新关键词/效果** | `gamedata.gd KEYWORDS` 加定义（照 DESIGN §3 原文）→ `battle.gd apply_fx()` 加 `op` 分支（必要时 `eval_cond()` 加条件）→ `battle_ui.gd _fx_text()/_fx_name()` 加中文名 → 图鉴自动收录 → keywords 加断言 → 全链 |
| 加**新角色/新曜彩** | 用户先给 xlsx 数据 → `gamedata.gd` 加条目（intro 照录原文）→ 选卡界面自动列出（`select_ui.gd` 遍历 `GameData.CHARACTERS/YAOCAI`）→ 检查 `_die_fx_hints` 是否需为新条件加标注 → keywords 加断言 → sim 局数会变（每角色 132 局、总 792 局是按 12 角色算的）→ 文档同步。**注意默认选中项是硬编码**：`select_ui.gd`（`physics` / `网络渗透`）与 `game_state.gd`，删改这两项要一起改 |
| 改**界面布局/字号** | 改 `battle.tscn` 或 `battle_ui.gd`（坐标见 CONTEXT §5 布局段）→ 跑 shot.gd → Read 五张 png 核对 → 请用户开窗确认 |
| 查**某个数值为什么是这个** | Grep `battle.gd` 对应函数（索引见 CONTEXT §5.1）→ 对照 DESIGN §1/§3/§9 与 §10 决策日志 |
| 写**临时探针**验证猜想 | 新建 `game/tests/probe_*.gd`（`extends SceneTree`，末尾 `quit(0)`）→ 无头跑 → **验证完删掉脚本与同名 `.gd.uid`**（规范见 GODOT_GUIDE §3b） |

## 架构速览

- 纯逻辑层 `game/scripts/core/`：die / gamedata(数据+intro) / game_rng(Crypto) / battle(分步回合 API+结算时序) / ai(贪心) / driver(同步编排) / game_state(静态跨场景)。
- UI 层 `game/scripts/ui/`：select_ui / battle_ui(人类=玩家0 异步编排；战绩汇总页) / dice_roll(3D 投骰演出) / glossary(关键词图鉴弹窗)。
- 回合编排：`round_open()` → 每方 `roll_phase(idx)` → 可选 `roll_yaocai` → 攻方 `do_reroll(idx, dice数组)`×2（可选任意颗至全部）→ `commit_selection`（确认即锁定）→ `settle()` → `round_close()`（末尾**无条件** `round += 1`）。
- 结算时序：跃升/骇入先改点（先跃升后骇入：骇入会把跃升刚升上来的骰打掉，用户裁决 2026-10-16）→ 重算攻防值 → 瞬伤已即时 → 结算开始荆棘 → 主伤害/连击/洞穿/反击 → 结算后中毒；**一方 KO 后所有效果均不再结算**（连击/反击/受伤被动/虹吸/中毒/回合结束被动/荆棘/commit 阶段被动与曜彩面效果/曜彩投掷均有 `winner < 0` 守卫，用户裁决 2026-10-16）；HP 钳制 ≥0，无平局。
- 布局（1080p 基准，canvas_items 拉伸）：敌条顶部（含状态栏）/ 敌骰行 / 横幅+预期效果上 / 投骰演出居中透明 / 骰子候选中下（含逐骰效果标注）/ 玩家条底部（含状态栏）/ 操作按钮右列 / 曜彩弹窗右上。详见 CONTEXT.md §5。

## 当前状态（2026-10-16）

v1 单机 PVE 已可完整游玩（选卡 → 战斗 → 终局战绩页），验证链全绿（keywords `pass=1122 fail=0`）。

- 十一轮 UI 反馈全部落实并验证；2026-10-13 交接验证 + 全量审计修复五处缺陷 + 用户两条规则裁决（等级上限=普通骰数；受伤被动仅防御正式结算逐次）。
- 2026-10-14 功能增补：终局战绩汇总页、局内关键词图鉴、骰型配色主题化、装饰随机改 Crypto。
- 2026-10-15：按 xlsx 将核科学技术学院骰池对齐官方三月七（d8×2+d6×3 → d6×2+d4×3）、11 个曜彩骰全部改为科大主题新名（蓄力→理实积淀 等，映射见 DESIGN §10）；同日晚审计复核修复战绩页总回合数差一、攻/防等级徽章不刷新、补曜彩骰 3D 演出，并按用户裁决为被击倒方受伤被动加 `winner<0` 守卫（keywords 1090 → 1094）。
- 2026-10-16：五份文档全面校订（修正场景数与失效引用、新增代码索引/字段词典/数据驱动合法取值/待办分级），代码零改动。
- 2026-10-16（续）：用户裁决跃升与骇入同时结算时**先跃升后骇入**（骇入把跃升刚升上来的骰打掉，见 DESIGN §9/§10）；keywords 新增「跃升骇入顺序」回归场景，断言 1094 → 1098（24 → 25 组）。
- 2026-10-16（续二）：用户裁决**一方 KO 后所有效果均不再结算**（补齐虹吸/中毒/回合结束被动 `winner<0` 守卫）；修复 shot.gd 截图路径写死旧副本的回归（改为随工程位置推导）；keywords 断言 1098 → 1110（25 → 26 组）。
- 2026-10-16（续三）：审计复核补齐「KO 后效果停止」两处覆盖缺口——settle 荆棘循环与 commit 阶段（瞬伤/被动/曜彩面效果）补 `winner<0` 守卫，被击倒方曜彩不可用不消耗（usable/reason/roll_yaocai，界面原因「对局已结束」）；keywords 断言 1110 → 1122（26 → 27 组）。
- 待办（详见 DESIGN §11）：P1 界面打磨（瞬伤/荆棘/中毒飘字）、P2 AI 强度改进（暂缓另议，**届时提醒用户**）、P3 局域网 PVP（中期）/ 天气（后期）/ 音效暂不加、P4 数据仓库杂项（scratch 可清理）。平衡不做调整（数值对齐官方版）。
