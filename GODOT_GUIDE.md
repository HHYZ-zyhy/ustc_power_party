# 本机 Godot 使用指南（GODOT_GUIDE.md）

> 适用机器：当前 Windows 电脑（用户 zyyh2）。引擎版本：Godot 4.7.2 stable。
> 项目路径：`D:\warrior party\game`
> 最后更新：2026-11-11（复核修复 AI 不屈估值/结算横幅注记/升级与 attack_after 文档；命定骰不可取消选中、重投必带，keywords 期望值 pass=1189；多来源连击改为叠加；删除战绩页 HP 折线图及相关数据；重投 3D 翻滚短动画 + 投骰演出缓存优化；shot.gd 抓不到投骰瞬间，验证方式见 §5）。

## 1. 可执行文件

- 已加入 PATH，**必须用完整文件名调用**：`Godot_v4.7.2-stable_win64.exe`
- 不要简写成 `godot`（PATH 里没有这个别名），不要改名 exe。
- 验证安装：`Godot_v4.7.2-stable_win64.exe --version`（注意双横线；单横线 `-version` 会被当成项目名启动编辑器）。

## 2. 三种启动方式

```bash
# A. 打开项目管理器（导入/管理工程）
Godot_v4.7.2-stable_win64.exe

# B. 打开本项目的编辑器（改场景/脚本/调试）
Godot_v4.7.2-stable_win64.exe -e --path "D:\warrior party\game"

# C. 直接运行游戏（走 project.godot 的主场景 scenes/select.tscn，开窗游玩）
Godot_v4.7.2-stable_win64.exe --path "D:\warrior party\game"
```

编辑器里按 F5 运行当前项目、F6 运行当前场景；战斗界面调试建议直接 F5 从选卡进。

## 3. 无头模式与自动化验证（本项目的标准流程）

```bash
cd "D:/warrior party/game"

# 0) 新增 class_name 脚本后必须先 import，刷新全局类缓存（否则 -s 报 Identifier not declared）
Godot_v4.7.2-stable_win64.exe --headless --path . --import

# 1) 关键词级断言测试：无 RNG 摆定骰面直接断言结算数值（改核心结算逻辑必跑）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/keywords.gd

# 2) 回归监控模拟：12 角色有序两两 ×6 局 = 792 局，输出胜率/平均回合（数值对齐官方版，仅监控不调参）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/sim.gd

# 3) 假人全流程：实例化战斗场景，模拟人类点击走完对局（含重投、曜彩使用）
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_play.gd

# 4) 冒烟：场景实例化 + 效果显示列表/高亮、推荐曜彩、HP 条、窄窗弹窗、各骰型面数/刻字断言
Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/ui_smoke.gd

# 5) 布局截图自检（注意：不加 --headless，需要显示器；会短暂开窗后自动退出；
#    输出目录 = 工程上一级 _frames/，随工程位置推导，不存在时自动创建；
#    战绩页会先用 time_scale=10 自动打完一局真实对局，耗时十余秒）
Godot_v4.7.2-stable_win64.exe --path . -s res://tests/shot.gd
# 产出：_frames/shot_selectscene.png（选卡）、shot_select.png（战斗选骰态）、shot_yc.png（曜彩弹窗态）、
#       shot_glossary.png（效果显示）、shot_summary.png（终局战绩页，真实对局数据）
```

约定：**改完代码先跑 1)~4) 再汇报**；改布局/字号/演出时加跑 5) 并 Read 截图核对；其余视觉问题需方式 C 开窗人工确认。

### 3a. 期望输出与实测耗时（对不上就是出问题了）

| 命令 | 期望 stdout | 实测耗时 | 失败时长什么样 |
|---|---|---|---|
| `--import` | 一堆导入日志，无 ERROR | 数十秒（首次）/ 数秒（增量） | 脚本语法错会在此暴露 |
| `keywords.gd` | `KEYWORDS pass=1189 fail=0` | <1s | 每条失败打印 `FAIL  <断言名>  <实际值>`；退出码 1 |
| `sim.gd` | `=== balance sim ===` + 12 行 `win N/132 = XX.X%  avg_rounds N.N` | 约 1-2s | stderr 出现 `Out of bounds get index` = AI 选骰越界（等级超池类问题） |
| `ui_play.gd` | `UI PLAY DONE winner=N round=N` | 约 1 分钟（逐帧驱动，别以为卡死） | `UI PLAY TIMEOUT round=N` = 假人 60000 帧内没打完（多半是人类阶段软锁） |
| `ui_smoke.gd` | `UI SMOKE OK` | <1s | 场景实例化/`_ready` 报错或效果显示/推荐曜彩/HP 条/窄窗/骰型面数与刻字断言失败会直接中断，无 OK |
| `shot.gd` | 无输出（只存图后 `quit(0)`） | 十余秒（开窗；含自动打完一局） | 闪窗即退属正常；`_frames/shot_*.png` 未更新说明中途报错 |

- 胜率逐次会变（Crypto 无种子）：只有量级突变才算信号；离群值按政策**只记录不调整**（DESIGN §11）。
- 断言总数会变：改动后把新数字同步到 CONTEXT §7、DESIGN §10/§11、AGENTS、README、本文件五处。

### 3b. 临时探针脚本规范（验证猜想用，用完即删）

```gdscript
extends SceneTree
# game/tests/probe_xxx.gd —— 无头验证某个猜想，不进验证链
func _init() -> void:
	var b := Battle.new()
	b.setup(["math", "ai"], ["", ""], GameRng.new())
	b.attacker = 0
	b.round_open()
	# ... 摆定骰面（b.players[i].dice[j].value = N）、commit_selection、settle()、print 观察值
	# 中文可能乱码，必要时写 UTF-8 文件再用 Read 看
	quit(0)   # 必须显式 quit，否则进程不退出
```

- 跑法：`Godot_v4.7.2-stable_win64.exe --headless --path . -s res://tests/probe_xxx.gd`
- **验证完删掉脚本与自动生成的同名 `.gd.uid`**（两个都要删，否则 git 里留垃圾）；探针结论写进 DESIGN §10 或 CONTEXT §8，不要只留在聊天记录里。
- 探针里可以直接改 `b.players[i].xxx` 摆状态（keywords.gd 就是这么写的），但**不要**为了复现性给 RNG 加种子（用户禁止）。

Shell 注意：上述命令在 cmd 与 Git Bash 下均可直接运行（命令本身不含管道）；但**不要给它们追加 Unix 管道/重定向**（如 `| tail`、`2>/dev/null`）——部分 AI 工具的 Bash 工具实为 cmd.exe，会报"'tail' 不是内部或外部命令"。要看完整输出就整条直跑。

## 4. 工程结构约定

- 场景放 `scenes/`（.tscn），逻辑放 `scripts/core/`（纯逻辑）与 `scripts/ui/`（界面），测试放 `tests/`（`-s` 可执行的 SceneTree 脚本）。
- 跨场景共享数据用静态类 `GameStateData`（`scripts/core/game_state.gd`）。**不要用 autoload**：`-s` 无头模式不注册 autoload，会导致编译期 Identifier not found。
- 每个 `.gd` 旁的 `.gd.uid` 与工程内 `.godot/` 均为引擎生成物：不要手改；`.godot/` 可安全删除（下次 import/运行自动重建）。
- 全局 GUI 主题 `theme.tres`（默认字号 32）在 project.godot 的 `[gui] theme/custom` 挂载；调字号改这里，不要逐控件改。
- 分辨率适配：project.godot `[display]` 设基准 1920×1080、`stretch/mode="canvas_items"`、`stretch/aspect="expand"`；界面坐标按 1080p 设计，其他窗口尺寸自动等比缩放。注意 aspect=expand 下窗口变窄时**视口宽度仍为 1920、高度扩展**；若日后改为缩短宽度（或其他拉伸设置），界面里的固定尺寸弹窗需依赖各自的 `_fit_*` 方法按视口收窄（曜彩/效果显示/战绩面板已实现）。

## 5. 本项目用到的引擎 API 注意点（踩坑记录）

- 随机数：`Crypto.new().generate_random_bytes(n)`。Godot 4.7 **没有** `Crypto.get_random_bytes`，也**没有** `CryptoRandomNumberGenerator` 类。项目要求所有随机走 Crypto（公平性），禁止加种子通道。
- 节点未入树时调用 `look_at()` 会报错 → 用 `look_at_from_position(pos, target)`。
- GDScript：字典取值用 `.get(key, default)` 防缺键崩溃；`var x := dict.field` 因 Variant 无法推断类型，需写 `var x: int = dict.field`。
- 手写 .tscn 时新增 `[ext_resource]` 必须同步把头部 `load_steps` 加 1。
- `String.replace()` 不接受函数回调（与 Python 不同）。
- 协程：控制器/编排函数里 `await` 信号或 timer；AI 同步路径走 `driver.gd`，人类异步路径走 `battle_ui.gd`，二者共用 `battle.gd` 分步 API。
- `-s` 无头脚本里等帧只能用 `await process_frame`（SceneTree 脚本没有别的帧回调）；`ui_play.gd` / `shot.gd` 都是这么驱动的，所以慢是逐帧造成的，不是卡死。
- `RichTextLabel` **没有** `set_bbcode()`：赋 `.text` 并设 `bbcode_enabled = true`；可点击词写 `[url=关键词]文字[/url]` 再连 `meta_clicked` 信号（局内效果显示入口就是这个机制，见 `glossary.gd kw_bbcode()`）。
- `RichTextLabel` 的 `fit_content` 只调高度、不提供最小宽度；直接放进 `GridContainer` 会被挤成一字一列。网格/卡片布局要给单元格设 `custom_minimum_size`（2026-10-25 曜彩六面表 bug 的根因）。
- `GameStateData` 初始为空（首次启动未选角/未选曜彩）；直接运行 `battle.tscn` 时 `battle_ui._ready()` 会回退到 physics/网络渗透，正常流程由 `select_ui._on_start()` 写入。测试脚本直接实例化战斗场景时建议显式设置 GameStateData（`ui_play.gd`/`shot.gd` 已这样做）。
- 场景唯一名：`@onready var x = %CharsGrid` 依赖 tscn 里该节点的 `unique_name_in_owner = true`；手写/复制节点时漏设会在运行时报 "Node not found"。
- `battle.gd` 的 `eval_cond()` / `apply_fx()` 用 `match` 分派字符串，**未命中静默失败**（条件返回 false、效果什么都不做，不报错）：新增条件/效果后必须写 keywords 断言确认真的触发了。
- 化学「升级」只提升骰型/最大面数，**保留当前点数、不重投**（DESIGN §2；`_t_upgrade` 断言锁定）。旧文档曾写“按新面数重投”，不要据此给 `upgrade_sel` 补重投逻辑；若要改先让用户裁决。
- AI 的 `_trigger_bonus()` 是另一套独立条件判定，必须与 `eval_cond()` 保持同口径：2026-11-11 发现 `all_same` 分支只判「组合非空」，生命学院防御任意组合都被估成不屈 +6；改 AI 评估后跑 sim 看胜率变化（只记录不调参）。
- 界面文本若只在 `_ready()` 或一次性构建函数里赋值，之后不会自动更新：凡随对局变化的（HP、等级徽章、状态栏）都要挂进 `refresh()`（2026-10-15 徽章 bug 的根因）。
- `round_close()` 末尾无条件 `round += 1`（终局那回合也加）：展示"总回合数"要用 `round - 1`。
- `ProgressBar` 用 `background`/`fill` 两个 StyleBoxFlat 主题覆盖上色；`show_percentage=false` 只留条。它放进 HBox 时要给 `custom_minimum_size` 才不会压扁（HP 条 180×16）。
- 固定尺寸弹窗做窄窗适配时，除了按 `get_viewport_rect()` 改 offset，还要处理**内容最小尺寸**：`GridContainer` 里的卡片有 170 最小宽度时，弹窗 offset 再小也会被内容顶宽；须同步降列/降卡片最小宽度（2026-10-25 曜彩弹窗）。
- 掉血飘字用 `Battle.hits[*].amount`（实际扣血）；`stats.dmg_taken/dmg_dealt` 自 2026-11-10 也按实际扣血累计，`s.dmg`（横幅「主伤害」）才是名义伤害（含溢出/不屈）；同批多笔按目标叠放，敌方顶部向下、我方底部向上，避免飘字出屏。
- 洞穿/力场/反击边界：力场只挡非洞穿的主伤害与连击各段；洞穿取攻击值、破力场且不触发反击（`settle()` 反击条件必须保留 `not summary.pierce`）；瞬伤/荆棘/中毒不吃力场（2026-11-10 修正）。
- 骇入目标最大骰为 1 点时也变为 2 点（全 1 时抬一颗，用户 2026-11-10 裁决，不是 bug）；不要改成「≤2 时不变」。
- 3D 骰的逐面数字不建议用 billboard（数字会脱离骰面）：每个面挂 `Label3D`，用「面法线 = 本地 +Z、投影 up = +Y」构造 Basis，`double_sided=false`；字高按该面内切圆半径算（约 1.35×inradius / font_size）。正十二面体面法线手写易错位，用顶点凸包支撑面算法生成（2026-11-11）。
- KO 后边界：所有扣血/治疗/改点循环必须逐迭代或逐效果检查 `winner`；commit 瞬伤致死后 `settle()` 的跃升/骇入也不得再改点；`damage()`/`heal()` 对 HP≤0 目标直接返回；UI/driver 在攻方 commit 致死后跳过阵亡方防御阶段（2026-11-11）。
- 「攻击后」类被动（`attack_after`）必须放在 `settle()` 内攻击结算之后（主伤害/连击/反击之后、中毒之前）：放在 `commit_selection()` 会先写入力量，被 settle 重算攻击值时吃进本次伤害（地球曾因此虚增；用户 2026-11-11 裁决改为结算后生效）。`settle()` 里先用最终 `atk_value` 更新 `_ctx_a.atk_value` 再 `eval_cond`/`apply_fx`。
- 多来源连击已改计数（用户 2026-11-11 裁决）：`apply_fx` 写 `flags.combo_count`，`settle()` 逐段结算，`summary.combo_n` 为实际段数、`dmg2` 为各段合计；写测试/探针直接摆上下文时不要再用 `flags.combo = true`。多来源骇入仍是布尔 `hack_pending`（用户暂缓叠加），不要误改。
- 命定骰允许被重投（用户 2026-11-11 裁决）：UI 自动入选后重投会换面，`commit_selection()` 的 `_enforce_mingding` 必须保证重投后仍占选骰名额；命运签约六面全部带命定，重投不改变命定属性。
- 回合上下文缓存（`_ctx_a/_ctx_d/atk_value/def_value`）必须在 `round_open()` 清空：防御阶段可能因攻方 commit 瞬伤被跳过，残留的上一回合 bonus 会被 `settle()` 误用（2026-11-11 修复）。
- `roll_yaocai()` 现在内部走 `yaocai_usable()`、`do_reroll()` 检查 `rerolls > 0`：写测试/探针时不要绕过入口直接改 `yc_uses`/`rerolls`，否则会绕过次数与 KO 守卫。
- `do_reroll(idx, dice)` 现在**返回实际重投集合**：命定曜彩骰不能被取消选中，任何重投都会把它强制加入（用户 2026-11-11 澄清）；人类/AI 的 3D 演出必须用返回值，不要再用传入的 picks。`battle.is_mingding(d)` 是命定判定的唯一入口（UI 的 `_is_mingding` 已转调它）。
- 重投 3D 动画走 `battle_ui._animate_roll(picks, idx, true)`：只把本次重投的骰子放进 RollView（quick 约 1.3s），不要用整轮 `roll` 显示双方全部骰行；演出期间锁输入。`dice_roll` 的 spec/mesh/material 缓存键要区分骰型/曜彩名，新增骰型或改面表时同步检查。
- 投骰 3D 演出只在 `RollView` 显示期间存在，`shot.gd` 的五个静态截图抓不到翻滚瞬间；要验证骰子尺寸/刻字/停骰，开窗游玩看，或写临时探针（SubViewport 760×360 复刻 RollView，截图后连同 `.uid` 一起删）。

## 6. 常见故障排查

| 症状 | 原因与处理 |
|---|---|
| `-s` 脚本报 `Identifier "X" not declared` | 新 class_name 未进缓存 → 跑 `--headless --path . --import` |
| 运行报 `Identifier "GameState" not found` | 误用 autoload → 改用静态类 GameStateData |
| 编辑器打开项目卡导入 | 首次 import 需几十秒，属正常；`game/` 之外的参考件（`参考素材/` 下的 xlsx/png，以及曾经的 mp4）不会被导入 |
| 窗口黑屏/渲染异常 | project.godot 已设 gl_compatibility（Intel Arc 核显兼容）；如仍异常改 `[rendering] renderer/rendering_method` |
| 测试进程不退出 | SceneTree 脚本末尾必须 `quit(0)`；若 assert/运行时错误发生在 quit 之前（如 ui_smoke 断言失败），进程会挂住，需手动结束 Godot 进程 |
| `ui_play.gd` 一分钟没动静 | 正常：它逐帧驱动一整局（约 60s）；真出问题会打印 `UI PLAY TIMEOUT round=N` |
| `keywords.gd` 出现 `fail=N` | 每条失败会打印 `FAIL <断言名> <实际值>`；先对照 DESIGN §1/§3/§9 判断是"代码错了"还是"断言随新裁决该改"，别默认改断言 |
| `sim.gd` stderr 有 `Out of bounds get index` | AI 选骰组合为空——通常是攻/防等级超过骰池上限（`selection_count` 钳制被绕过），见 DESIGN §10 2026-10-13 条目 |
| 跑 shot.gd 时闪出一个窗口又关闭 | 正常：截图脚本需开窗渲染，截完自动 quit；无显示器环境（纯 headless 服务器）跑不了它 |
| shot.gd 截图是黑的/空的 | 未真正开窗（加了 `--headless`）或等待帧数不够；确认 `_frames/shot_*.png` 修改时间已更新再 Read |
| 替换 xlsx 报 `WinError 5` | 用户 Excel 正开着该表（`参考素材/` 下有 `~$角色，骰子参数.xlsx` 锁文件）→ 请用户先关 Excel |

## 7. 与外部工具的边界

- 写 xlsx（数值表，位于 `参考素材/角色，骰子参数.xlsx`）用 Python 3.13 的 zipfile 改内部 XML；**写之前确认 Excel 已关闭**（存在 `参考素材/~$角色，骰子参数.xlsx` 锁文件时替换报 WinError 5）。读 xlsx 时注意：单元格 `t="s"` 的 `<v>` 是 sharedStrings 下标，需映射回原文。（`_xlsx/` 解包产物已清理，需要时重新解包即可。）
- 抽视频帧用 ffmpeg：`"/d/App files/ffmpeg-n8.1.2-win64-gpl-8.1/bin/ffmpeg.exe"`（Git Bash 路径）。
- GitHub 访问经 Watt Toolkit（Steam++）代理，直连 IP 不通。
- git：仓库已跟踪（分支以仓库当前状态为准）。**git 由用户全权负责**：AI 不执行 git 操作、不跟踪不汇报仓库状态；不擅自改 `.gitignore`。注意 `.gitignore` 未忽略 Excel 锁文件 `~$*.xlsx`，提交时留意别带上。
- AI 工具自身的坑（与 Godot 无关但会浪费时间）：控制台打印中文可能乱码（GBK 控制台）→ 让脚本写 UTF-8 文件再用 Read 看；搜索工具偶发漏报（明明存在却 "No matches"）→ 换 pattern 或直接 Read 文件确认；ripgrep 默认不支持 look-behind（`(?<!x)` 会报错）。
