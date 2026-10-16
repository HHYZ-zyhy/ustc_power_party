# D:\warrior party — 文件夹说明

> 科大战力党（骰子对战游戏）项目根目录。接手先读 `AGENTS.md`（硬规则速查），再读 `CONTEXT.md`（背景与架构），规则读 `DESIGN.md`，Godot 操作读 `GODOT_GUIDE.md`。本文件是**文件夹内每个文件的用途登记表**，新添文件必须在此登记一行。
> 最后校订：2026-10-16（与磁盘实际文件逐项核对）。

## 我想知道…该看哪份文档

| 问题 | 去处 |
|---|---|
| 这个项目是什么、有哪些硬规则、常用命令 | `AGENTS.md` |
| 改某个功能要去哪个文件/函数 | `CONTEXT.md` §5.1 代码索引 |
| 某个状态字段是什么意思、什么时候清零 | `CONTEXT.md` §5.2 玩家字段词典 |
| 某条规则为什么这么定、谁拍的板 | `DESIGN.md` §9 已定约定 / §10 决策日志 |
| 写被动时能用哪些条件/效果字符串 | `DESIGN.md` §5.1（§5.2 是已知实现缺口） |
| 现在做到哪了、下一步做什么 | `DESIGN.md` §11（P1~P4 分级待办）+ `CONTEXT.md` §7 |
| 角色/曜彩的具体数值 | `角色，骰子参数.xlsx`（唯一数值权威）→ 镜像在 `game/scripts/core/gamedata.gd` |
| Godot 怎么跑、测试期望输出是什么、报错了怎么办 | `GODOT_GUIDE.md` |
| 某个文件是干什么的 | 本文件 |

## 根目录文件

| 名称 | 类型 | 说明 |
|---|---|---|
| `AGENTS.md` | 文档 | **任何 AI 编程工具/智能体打开本项目的第一入口**：项目一句话、阅读顺序、硬规则、命令速查、常见任务菜谱、架构速览、当前状态 |
| `CONTEXT.md` | 文档 | 交接主文档：背景、协作约定、环境事实、权威资料清单、代码架构 + 代码索引 + 字段词典、Battle 分步 API、验证命令与期望输出、进度、踩坑记录、未决事项、跨设备交接指引 |
| `DESIGN.md` | 文档 | **规则权威**：冻结规则全文、18 关键词定义、12 角色/11 曜彩骰表、§5 被动框架与合法取值、§9 已定约定、§10 决策日志（十一轮反馈 + 全部裁决）、§11 进度与分级待办（改规则先改它） |
| `GODOT_GUIDE.md` | 文档 | 本机 Godot 4.7.2 使用手册：三种启动方式、无头验证流程与期望输出、临时探针规范、截图自检、工程约定、API 踩坑、故障排查表 |
| `README.md` | 文档 | 本文件：文件夹每个文件/目录的用途登记 |
| `LICENSE` | 元 | GNU GPL v3 开源许可证（仓库已纳入 git 版本控制，分支 main） |
| `.gitignore` | 元 | git 忽略规则（Godot 4 标准模板：`.godot/`、`*.exe`、导出产物、`*.tmp` 等）；**未忽略 Excel 锁文件 `~$*.xlsx`**，提交前留意 |
| `角色，骰子参数.xlsx` | **数值权威** | sheet1 角色属性（12 角色）、sheet2 骰子属性（11 曜彩骰，B 列面表已录入）。改数值需用户批准后同步 `gamedata.gd` |
| `科大战力党-构思.txt` | 规格 | 用户原始构思：Godot 引擎、Crypto 随机、2D+投骰3D、贪心 PVE、中期局域网、后期天气 |
| `进攻方选骰子.png` | 参考 | 原作战斗界面截图（进攻方选骰态）——整体布局与逐骰效果标注的对照依据 |
| `进攻方使用曜彩骰时.png` | 参考 | 原作战斗界面截图（曜彩弹窗态）——曜彩六面表弹窗布局的对照依据 |
| `防御时显示界面.png` | 参考 | 原作战斗界面截图（我方防御时）——第八轮反馈「显示敌方所选骰+总计」的对照依据 |
| `未选中时显示可能的效果.png` | 参考 | 原作战斗界面截图（未选中骰子时）——第十一轮反馈「逐骰效果标注」的对照依据 |
| `选中时高亮显示获得效果.png` | 参考 | 原作战斗界面截图（选中骰子高亮）——第十一轮反馈「已选触发效果高亮」的对照依据 |
| `效果/` | 参考 | 官方关键词解释截图 page1~4.jpg（官方 15 条）；游戏内关键词共 18 条（另 3 条用户补充，全文见 DESIGN §3） |
| `曜彩骰定义/` | 参考 | 11 张曜彩骰面表与使用条件截图，gamedata.gd 面表录入依据。文件名仍用旧曜彩名（只读参考素材，未改），对应新名：理实积淀(蓄力.jpg)、命运签约(命运.jpg)、军训急救(医嘱.jpg)、重复试验(复读.jpg)、网络渗透(奇术师.jpg)、通宵鏖战(战狂.jpg)、东风导弹(魔弹.jpg)、选课盲赌(赌徒.jpg)、顶刊论文(奇迹.jpg)、实验防护(星盾.jpg)、铜砖誓言(誓言.jpg) |

**已不在仓库的文件（旧文档可能还提到）**：
- `示例1.mp4` / `示例2.mp4`（原作参考录屏，曾各 66MB / 156MB）——已移除，抽帧保留在 `_frames/ex1_*.jpg`(8 张)、`ex2_*.jpg`(14 张)；需要再看动态演出请用户重新提供。
- `银河战力党-官方资料汇编.md`（网络抓取的官方资料）——用户明示可能有误、**非权威**（xlsx 优先），且已不在磁盘。
- `~$角色，骰子参数.xlsx` 若出现，是 Excel 打开该表时的锁文件（未跟踪）：此时替换 xlsx 会报 WinError 5，也别把它提交进 git。

## 子目录

| 名称 | 说明 |
|---|---|
| `game/` | **Godot 4.7.2 工程**（可执行内容全在这里），结构见下 |
| `_frames/` | 工作scratch（可清理）：原作录屏的 ffmpeg 抽帧（`ex1_*.jpg` 8 张、`ex2_*.jpg` 14 张——**mp4 本体已移除，这些抽帧是唯一的动态参考**）；`tests/shot.gd` 每次覆盖生成的布局自检图（shot_selectscene / shot_select / shot_yc / shot_glossary / shot_summary.png 五张）；历史探针一次性验证截图（`probe_*.png` 11 张，可删） |
| `_xlsx/` | 工作scratch：xlsx 解包目录（`xl/`、`docProps/` 等，Python zipfile 修改 B 列时的产物）与解析记录（current-parse.txt、verify.txt）；**original-backup.xlsx 是写入 B 列前的原表备份，永久保留** |

## game/ 工程结构

```
game/
  project.godot        工程配置：主场景 scenes/select.tscn、全局主题 theme.tres、gl_compatibility 渲染、
                       基准分辨率 1920×1080（canvas_items 拉伸 + aspect=expand，适配不同窗口）
  theme.tres           全局 GUI 主题（默认字号 32；调字号改这里，不要逐控件改）
  .godot/              引擎缓存（import 产物），可删，下次 import/运行自动重建
  scenes/
    select.tscn        选卡界面（1 角色 + 1 曜彩骰；信息栏显示骰池构成与 Excel 原文介绍；少年班显示「攻?」）
    battle.tscn        战斗界面布局：敌方信息条顶部（含状态栏）/ 敌方骰子行 / 横幅+预期效果中上 /
                       投骰 3D 子视口 RollView 居中透明 / 骰子候选中下（骰型配色）/ 玩家信息条底部（含状态栏）/
                       操作按钮右列（曜彩/重投/确认）/ 曜彩六面表弹窗 YcPopup / 终局战绩汇总页 SummaryView
  scripts/
    core/              纯逻辑层（不依赖 UI，可无头运行）
      die.gd           Die：sides/value/yaocai/face；升级链 d4→d6→d8→d12
      gamedata.gd      12 角色 + 11 曜彩骰面表/使用条件（照 xlsx 录入，勿手改数值；intro 字段为 Excel 介绍原文）
      game_rng.gd      GameRng：仅 Crypto.generate_random_bytes，无种子通道
      battle.gd        Battle：分步回合 API 与结算时序（跃升/骇入先改点再求和、并列随机取）；
                       yaocai_usable/yaocai_reason（可用性与中文原因）；damage() 钳制 HP≥0
      ai.gd            AIController：贪心枚举选骰/重投/曜彩启发式（待改进清单见 DESIGN §11）
      driver.gd        Driver：同步编排（无头模拟用）run_round/run_game
      game_state.gd    GameStateData：静态变量 char_id/yc_name（选卡→战斗跨场景，不用 autoload）
    ui/
      select_ui.gd     选卡逻辑：骰池构成行、攻?显示、化学禁曜彩
      battle_ui.gd     战斗界面逻辑（人类=玩家0 异步编排）：中文效果文案映射、命定锁定、升序排骰、
                       选中即重投、扣血闪红+飘字、曜彩弹窗开关式+不可用原因、攻/防等级角标（随 refresh 更新）、
                       状态栏（荆棘待结算/力场/不屈/中毒/力量/跃升）、逐骰效果标注（少年班不显示）、
                       预期效果汇总行、确认按钮 已选/需选 计数、敌方所选骰+总计、守方上回合骰展示、
                       骰型配色、关键词图鉴接入、曜彩骰 3D 演出、终局战绩汇总页（HP 曲线+触发统计）
      glossary.gd      关键词图鉴弹窗 GlossaryPanel（18 条定义照录 DESIGN §3；界面内效果词均为可点击 meta 链接展开）
      dice_roll.gd     投骰 3D 演出（SubViewport 透明背景，约 2.3s，与选骰框不重叠；骰型同色系；旋转随机走 Crypto；
                       曜彩骰为近黑+蓝紫 BoxMesh，普通骰与曜彩共用同一 roll() 接口）
  tests/
    sim.gd             792 局 AI vs AI 回归监控模拟（12 角色有序两两 ×6 局，每角色 132 局；随机曜彩；
                       数值对齐官方版，仅监控不调参）
    keywords.gd        关键词级断言测试：无 RNG 摆定骰面直接断言结算数值，26 组场景 1110 项断言；
                       **改核心结算逻辑必跑**，期望 KEYWORDS pass=1110 fail=0
    ui_play.gd         无头假人全流程（含重投、曜彩使用路径），期望 UI PLAY DONE（约 1 分钟）
    ui_smoke.gd        场景实例化冒烟（30 帧），期望 UI SMOKE OK
    shot.gd            布局截图自检（开窗运行，输出 _frames/shot_*.png 五张：选卡/战斗/曜彩弹窗/图鉴/战绩页）
    debug1.gd          单局日志调试（临时排查用；正式验证不依赖它）
  *.gd.uid             Godot 自动生成的脚本 UID 文件，勿手改、勿删（新建脚本会自动生成，删脚本要连 .uid 一起删）
```

## 维护约定

- 参考素材（截图/xlsx/构思.txt，以及曾在的 mp4）只读；AI 产物进 `game/` 与文档。
- scratch 目录（`_frames/`、`_xlsx/` 除 `original-backup.xlsx` 外）可清理；清理前确认备份已无用、并跟用户说一声。
- 根目录新增参考截图或文档时，在本表登记一行；`game/` 新增脚本/场景/测试时，在上面的工程结构里补一行；临时探针脚本（`game/tests/probe_*.gd`）用完即删，不登记。
- **改完东西要同步哪些文档**：数值 → `DESIGN.md` §4/§6 + `gamedata.gd`；规则/时序 → `DESIGN.md` §1/§3/§9 + §10 记一条决策；断言数或 sim 胜率变化 → `CONTEXT.md` §7 + `DESIGN.md` §11 + `AGENTS.md` + 本文件（四处都写了数字）；新增文件 → 本表登记。
- 文档冲突时以 `DESIGN.md` 为规则权威、`角色，骰子参数.xlsx` 为数值权威；其余以更新时间新者为准。
- 本仓库已用 git 跟踪（分支 main）：`.gitignore` 忽略 `.godot/`、`*.exe` 等引擎/导出产物；git 提交与仓库状态由用户全权负责，AI 不擅自提交、不跟踪 git 状态。