# AGENTS.md — 智能体接手入口（科大战力党）

> 任何 AI 编程工具 / 智能体打开本文件夹时，先读完本文件，再按下面的文档表深入。
> 本文件是速查与硬规则；细节以仓库内文档为准（冲突时：DESIGN.md > CONTEXT.md > 本文件）。

## 项目一句话

用户自研骰子对战游戏「科大战力党」：Godot 4.7.2 + GDScript，1v1 攻防选骰比点数，借鉴《崩坏：星穹铁道》「上骰了！战力党！」，角色为科大院系。工程在 `game/`。

## 5 份文档怎么用

| 文档 | 用途 | 什么时候读 |
|---|---|---|
| `AGENTS.md`（本文件） | 硬规则、命令速查、常见任务菜谱、架构速览 | 每次接手先读 |
| `CONTEXT.md` | 背景、代码架构、§5.1 代码索引、§5.2 字段词典、§5.3 审查入口、§7 进度、§8 踩坑 | 要改代码/查字段/查历史时 |
| `DESIGN.md` | 规则权威、18 关键词、12 角色/11 曜彩、§5.1 数据驱动合法取值、§9 约定、§10 决策日志、§11 待办 | 改规则/数值/看裁决时先读 |
| `README.md` | 文件/目录用途登记表、参考素材清单、game 工程结构、提交前检查 | 找文件/新增文件/交接环境 |
| `GODOT_GUIDE.md` | 启动方式、无头验证与期望输出、截图自检、API 踩坑、排错表 | 跑命令/环境报错/写探针 |
| `server/README.md` + `server/API.md` | 服务端使用部署与冻结接口（**2026-11-25 起暂缓，恢复时再读**） | 仅恢复服务端工作时 |

## 接手清单（新智能体 5 分钟上手）

1. 按阅读顺序读完核心四份文档（本文件 + CONTEXT + DESIGN + README 必读）；改服务端时加读 `server/README.md` + `server/API.md`。
2. 跑验证链确认环境：`--import` → `keywords.gd`（应 `KEYWORDS pass=1207 fail=0`）→ `sim.gd`（12 行胜率表）→ `ui_play.gd`（应 `UI PLAY DONE`，约 1 分钟）→ `ui_smoke.gd`（应 `UI SMOKE OK`）。命令与期望输出见下。
3. 记住硬规则（尤其：数值归用户、随机走 Crypto、不用 autoload、改完必验证、不擅自 commit）。
4. 有疑问先查 DESIGN §9 已定约定 / §10 决策日志——关键裁决与修复都有记录（早期逐轮 UI 细节已压缩）；审查 2026-11-12 / 2026-11-26 代码整理轮看 CONTEXT §5.3（含审查入口与不用重复报的既有取舍）；查不到再问用户，**不要自己定规则**。
5. 动手前先看两张表：DESIGN §5.1（数据驱动被动只能用哪些字符串，`match` 未命中会静默失败）与 CONTEXT §5.1（要改某功能去哪个函数）；改核心逻辑再查 CONTEXT §5.2（玩家状态字段词典）。
6. 待办清单在 DESIGN §11（分 P1~P4，含验收口径与"谁拍板"）。其中 **P3 AI 强度改进是用户明确要求"届时提醒"的**——用户提起可玩性/难度时主动提；P1 稳定性先测试后修复，P2 局域网按 §11 口径推进。

## 硬规则（违反即破坏用户信任）

- **数值所有权归用户**：`参考素材/角色，骰子参数.xlsx` 是唯一数值依据。改任何数值/角色/曜彩参数 = 先列方案给用户批准，批准后同步改 xlsx 与 `game/scripts/core/gamedata.gd`。
- **不做平衡调整**：机制与数值对齐米哈游官方版本（用户 2026-10-11 确认），离群值仅记录不处理。已知离群（2026-11-11 复核）：信息 83.3%、核科学 75.0%、工程 76.5% 偏高，数学 14.4% 偏低（管理 67.4% 仍在历史区间；Crypto 无种子，逐次波动数个百分点属正常）。
- **随机数必须走 Crypto**（`Crypto.new().generate_random_bytes`，Godot 4.7 方法名；禁止加种子通道）。
- **不要用 autoload**：`-s` 无头模式不注册 autoload；跨场景状态用静态类 `GameStateData`。
- **exe 全名调用**：`Godot_v4.7.2-stable_win64.exe`（在 PATH 中；不要简写、不要改名）。
- **改完代码必须无头验证再汇报**；无法验证时明说，不得暗示成功。
- **用户反馈逐条落实**，并追加到 `DESIGN.md` §10（决策日志）与 §11（进度）；用户用中文交流，界面文案全中文。
- 界面介绍文字（角色/曜彩）必须与 Excel 原文一致（gamedata.gd 的 intro 字段），不得简写。
- 参考素材（`参考素材/` 全部内容——xlsx、构思 txt、原作截图/效果/曜彩骰定义）只读；scratch 目录 `_frames/`、`_xlsx/` 已清理至最小：`_xlsx/original-backup.xlsx` 永久保留勿删，`_frames/ex*_*.jpg` 是唯一动态参考勿删，其余临时产物用完即删。
- **git 由用户全权负责**：AI 不执行 git 操作、不跟踪不汇报仓库状态；不擅自改 `.gitignore`；`~$*.xlsx`（Excel 锁文件）未被忽略，提交时别带上。
- **不擅自改 xlsx**：默认只读解析（Python zipfile）；确需写入先取得批准并备份。
- **外部结论一律复核**：第三方审计报告、网络抓取资料先对代码与 xlsx 核实再采信（2026-10-15 一份审计报告声称"已有裁决"，查证无实据）。
- **规则空白报裁决**：文档没定义的情形列方案给用户拍板，批准后改代码并回写 DESIGN §9/§10。
- **服务端数据口径归用户**：`server/` 只存 PVE/PVP 场次与胜场；新增统计字段或修改接口必须先裁决，并先改 `server/API.md`；保持零第三方依赖；不改 `game/`（客户端接入另议）。
- **云服务/战绩存储暂停（2026-11-25 用户决定）**：`server/` 保持原样，不删除、不修改、不继续投入，Ubuntu 验收暂停；恢复前需用户明确指示。
- **稳定性测试不得引入 RNG 种子**：`GameRng` 只有 Crypto；soak/fuzz 复现靠记录动作 + 掷骰结果/快照回放，禁止改 `game_rng.gd` 加 seed。

## 命令速查（cwd 任意；本机 cmd/Git Bash 均可，勿加 Unix 管道）

```bash
cd "D:/warrior party/game"
Godot_v4.7.2-stable_win64.exe --headless --path . --import        # 新增 class_name 后必跑（数十秒）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/keywords.gd # 期望 KEYWORDS pass=1207 fail=0（<1s；改核心结算必跑）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/sim.gd      # 期望 12 行胜率表、stderr 无 Out of bounds（约 1-2s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_play.gd  # 期望 UI PLAY DONE winner=N round=N（约 1 分钟）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_smoke.gd # 期望 UI SMOKE OK（<1s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/soak.gd      # 期望 SOAK OK games=2000 fails=0（约 5-15s）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/fuzz_actions.gd # 期望 FUZZ OK steps≥20000（-- --mode=invalid 另测）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/ui_stress.gd    # 开窗压力测试；--headless -- --mode=lifecycle 只跑生命周期
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/shot.gd     # 布局截图自检（开窗，输出 _frames/shot_*.png 六张，含选中态 shot_dice_selected.png）
Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"      # 开窗游玩

# 服务端（server/，Python 3.10+，零第三方依赖；**2026-11-25 起暂缓，以下命令仅供恢复时参考**；本机用 python，Ubuntu 用 python3）
cd "D:/warrior party/server"
python -m unittest discover -s tests -v      # 服务端单测（现 131 项，2 项 POSIX-only 跳过，应 OK）
python tools/smoke.py                        # HTTP 冒烟（应 SMOKE OK）
python -m compileall app tests tools         # 语法编译检查（退出码 0）
python -m app --db data/store.sqlite3 --port 8080  # 本机启动（默认 127.0.0.1:8080，Ctrl+C 停止）
```

标准流程：改代码 → import（如新增 class_name）→ keywords + sim + ui_play（+ ui_smoke）→ 稳定性阶段加跑 soak/fuzz（+ ui_stress）→ 改布局/字号加跑 shot.gd 并 Read 六张截图核对 → 汇报并提醒用户开窗确认视觉。服务端（**2026-11-25 起暂缓**）：单测 + 冒烟 + compileall；Ubuntu 部署/备份按 `server/README.md` §11 验收。

## 常见任务怎么做（菜谱）

| 任务 | 步骤 |
|---|---|
| 改角色/曜彩**数值** | 列方案给用户批准 → （用户或经批准后 AI）改 xlsx → 改 `gamedata.gd` → 改 DESIGN §4/§6 → 若 keywords 里有写死该数值的断言一并改 → 跑全链 → 把 sim 胜率变化贴给用户（**不调参**） |
| 改**规则/时序** | 先改 DESIGN（§1/§3/§9）→ 改 `battle.gd`（注意 §5.1 合法取值、结算顺序：改骰点的效果必须在求和前）→ keywords 加/改断言 → 全链 → §10 记一条 |
| 加**新关键词/效果** | `gamedata.gd KEYWORDS` 加定义（照 DESIGN §3 原文）→ `battle.gd apply_fx()` 加 `op` 分支（必要时 `eval_cond()` 加条件）→ `battle_ui.gd _fx_text()/_fx_name()` 加中文名 → 效果显示自动收录 → keywords 加断言 → 全链 |
| 加**新角色/新曜彩** | 用户先给 xlsx 数据 → `gamedata.gd` 加条目（intro 照录原文）→ 选卡界面自动列出（`select_ui.gd` 遍历 `GameData.CHARACTERS/YAOCAI`）→ 若新被动用骰值相关条件，把 `c.t` 加进 `battle_ui.HINT_COND_TYPES`（当前白名单 `has_pair`/`pairs_ge`/`all_eq_value`/`all_even`/`all_same`；对子类只标在能凑对的骰下、选中对子即可金；网安 `sum_ge` 与地球 50% 力量按用户裁决不标）→ keywords 加断言 → sim 局数会变（每角色 132 局、总 792 局是按 12 角色算的）→ 文档同步。**注意选卡默认状态**：初始不选中（`GameStateData` 为空），选中角色后自动带出 `yc_reco` 推荐；直接跑 battle.tscn 的兜底组合写在 `battle_ui._ready()`（physics/网络渗透），删改角色时一并检查 |
| 改**界面布局/字号** | 改 `battle.tscn` / `battle_ui.gd`（候选骰外观在 `die_view.gd`；坐标见 CONTEXT §5 布局段）→ 跑 shot.gd → Read 六张 png 核对 → 请用户开窗确认 |
| 查**某个数值为什么是这个** | Grep `battle.gd` 对应函数（索引见 CONTEXT §5.1）→ 对照 DESIGN §1/§3/§9 与 §10 决策日志 |
| 写**临时探针**验证猜想 | 新建 `game/tests/probe_*.gd`（`extends SceneTree`，末尾 `quit(0)`）→ 无头跑 → **验证完删掉脚本与同名 `.gd.uid`**（规范见 GODOT_GUIDE §3b） |
| 改**服务端接口/部署/备份** | **2026-11-25 起暂缓，恢复前不做**；恢复时：接口先改 `server/API.md`，部署先改 `server/README.md` → 改 `server/app/` 或 `server/deploy/` → `cd server` 跑 `python -m unittest discover -s tests -v`（131 项）+ `python tools/smoke.py` + `python -m compileall app tests tools` → Ubuntu 按 `server/README.md` §11 验收；不碰 `game/` |

## 架构速览

- **纯逻辑层** `game/scripts/core/`：
  - `die`（sides/value/yaocai/face，升级链 d4→d6→d8→d12）、`game_rng`（仅 Crypto）、`game_state`（静态跨场景）。
  - `gamedata`：12 角色 + 11 曜彩面表/使用条件 + 18 关键词 + `SIDES_TEXT`；数值照 xlsx 录入。
  - `battle`：分步回合 API + 结算时序 + `hits` 逐笔掉血 + 每回合幂等守卫；`eval_cond/pairs_count/dice_sum/pool_count` 为静态纯函数，结算/AI/界面共用。
  - `ai`：贪心选骰/重投/曜彩；条件判定直接调用 `Battle.eval_cond`；`combinations()` 也供逐骰提示。
  - `driver`：同步编排（无头模拟）。
- **UI 层** `game/scripts/ui/`：
  - `select_ui` / `battle_ui`：选卡与战斗编排（人类=玩家 0 异步）；`battle_ui` 含 HP 条、掉血飘字、状态栏、选骰提示、敌方骰块、战绩页。
  - `button_styles`：选卡/战斗共用按钮样式（`ButtonStyles.apply()` / `apply_primary()`），不要再各写一份。
  - `die_visuals`：3D 骰几何/材质/贴面刻字/停骰姿态/灯光静态缓存；`make_die_instance()` 统一装配网格+逐面数字。
  - `die_view`：单个骰子的静态 3D 视图（无边框 Button + SubViewport；普通 128×150、敌方 96×132）；选中金边放大 1.10、命定粉边 1.06 的不透明反壳描边；双方共用同一停骰姿态；`_apply_rest()` 按投影包围盒居中并按骰型自动放大正交 size（d8 约 2.5），避免顶尖被裁。
  - `dice_roll`：3D 真骰型投骰演出（重投 1.3s 短版）。
  - `glossary`：效果显示弹窗（全量可滚动、高亮定位、窄窗收窄）。
  - 骰行池化：`battle_ui._obtain_view()/_prune_views()` 统一创建/复用/清理，`_sync_dice_row()/_sync_enemy_row()` 增量刷新。
- **服务端** `server/`（**2026-11-25 起暂缓**）：Python 3 标准库 + SQLite、零第三方依赖、HTTP JSON `/api/v1`、默认 `127.0.0.1:8080`；只存 PVE/PVP 场次与胜场；`server/README.md` + `server/API.md`。
- **回合编排**：`round_open()` → 每方 `roll_phase(idx)` → 可选 `roll_yaocai` → 攻方 `do_reroll`×2 → `commit_selection` → `settle()` → `round_close()`（末尾无条件 `round += 1`）。
- **结算时序**：跃升/骇入先改点（先跃升后骇入）→ 重算攻防值 → 瞬伤已即时 → 荆棘 → 主伤害/连击/洞穿/反击 → 攻击后被动 → 中毒；**一方 KO 后所有效果停止**；HP 钳制 ≥0，无平局。
- **布局（1080p 基准）**：敌条 x360 起、y16 起，只放名字/HP/曜彩/被动/状态并按内容收紧；敌方骰块在框外、名字正下方 x380、cell 96×132（每行 5 颗、第 6 颗换行、来源标题行右侧「总计 N」）；横幅+预期效果居中 / 投骰演出 / DiceTip y664–692 / DiceRow x±700、y720–870（128×150）/ 日志 y872–910 / 玩家条 y910–1064 / 按钮列 260px / 曜彩弹窗右上；选卡页 1280px 内容列居中。详见 `CONTEXT.md` §5。

## 当前状态（2026-11-27）

**现在能玩**：单机 PVE 全流程（选卡 → 战斗 → 终局战绩页）；12 角色 / 11 曜彩；3D 投骰、选骰与敌方骰。

**当前优先级**：**P1 稳定性（收尾）→ P2 局域网 1v1 → P3 AI 强化 → P4 美术**；云服务/战绩存储暂停（`server/` 原样保留）。

**最近完成**
- **2026-11-27 提示逻辑去重**：`_sel_ready()`（就绪判断唯一实现，`_die_lit_fx` 不再隐式读全局 `_sel`）、`_hint_passives()`（阶段被动 → 白名单 → 效果词三重过滤唯一，浅色/金色共用）、`_yaocai_face_fx()`（曜彩面效果取表唯一）、`_fx_hint_ok()`（不屈一次性过滤）；`_die_fx_hints()` 预计算提示被动并复用求值 ctx；`_fx_hint_item()` 形参改名 `lit`。无行为/规则/数值改动。
- **2026-11-27 骰下提示两态**：取消骰子面数标注（六面/四面等不再显示在骰下，仅保留在悬停 tooltip）；普通骰只列「可能效果」，未选中为浅灰蓝（`HINT_FX_DIM`），**确定会生效**时转金色（`HINT_FX_LIT`）——对子类（`has_pair`/`pairs_ge`）选中对子即金且只金凑对的骰，`all_even`/`all_same`/`all_eq_value` 须选满 `_need` 才金。逐骰归属由 `_die_lit_fx()` 判定；`_active_fx()` 只供预期效果行（含连击×N）。按用户逐角色验收：网安 `sum_ge`、工程 `round_end`、地球 50% 力量不逐骰标注（地球只标全 6 的力量×100%+治愈），生命 `unyielding_once` 用后不显示。`GlossaryPanel.kw_bbcode()` 支持颜色参数（默认金色）。无规则/数值改动。
- **2026-11-27 选中骰高光**：`DieVisuals.selected_material_for()` 为基础材质按骰型+基色单独缓存选中变体（`roughness 0.65→0.50`、`metallic_specular 0.2→0.40`、自发光 `+0.05`）；`DieView._apply_material()` 选中/取消时只切换 `material_override` 并补一帧渲染，不重建网格、不动金边/命定壳层；未选中骰与投骰演出不受影响，骰体仍完全不透明。无规则/数值改动。
- **2026-11-27 第三轮：全量代码审查与优化**：修受伤被动瞬伤漏记战绩（`_eval_on_damaged` 统一走 `apply_fx`）、骇入跨回合残留（`round_open` 重置 `hack_pending`）、投骰计时器生命周期（`dice_roll` 帧驱动 + `_animate_roll` 守卫）；统一 `FX_NAMES`/`_damage_after_defense()`/`_selection_ready()`/`_enemy_selected()`，复用 `_face_basis()` 并删除 `display_label_basis()`；keywords 增至 1207。同日收尾：曜彩可用性收敛为 `yaocai_reason()` 单一来源（`yaocai_usable()` 只判空），`Die.roll()`/`is_mingding()`/commit 面号守卫改取曜彩面表长度。无规则/数值改动。
- **2026-11-27 第二轮：静姿倾角 + 中心选骰合计**：`DieVisuals._display_tilt_for()` 按骰型选倾角（d4 -28°、d6 -14°、d8 -8°、d12 -18°），d8 结果面已接近正视玩家；`battle.tscn` 新增页面中心 `SelSum` 蓝圈，`battle_ui._update_sel_sum()` 玩家阶段实时显示 `Battle.dice_sum(_sel)`、敌方提交选骰后显示其合计 0.9s，投骰/重投/结算期间隐藏。无规则/数值改动。
- **2026-11-27 骰顶裁切修复 + 八面骰配色**：静态 3D 骰按投影包围盒（含 1.10 选中壳）居中，并按骰型自动放大正交 `size`（基础 2.0，d8 约 2.5、`FIT_MARGIN=0.94`），修 d4/d8/d12 顶尖/边角被 SubViewport 裁切；八面骰主色改为 `#FDB26B`。无规则/数值改动。
- **2026-11-26 代码整理轮**：抽出 `ButtonStyles`（选卡/战斗共用按钮样式）、`DieVisuals.make_die_instance()`（骰体+逐面刻字共用）、`battle_ui._obtain_view()/_prune_views()`（双方骰行池化共用）、`_phase_passives()`（阶段被动过滤共用）；`select_ui`/`battle_ui`/`die_view`/`dice_roll` 接入。无规则/数值改动。
- **2026-11-26 3D 骰外观**：数字贴面（法线外 0.0015、单面/深度测试）、骰体全不透明、d6/曜彩官方 `BoxMesh`、d4/d8/d12 精确正多面体、`CULL_FRONT` 不透明反壳描边、d4 刻字扶正。
- **2026-11-26 同日第二轮/第四轮/第五轮**：选骰静态视图按参考截图改为「结果面正对玩家 + 绕屏幕水平轴 18° 上仰（d4/d8 三角面 28°）」露出底面/侧面，使用正交镜头（size 2.0）；d4/d8 三角面额外转到顶点朝上；同时降低材质高光（roughness 0.65、metallic 0、metallic_specular 0.2）。第五轮按用户反馈：选中金边壳层 1.06→1.10 加粗；DiceTip 上提 16px；敌方骰块移出敌方信息条，放到框外名字正下方（Grid 5 列、第 6 颗换行、来源标题+总计一行、与玩家骰共用同一 `display_rotation`/镜头/灯光/材质）。倾角已于 2026-11-27 第二轮按骰型拆为 d4 -28°、d6 -14°、d8 -8°、d12 -18°。
- **2026-11-25 稳定性两轮**：`soak`/`fuzz_actions`/`ui_stress` 落地；Battle 入口/索引/归属/幂等守卫、`battle_ui` 异步生命周期、`GameStateData.sanitize`、`select_ui` 防重入、`dice_roll` 重入令牌。
- **2026-11-17 界面打磨三轮**：选卡选中态与 1280px 居中、战绩面板自适应+三列表格、曜彩弹窗遮罩、主操作按钮金色启用态、选满提示、日志前缀、Esc 关闭、信息栏内边距、按钮列 260px、长被动边界。
- 更早历史见 `DESIGN.md` §10。

**验证基线（2026-11-27 第三轮 + 收尾去重 + 选中高光 + 骰下提示两态 + 提示逻辑去重后）**：keywords `pass=1207 fail=0`；sim 12 行；ui_play `UI PLAY DONE`；ui_smoke `UI SMOKE OK`；soak 2000 局 0 失败（68920 项检查）；fuzz 20001 步 0 失败（482779 项检查）；fuzz invalid 3000 步 0 失败（3008 项检查）；ui_stress 30 局 + 100 次往返 290 项 0 失败 0 泄漏；shot 六图重跑并目检（骰下面数已取消、选中骰面亮度提升、未选中骰不变；连击提示只挂同点骰、未选中为浅色）；临时探针目检（d8 正视、d6 略减、提示浅/金两态、化学/信息逐角色口径），探针已删除。

**已裁决口径**：等级上限=普通骰数；受伤被动仅防御正式结算逐次且 KO 后不触发；跃升先于骇入；KO 后所有效果停止；地球攻击后不参与本次伤害；命定可重投/不可取消/重投必带；多来源连击叠加；升级不重投（只改骰型、保留点数）。

**暂缓/缺口**：多来源跃升/骇入（用户 2026-11-11 指示放一放）；`poison`/`round_start`/`toughness` 无授予/未实现；P3 AI 强化开工前必须先提醒用户；P4 美术待后续。用户实玩验收新骰角度/敌方骰块/选中金边/骰顶裁切修复/八面骰配色/静姿倾角/中心选骰合计/整体手感仍待反馈。
