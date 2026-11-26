# 科大战力党 玩家数据存储服务（server）

> 版本 **1.0.0**，接口版本 `/api/v1`，接口契约见 [`API.md`](./API.md)。
> 纯 Python 3 标准库 + SQLite，**零第三方依赖**；默认只监听 `127.0.0.1:8080`。
> 本文是唯一部署与使用入口；规则和字段口径以 `API.md` 为准，两者冲突时先改 `API.md`。

---

## 审查者 10 分钟路径（交付状态摘要）

先读这一段，不必翻到文末：

- **是什么**：一个只存玩家 PVE/PVP **场次与胜场**的小型 HTTP 服务，Python 3 标准库 + SQLite、零第三方依赖、默认只监听本机 `127.0.0.1:8080`，数据库默认 `data/store.sqlite3`。不存对局明细、伤害、回合、角色/曜彩，也不做排行榜。
- **先跑哪三条命令**（本机 Windows 用 `python`，Ubuntu 用 `python3`；从仓库根 `cd server`，已在 `server/` 内则跳过）：

  ```bash
  cd server
  python -m unittest discover -s tests -v   # 131 项 OK，2 项跳过（POSIX-only）
  python tools/smoke.py                     # 12 条 [OK] + SMOKE OK
  python -m compileall app tests tools      # 退出码 0
  ```

- **契约在哪**：接口字段、错误码、限流与数据口径的**唯一契约是 [`API.md`](./API.md)**；本文负责使用、部署、备份与排错。两者冲突时先改 `API.md`。
- **已验证**（2026-11-14，本机 Windows + Python 3.13 + Git Bash）：单测 **131 项 OK、2 项跳过**（应用层 116、部署脚本 15 = 13 通过 + 2 项 POSIX-only 跳过）；`tools/smoke.py` 12 条 `[OK]` + `SMOKE OK`；`bash -n deploy/install-ubuntu.sh`、`py_compile`/`compileall` 通过。详见 §11.3。
- **未验证**：真实 Ubuntu 24.04 上的 systemd 安装、备份 timer 定时触发、信号优雅停止、nginx/TLS 与异地备份。必须在 VM 上按 §11.1/§11.2 逐条验收。
- **待裁决**：排行榜、公网入口/域名/HTTPS、隐私与数据保留期、客户端接入、反作弊/互证；`.gitignore` 未覆盖 `server/data/`、`__pycache__/`、`*.sqlite3`，需用户决定是否补规则。
- **本轮复核修复**（2026-11-14）：严格 `Content-Length`/短读拒绝、错误响应排空 body、未知方法返回 JSON 405/404、schema/健康检查 fail-fast、批量查询读快照、幂等窗口 2000、胜率四舍五入、备份轮转与恢复校验、安装 staging 换入等，详见 §10.5 与 §11.3。

---

## 1. 这是什么

这是《科大战力党》的玩家数据存储服务：玩家注册后获得 ID 与 token，客户端用 token 上报自己的 PVE/PVP 胜负，查询时返回场次、胜场与胜率。

**数据口径是硬边界**（详见 `API.md` §2）：

| 存 | 不存 |
|---|---|
| 玩家 ID（服务端生成） | 对局明细、时间线、回合数 |
| 昵称（可重名） | 伤害、扣血、治疗数值 |
| 创建/更新时间 | 角色、曜彩骰使用情况 |
| PVE/PVP 的 `games`、`wins` | 胜率（查询时计算，不落库） |

技术事实：

- Python 3.10+，只用标准库（`http.server`、`sqlite3`、`secrets` 等）。
- SQLite（WAL 模式，写串行），schema `user_version = 1`；默认数据库 `data/store.sqlite3`。
- token 只在注册响应里返回一次，服务端只存 `SHA-256(token)`（配置 pepper 时用 `HMAC-SHA256(pepper, token)`）。
- `event_id` 幂等记录每玩家保留最近 **2000 条**（覆盖约 3 小时满速上报）。
- 当前是**单实例**部署；限流计数在内存里，重启清零，多实例不共享。
- 只服务 PVE/PVP 统计，**不接游戏客户端**、不存对局过程、不做排行榜。

---

## 2. 目录结构

```
server/
├── API.md                         冻结的 HTTP 契约（实现变更先改它）
├── README.md                      本文件
├── app/                           服务代码
│   ├── __init__.py                版本号 __version__ = "1.0.0"
│   ├── __main__.py                python -m app 入口
│   ├── auth.py                    token 生成/哈希/常数时间校验
│   ├── config.py                  配置：命令行 > 环境变量 > 默认值
│   ├── db.py                      SQLite 存储层（玩家、统计、幂等事件）
│   ├── errors.py                  统一 API 错误
│   ├── http_api.py                HTTP 路由、请求解析、鉴权与限流
│   ├── log.py                     日志（访问日志为单行 JSON，不记 token）
│   ├── ratelimit.py               固定窗口内存限流（注册/上报）
│   ├── validation.py              输入校验（昵称/mode/result/event_id/player_id）
│   └── main.py                    HTTP 入口：make_server(config) / run(config)
├── deploy/                        部署与运维文件（安装后位于 /opt/warrior-store/deploy）
│   ├── warrior-store.service      主服务 systemd 单元
│   ├── warrior-store.env.example  环境变量样例（安装为 /etc/warrior-store.env）
│   ├── warrior-store-backup.service  备份 oneshot 单元
│   ├── warrior-store-backup.timer    每日备份定时器
│   ├── backup.py                  SQLite 一致性快照备份（跨平台）
│   ├── restore.py                 从快照恢复（跨平台）
│   └── install-ubuntu.sh          Ubuntu 24.04 一键安装脚本
├── tests/                         单元测试（unittest；test_db / test_validation / test_api / test_config / test_main / test_ratelimit / test_deploy_scripts，helpers.py 为测试工具；共 131 项，2 项 POSIX-only 跳过）
└── tools/
    └── smoke.py                   跨平台 HTTP 冒烟测试（临时服务 + 临时数据库）
```

运行时生成的 `data/` 目录、`*.sqlite3` 数据库与 `__pycache__/` 都是本地产物，不要提交到版本库。

---

## 3. 本机测试（Windows / Linux 均可）

要求：Python **3.10 及以上**，且编译时带 `sqlite3` 模块（官方安装包默认带）。**不需要 pip 安装任何东西。**

**从仓库根执行 `cd server`；已经在 `server/` 目录内则跳过这条 `cd`。** 下面的命令都假设 cwd 是 `server/`：

```bash
cd server   # 仅从仓库根开始时需要

# 1) 单元测试（应 131 项 OK，2 项跳过）
python -m unittest discover -s tests -v

# 2) HTTP 冒烟测试：自动起临时服务 + 临时数据库，走完注册/查询/上报/去重/批量/改名/删除
python tools/smoke.py

# 3) 全量语法编译检查（应退出码 0）
python -m compileall app tests tools
```

Windows 上用 `python`；Ubuntu 上用 `python3`。Git Bash、PowerShell、CMD 均可执行上述命令（`compileall` 输出路径可能是反斜杠，属正常）。

### 3.1 期望现象

- 单测：末行 `Ran 131 tests`、`OK (skipped=2)`，退出码 0。跳过的是 2 项 POSIX-only 用例（符号链接、伪 `systemctl`）；应用层 116 项、部署脚本 15 项（13 通过 + 2 跳过）。
- 冒烟：逐行打印 12 条 `[OK] ...`，最后一行 `SMOKE OK`；任一步失败会打印中文原因并以非 0 退出。
- `compileall`：列出编译的 `.py` 文件，无 `Error`，退出码 0。

冒烟测试不需要手动启动服务，也不会碰正式数据库：它用 `Config(port=0)` 随机端口、在系统临时目录建库，结束后自动关闭服务并清理临时目录。

### 3.2 本机手动跑一下（可选）

```bash
cd server
python -m app
# 默认监听 127.0.0.1:8080，数据库为相对路径 data/store.sqlite3（相对当前目录）
```

另开一个终端：

```bash
curl -sS http://127.0.0.1:8080/healthz
```

看到 `{"status": "ok", "version": "1.0.0", "db": "ok", ...}` 即正常。按 `Ctrl+C` 停止。

> 本机手动运行时，`data/` 目录和数据库文件会留在 `server/` 下；这是本地产物，不要提交。

---

## 4. Ubuntu 24.04 部署

目标系统：Ubuntu 24.04（自带 Python 3.12 与 `sqlite3` 模块），使用 systemd。以下命令都在 VM 上执行。

### 4.1 前置检查

```bash
python3 --version
# 期望：Python 3.12.x

python3 -c "import sqlite3; print(sqlite3.sqlite_version)"
# 期望：打印 SQLite 版本（3.40+），无 ImportError

systemctl --version | head -n 1
# 期望：systemd 版本信息（Ubuntu 24.04 默认 systemd 255）
```

如果 `import sqlite3` 失败，先安装系统自带的 Python（`sudo apt install python3`），本服务不依赖任何 pip 包。

### 4.2 把 `server/` 传到 VM

在仓库所在机器上（示例，替换用户名与地址）：

```bash
scp -r server user@<VM_IP>:/tmp/warrior-store-server
```

> **注意**：如果目标 `/tmp/warrior-store-server` 已存在，`scp -r server ...` 会把它嵌套成 `/tmp/warrior-store-server/server/`，导致 `cd /tmp/warrior-store-server` 后找不到 `app/` 与 `deploy/`。建议先删除/清空目标目录，或用 `scp -r server/. user@<VM_IP>:/tmp/warrior-store-server/`（复制目录内容而不是目录本身）。

或者 VM 上已有仓库/压缩包，直接进入含 `app/`、`deploy/` 的 `server/` 目录即可。

### 4.3 一键安装

```bash
cd /tmp/warrior-store-server
sudo bash deploy/install-ubuntu.sh
```

脚本会做这些事（全部在本机，不联网）：

1. 检查 root、`python3`、`sqlite3` 模块、systemd，并拒绝从 `/opt/warrior-store` 安装目录自身运行（避免复制自身后删掉源码）；
2. 先把 `app/` 与 `deploy/` 复制到 `/opt/warrior-store/.staging`（属主 `root:root`，不复制 `tests/`、`tools/`），在 staging 内用 `env -u PYTHONPATH` 做 `import app.main` 与逐文件语法检查；
3. 创建系统用户 `warrior-store`（已存在则跳过）；若同名用户组不存在，补建 `groupadd` 并 `usermod --gid` 设为主组；
4. 若 `/etc/warrior-store.env` 不存在，从样例复制并设为 `root:root 0640`；已存在则**保留内容不覆盖**，只把属主/权限重置为 `root:root 0640`；
5. 把旧 `app/`、`deploy/` 改名暂存，换入 staging 的新代码；换入失败自动还原旧目录；
6. 安装 2 个 service + 1 个 timer 到 `/etc/systemd/system/`；
7. `systemctl daemon-reload`，`systemctl enable --now warrior-store.service warrior-store-backup.timer`；
8. 如果服务原本在运行（重复安装/升级），自动重启以加载新代码；启动后等待 2 秒检查 `is-active`，失败则打印日志并以 1 退出。

脚本**不会**删除 `/var/lib/warrior-store` 下已有的数据库，也不会写任何密码。

### 4.4 安装后检查

```bash
sudo systemctl status warrior-store --no-pager
# 期望：Active: active (running)
# 注意：systemctl status 不显示 User=，运行身份用下面这条确认

systemctl show warrior-store -p User -p Group -p StateDirectory
# 期望：User=warrior-store、Group=warrior-store、StateDirectory=warrior-store

sudo journalctl -u warrior-store -n 100 --no-pager
# 期望：无 Traceback；可见服务启动日志

curl -sS http://127.0.0.1:8080/healthz
# 期望：{"status": "ok", "version": "1.0.0", "db": "ok", "uptime_s": ...}

sudo ss -lntp | grep 8080
# 期望：127.0.0.1:8080，进程为 python3
```

数据库目录由 systemd 的 `StateDirectory` 创建为 `/var/lib/warrior-store`（`0700 warrior-store:warrior-store`）；数据库文件默认 `/var/lib/warrior-store/store.sqlite3`。

### 4.5 手动安装（不用脚本）

如果不想用脚本，可按下面的最小步骤手动安装。**脚本额外提供 staging 换入/失败回滚、导入与语法检查、启动后 `is-active` 检查，推荐优先用脚本。** 先 `cd` 到含 `app/`、`deploy/` 的 `server/` 目录：

```bash
# 1) 系统用户与用户组（已存在则跳过；unit 里 Group=warrior-store，组必须存在）
sudo useradd --system --home /opt/warrior-store --shell /usr/sbin/nologin warrior-store || true
if ! getent group warrior-store >/dev/null 2>&1; then
  sudo groupadd --system warrior-store
  sudo usermod --gid warrior-store warrior-store
fi

# 2) 程序文件（只复制 app/ 与 deploy/）
sudo install -d -o root -g root -m 0755 /opt/warrior-store
sudo rm -rf /opt/warrior-store/app /opt/warrior-store/deploy
sudo cp -a app /opt/warrior-store/app
sudo cp -a deploy /opt/warrior-store/deploy
sudo chown -R root:root /opt/warrior-store/app /opt/warrior-store/deploy
sudo chmod -R u=rwX,go=rX /opt/warrior-store/app /opt/warrior-store/deploy

# 2b) 导入/语法检查（失败就不要启用服务）
sudo sh -c 'cd /opt/warrior-store && env -u PYTHONPATH PYTHONDONTWRITEBYTECODE=1 python3 -c "import app.main"'

# 3) 环境变量文件（只在不存在时创建；已有配置不要覆盖，但权限要收紧）
if [[ ! -f /etc/warrior-store.env ]]; then
  sudo install -o root -g root -m 0640 deploy/warrior-store.env.example /etc/warrior-store.env
else
  sudo chown root:root /etc/warrior-store.env
  sudo chmod 0640 /etc/warrior-store.env
fi

# 4) systemd 单元
sudo install -o root -g root -m 0644 deploy/warrior-store.service /etc/systemd/system/
sudo install -o root -g root -m 0644 deploy/warrior-store-backup.service /etc/systemd/system/
sudo install -o root -g root -m 0644 deploy/warrior-store-backup.timer /etc/systemd/system/

# 5) 启用并启动
sudo systemctl daemon-reload
sudo systemctl enable --now warrior-store.service warrior-store-backup.timer
sudo systemctl status warrior-store --no-pager
```

不需要手动建 `/var/lib/warrior-store`：主服务启动时 `StateDirectory=warrior-store` 会自动创建并设置属主/权限。不要手工把数据库 `chown` 成其他用户。

---

## 5. 配置

### 5.1 环境变量表（与 `app/config.py` 一致）

配置文件：`/etc/warrior-store.env`（样例见 `deploy/warrior-store.env.example`，权限建议 `0640 root:root`）。
布尔项接受 `1/0`，也接受 `true/false`、`yes/no`、`on/off`。

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `WARRIOR_STORE_HOST` | `127.0.0.1` | 监听地址；默认仅本机 |
| `WARRIOR_STORE_PORT` | `8080` | 监听端口；`0` 表示随机端口（测试用） |
| `WARRIOR_STORE_DB` | `data/store.sqlite3` | SQLite 路径；相对路径相对 `WorkingDirectory=/opt/warrior-store`，服务部署时样例已改为绝对路径 |
| `WARRIOR_STORE_PEPPER` | 空 | token 哈希 pepper；设置后**不可更改**，见 §5.4 |
| `WARRIOR_STORE_LOG_LEVEL` | `INFO` | `DEBUG/INFO/WARNING/ERROR/CRITICAL` |
| `WARRIOR_STORE_LOG_IP` | `1` | 访问日志是否记录客户端 IP；`0` 不记录 |
| `WARRIOR_STORE_ACCESS_LOG` | `1` | 是否输出访问日志（journald 单行 JSON）；`0` 关闭 |
| `WARRIOR_STORE_REGISTER_PER_HOUR` | `20` | 注册限流：每 IP 每小时次数；`0` 关闭 |
| `WARRIOR_STORE_RESULTS_PER_HOUR` | `600` | 上报限流：每玩家每小时次数；`0` 关闭 |
| `WARRIOR_STORE_TRUST_PROXY` | `0` | 是否信任 `X-Forwarded-For`；只有前置可信反向代理时才设 `1` |

说明：

- 上报限流由 `WARRIOR_STORE_RESULTS_PER_HOUR` 控制（默认 600 次/小时/玩家，`0` 关闭）；见 `API.md` §4.5。
- `WARRIOR_STORE_LOG_IP=0` 只影响日志中是否写 IP，不影响限流判断。
- 注册与上报限流都按固定窗口在内存计数，进程重启清零。

### 5.2 命令行参数（优先级高于环境变量）

`python3 -m app` 支持：

| 参数 | 对应环境变量 | 默认 |
|---|---|---|
| `--host` | `WARRIOR_STORE_HOST` | `127.0.0.1` |
| `--port` | `WARRIOR_STORE_PORT` | `8080` |
| `--db` | `WARRIOR_STORE_DB` | `data/store.sqlite3` |
| `--log-level` | `WARRIOR_STORE_LOG_LEVEL` | `INFO` |

优先级：**命令行参数 > 环境变量 > 内置默认值**。systemd 单元的 `ExecStart` 没有带命令行参数，所以生产环境实际生效的是 `/etc/warrior-store.env`。

### 5.3 改完配置怎么生效

```bash
sudo nano /etc/warrior-store.env      # 按需修改
sudo systemctl restart warrior-store
curl -sS http://127.0.0.1:8080/healthz
```

> **重要：改数据库路径时，必须同步改主服务与备份服务，否则会写不进去或备份错库。**
> 1. `/etc/warrior-store.env` 的 `WARRIOR_STORE_DB`；
> 2. `warrior-store.service` 的 `ReadWritePaths=` 与 `StateDirectory=`（默认只允许写 `/var/lib/warrior-store`，并由 systemd 创建该目录）；
> 3. `warrior-store-backup.service` 的 `ExecStart` 里 `--db` 与 `--out-dir`；
> 4. `warrior-store-backup.service` 的 `ReadWritePaths=` 与 `StateDirectory=`——备份服务也要能写**数据库所在目录**（SQLite 备份时需要读 WAL/写临时文件），以及备份输出目录。
> 改完 `sudo systemctl daemon-reload && sudo systemctl restart warrior-store`。备份目录与数据库目录都必须落在两个 unit 的 `ReadWritePaths` 允许的路径内。

### 5.4 PEPPER（token 哈希密钥）

- 默认留空：服务端保存 `SHA-256(token)`。
- 设为非空：保存 `HMAC-SHA256(pepper, token)`，更安全。
- **设置后不可更改**（也不能改回空）：一旦更改，所有已发出的 token 立即失效，玩家只能重新注册，且旧统计无法再用原 token 访问/删除。
- 建议在第一次注册前就设定，并把该行内容另行安全备份（例如密码管理器）；丢失 pepper 同样会让所有 token 失效。
- 该文件含密钥，不要提交版本库、不要设为全局可读（`0640 root:root` 即可；systemd 以 root 读取后再降权运行服务）。
- 若 pepper 含空格、`#`、引号等字符，按 systemd `EnvironmentFile` 规则用引号包裹，例如 `WARRIOR_STORE_PEPPER='abc def#ghi'`。

### 5.5 监听局域网 / 公网

默认 `127.0.0.1`，只有本机能访问。需要局域网其他机器访问时：

```bash
sudo sed -i 's/^WARRIOR_STORE_HOST=.*/WARRIOR_STORE_HOST=0.0.0.0/' /etc/warrior-store.env
sudo systemctl restart warrior-store

# 只放行你的局域网网段（示例：192.168.1.0/24）
sudo ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
sudo ufw status
```

安全警告：

- 服务本身只提供 **HTTP**，不终结 TLS；token 会以明文经过网络。只应在可信局域网使用。
- 不要把 `0.0.0.0:8080` 直接暴露到公网；公网访问请走 §8 的 nginx + TLS 反代，并只让 nginx 访问本机 8080。
- 若前面没有可信反向代理，**不要**设置 `WARRIOR_STORE_TRUST_PROXY=1`，否则客户端可伪造 `X-Forwarded-For` 绕过注册限流。
- 自报战绩没有权威校验（见 §10），公网开放会放大刷分风险。

---

## 6. API 使用

完整字段、错误码与边界以 [`API.md`](./API.md) 为准。下面给一条可直接复制的 curl 流程。

### 6.1 curl 全流程（注册 → 查询 → 上报 → 重复上报 → 批量 → 改名 → 删除）

```bash
BASE=http://127.0.0.1:8080

# 1) 注册（昵称 1~24 字符，可重名）
REG=$(curl -sS -X POST "$BASE/api/v1/players" \
  -H 'Content-Type: application/json' \
  -d '{"nickname":"科大路人甲"}')
echo "$REG"

# 2) 取出 player_id 与 token（token 只返回这一次，请立即保存）
PLAYER_ID=$(printf '%s' "$REG" | python3 -c 'import json,sys; print(json.load(sys.stdin)["player_id"])')
TOKEN=$(printf '%s' "$REG" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
echo "PLAYER_ID=$PLAYER_ID"
echo "TOKEN=$TOKEN"

# 3) 查询（公开接口，无需 token）
curl -sS "$BASE/api/v1/players/$PLAYER_ID"

# 4) 上报一场 PVE 胜（需要本人 token）
curl -sS -X POST "$BASE/api/v1/players/$PLAYER_ID/results" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"mode":"pve","result":"win","event_id":"demo-0001"}'

# 5) 用同一个 event_id 重发：应返回 "duplicate": true，统计不增加
curl -sS -X POST "$BASE/api/v1/players/$PLAYER_ID/results" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"mode":"pve","result":"win","event_id":"demo-0001"}'

# 6) 批量查询，最多 50 个 ID；未知 ID 会被省略
curl -sS "$BASE/api/v1/players?ids=$PLAYER_ID,p_0000000000000000"

# 7) 改昵称（需要本人 token）
curl -sS -X PATCH "$BASE/api/v1/players/$PLAYER_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"nickname":"新昵称"}'

# 8) 删除本人数据（204，无响应体；token 立即失效）
curl -sS -i -X DELETE "$BASE/api/v1/players/$PLAYER_ID" \
  -H "Authorization: Bearer $TOKEN"

# 9) 删除后再查：404 not_found
curl -sS -i "$BASE/api/v1/players/$PLAYER_ID"

# 10) 健康检查
curl -sS "$BASE/healthz"
```

Windows 上把 `python3` 换成 `python`。如果只需要看 HTTP 状态码，加 `-i`。

**接口要点**：

- 请求体上限 **8 KiB**；必须带唯一的 `Content-Length`（纯 ASCII 数字），**拒绝任何** `Transfer-Encoding`；curl 会自动带。短读/半关闭会返回 `400 invalid_body`，不会落库。
- 仅 JSON 响应带 `Content-Type: application/json; charset=utf-8`；所有响应带 `Cache-Control: no-store` 与 `X-Content-Type-Options: nosniff`。**204 无 body、无 `Content-Type`**，但仍有 `Cache-Control: no-store` 与 `X-Content-Type-Options: nosniff`。
- `event_id` 可选，8~64 位 `[A-Za-z0-9_-]`；网络重试时客户端应复用同一个 ID 去重。幂等记录每玩家保留最近 **2000 条**。
- 玩家 ID 形如 `p_` + 16 位小写十六进制；短 ID 是前 6 位，仅展示用，不保证唯一。
- 错误统一为 `{"error": {"code": "...", "message": "..."}}`，错误码表见 `API.md` §3。
- 401 带 `WWW-Authenticate: Bearer`；429 带 `Retry-After: 3600`（固定窗口 1 小时）。
- **404/401 语义**：`GET` 玩家不存在返回 `404 not_found`；`PATCH`/`DELETE`/`results` 对不存在的玩家返回 **`401 unauthorized`**（鉴权先于存在性检查，避免探测），不是 404。未知路径返回 404。

### 6.2 可选：用 jq 解析

`jq` 不是依赖，只是方便。Ubuntu 可 `sudo apt install jq`：

```bash
PLAYER_ID=$(printf '%s' "$REG" | jq -r '.player_id')
TOKEN=$(printf '%s' "$REG" | jq -r '.token')
```

### 6.3 Python `urllib` 最小示例（不依赖第三方库）

```python
import json
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080"


def call(method, path, payload=None, token=None):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read() or b"null")


status, player = call("POST", "/api/v1/players", {"nickname": "科大路人甲"})
print(status, player["player_id"], player["short_id"])

status, stats = call(
    "POST",
    f"/api/v1/players/{player['player_id']}/results",
    {"mode": "pve", "result": "win", "event_id": "demo-0001"},
    token=player["token"],
)
print(status, stats["pve"], stats["duplicate"])
```

游戏客户端以后接 HTTP 时可直接采用同样的请求格式；本服务不提供 SDK。

---

## 7. 备份 / 恢复 / 升级

### 7.1 自动备份（systemd timer）

安装脚本会启用 `warrior-store-backup.timer`：

- 每天 **04:00** 触发一次，`RandomizedDelaySec=300`（最多再随机延后 5 分钟，避免多机同时 IO）。
- `Persistent=true`：如果 04:00 时机器关机，开机后会补跑一次。
- 备份由 `warrior-store-backup.service`（`Type=oneshot`，用户 `warrior-store`）执行。

查看：

```bash
systemctl list-timers warrior-store-backup.timer
# 期望：NEXT 在下一次 04:00~04:05 之间（RandomizedDelaySec=300，最多再随机延后 5 分钟）；
#       首次安装后 LAST 可能显示 n/a（还没触发过），属正常

sudo systemctl start warrior-store-backup.service    # 手动立即跑一次
sudo journalctl -u warrior-store-backup -n 50 --no-pager
# 期望：出现「备份完成：...」与「轮转：保留最新 14 份...」

sudo ls -lh /var/lib/warrior-store/backups/
# 期望：warrior-store-YYYYmmdd-HHMMSS.sqlite3.gz，权限 0600、属主 warrior-store
```

### 7.2 手动备份（直接调用脚本）

```bash
sudo -u warrior-store /usr/bin/python3 /opt/warrior-store/deploy/backup.py \
  --db /var/lib/warrior-store/store.sqlite3 \
  --out-dir /var/lib/warrior-store/backups \
  --keep 14
```

参数：

| 参数 | 说明 |
|---|---|
| `--db` | 源数据库（必填），运行中也可备份 |
| `--out-dir` | 备份目录，默认 `/var/lib/warrior-store/backups` |
| `--keep` | 只保留最新 N 份本脚本生成的备份，默认 14，至少 1 |
| `--no-gzip` | 不压缩，输出 `.sqlite3`（默认 gzip 为 `.sqlite3.gz`） |

行为：

- 先用 `PRAGMA page_count`、`user_version == 1` 与 `players/stats/result_events` 三表校验源库；空库、错 schema、非本服务库一律拒绝，不写最终备份也不轮转。
- 用 SQLite `backup()` API 生成一致性快照，**不会**直接 `cp` 正在写入的数据库文件；运行中也可备份。
- 快照后执行 `PRAGMA integrity_check`，必须为 `ok`，否则删除临时文件并以 1 退出。
- 快照与压缩临时文件都用 `tempfile.mkstemp`（不可预测文件名、0600，后缀 `.tmp`）；压缩完成后 fsync 并 `os.replace` 为最终文件，失败会清理临时文件，不会留下会被误当成“最新备份”的半截 `.gz`。
- 文件名：`warrior-store-YYYYmmdd-HHMMSS.sqlite3[.gz]`（本机时区）；同一秒内重复执行会加 `-1`、`-2` 后缀。
- 轮转只处理 `--out-dir` 下**严格匹配** `warrior-store-<8位日期>-<6位时间>[-序号].sqlite3[.gz]` 的文件；按**文件名中的时间戳**（mtime 仅兜底）保留最新 `--keep` 份，源库与本次生成的文件永不删除。`.tmp`、其他前缀/格式的文件不参与轮转。
- 备份文件权限 0600、属主为运行脚本的用户（systemd 下是 `warrior-store`）。手动以 root 运行时注意 umask/属主，必要时 `chown warrior-store:warrior-store` 并 `chmod 0600`。
- 退出码：0 成功，1 运行失败（中文原因到 stderr），**2 为 argparse 参数错误**（如缺少 `--db`、`--keep` 非整数）。

> 备份与数据库在**同一块盘**，只能防误删、误改和数据库损坏，防不了整盘/整机故障。异地备份需自行同步，见 §7.7。

### 7.3 从备份恢复

恢复会整库替换。**必须先停止服务**，否则运行中的进程仍持有旧库句柄：

```bash
# 1) 停止服务
sudo systemctl stop warrior-store

# 2) 选一个备份（示例：取最新；只匹配 .sqlite3/.sqlite3.gz，排除 .tmp）
LATEST=$(ls -1t /var/lib/warrior-store/backups/warrior-store-*.sqlite3 \
  /var/lib/warrior-store/backups/warrior-store-*.sqlite3.gz 2>/dev/null | head -n 1)
echo "$LATEST"

# 3) 恢复（先解压到临时文件并做 integrity_check，再原子替换）
#    若目标库旁有旧的 -wal / -shm，必须加 --remove-wal（见下方说明）。
sudo /usr/bin/python3 /opt/warrior-store/deploy/restore.py \
  --backup "$LATEST" \
  --db /var/lib/warrior-store/store.sqlite3 \
  --force --remove-wal

# 4) 修正属主/权限（root 下脚本会自动 chown，通常无需手动执行）
sudo chown warrior-store:warrior-store /var/lib/warrior-store/store.sqlite3
sudo chmod 0600 /var/lib/warrior-store/store.sqlite3

# 5) 启动并验证
sudo systemctl start warrior-store
curl -sS http://127.0.0.1:8080/healthz
sudo journalctl -u warrior-store -n 50 --no-pager
```

`restore.py` 的规则：

- `--backup` 支持 `.sqlite3` 与 `.sqlite3.gz`（也会按文件头识别 gzip）；截断/损坏的 gzip 会拒绝。
- **默认会检查 `systemctl is-active --quiet warrior-store`**：服务仍在运行时拒绝恢复（先 `systemctl stop warrior-store`）。确认没有进程占用数据库时（如容器/非 systemd 环境）可加 `--allow-running` 跳过检查，脚本会打印警告。没有 `systemctl` 的环境自动跳过该检查。
- 先解压/复制到**目标同目录**的临时文件，校验内容非空（`page_count > 0`）、`user_version == 1` 且 `players/stats/result_events` 三表齐全，再校验 `PRAGMA integrity_check` 必须 `ok`；空库、其他应用的库、schema 过新/过旧、截断 gzip 一律拒绝。
- 目标路径是符号链接或是已存在但非普通文件（目录/设备）时拒绝恢复；目标库已存在且没有 `--force` 时拒绝覆盖，打印中文提示。
- 成功用 `os.replace` 原子替换；失败清理临时文件；退出码 0 成功、1 运行失败、**2 为 argparse 参数错误**（如缺少 `--backup`/`--db`）。
- **WAL/SHM/journal 残留会污染恢复结果**：旧 `store.sqlite3-wal` / `store.sqlite3-shm` / `store.sqlite3-journal` 会在下次打开数据库时被 SQLite 重放，可能把崩溃前的数据“复活”到新快照上。因此：
  - 检测到残留且没有 `--remove-wal` 时，脚本**直接拒绝恢复并退出 1**（加 `--force` 也不能跳过），同时打印可直接执行的 `rm -f` 命令；
  - 必须先 `sudo systemctl stop warrior-store` 确认服务已停止，再加 `--remove-wal`；脚本会在完整性校验通过后、`os.replace` 之前把这些 sidecar 改名为同目录隐藏文件暂存，替换成功后再删除；替换失败会改名还原；
  - 若你更愿意手动处理，删除 sidecar 后不加 `--remove-wal` 重新运行即可。
- **属主**：root 下运行脚本时，会用旧目标文件的 `uid/gid` 自动 `chown` 恢复后的数据库；旧文件不存在时尝试 `warrior-store` 用户，系统无该用户则跳过。非 root 或 Windows 会跳过并在最后提示手动 `chown`。权限仍统一设为 `0600`。
- 恢复完成后按脚本提示执行 `systemctl start warrior-store`，再用 `curl -sS http://127.0.0.1:8080/healthz` 验证。

### 7.4 恢复演练（不影响线上）

可以恢复到临时路径，只验证备份可用：

```bash
LATEST=$(ls -1t /var/lib/warrior-store/backups/warrior-store-*.sqlite3 \
  /var/lib/warrior-store/backups/warrior-store-*.sqlite3.gz 2>/dev/null | head -n 1)
RESTORE_DIR=$(mktemp -d)
sudo /usr/bin/python3 /opt/warrior-store/deploy/restore.py \
  --backup "$LATEST" --db "$RESTORE_DIR/restore-check.sqlite3" --force --allow-running
# 这里恢复到临时路径，不会碰线上库，所以用 --allow-running 跳过“服务运行中”检查；
# 若是恢复到线上库（§7.3），必须先停服务，绝不要加 --allow-running。
# 用 sudo python3（或 sudo -u warrior-store python3）打开临时库，避免普通用户读不到 0600 文件
sudo python3 -c "import sqlite3; c=sqlite3.connect('$RESTORE_DIR/restore-check.sqlite3'); print(c.execute('PRAGMA integrity_check').fetchone()); c.close()"
# 期望：('ok',)
# 每次用独立 mktemp 目录，连 -wal/-shm 一起清掉
sudo rm -rf "$RESTORE_DIR"
```

### 7.5 升级步骤

1. **先备份**（见 §7.2）。
2. 把新版本 `server/` 传到 VM，在 `server/` 目录重新执行安装脚本：

   ```bash
   cd /path/to/new/server
   sudo bash deploy/install-ubuntu.sh
   ```

   脚本会覆盖 `/opt/warrior-store/app` 与 `deploy`，保留 `/etc/warrior-store.env` 与数据库；若服务原本在运行会自动重启。
3. 验证：

   ```bash
   sudo systemctl status warrior-store --no-pager
   curl -sS http://127.0.0.1:8080/healthz
   sudo journalctl -u warrior-store -n 100 --no-pager
   ```

只改了 `deploy/*.service` 或 timer 时，重新运行安装脚本即可（含 `daemon-reload`）。只改了 `app/` 时也可以手动 `cp` 后 `sudo systemctl restart warrior-store`，但不推荐跳过安装脚本，容易漏文件。

### 7.6 schema 版本

当前 schema 版本为 **1**（`PRAGMA user_version = 1`），1.0.0 不包含自动迁移。查看：

```bash
sudo -u warrior-store python3 - <<'PY'
import sqlite3
conn = sqlite3.connect("/var/lib/warrior-store/store.sqlite3")
print("user_version =", conn.execute("PRAGMA user_version").fetchone()[0])
conn.close()
PY
# 期望：user_version = 1
```

以后若修改表结构，必须先更新 `API.md` 并提供迁移脚本；升级前务必先备份。

### 7.7 异地备份（需自行配置）

本服务只负责本机快照。要防整机故障，请把 `/var/lib/warrior-store/backups/` 同步到另一台机器，例如：

```bash
# 需要预先配置 SSH 密钥登录，不要把密码写进脚本
rsync -av /var/lib/warrior-store/backups/ backup@backup-host:/srv/warrior-store-backups/
```

可以用 cron 或另一台机器上的 systemd timer 定时拉取。备份文件包含玩家 ID、昵称、token 哈希与统计，传输和存放都要限制权限。

---

## 8. 反向代理（可选）

**默认不需要 nginx。** 服务默认只监听 `127.0.0.1:8080`，本机客户端或同机代理直接访问即可。只有需要**公网域名 + HTTPS** 时才加反向代理。

### 8.1 nginx 示例（TLS 终结在本机）

安装 nginx 与 certbot（需要联网，安装脚本不会做）：

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
```

**第一步：先只放一个监听 80 的 server 块**（此时还没有证书，不要先写引用 `/etc/letsencrypt/...` 的 443 块，否则 `nginx -t` 会因证书不存在失败）：

```nginx
# /etc/nginx/sites-available/warrior-store
server {
    listen 80;
    server_name store.example.com;

    # API 请求体上限 8 KiB；这里放宽到 16k，让应用自己返回 JSON 格式的 413
    client_max_body_size 16k;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # 覆盖而非追加：只让客户端看到直连反代的那一个 IP，避免伪造的 XFF 被保留
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

启用并确认可访问：

```bash
sudo ln -s /etc/nginx/sites-available/warrior-store /etc/nginx/sites-enabled/warrior-store
sudo nginx -t
sudo systemctl reload nginx
curl -sS http://store.example.com/healthz
```

**第二步：用 certbot 申请证书并让 certbot 改写/生成 443 配置**：

```bash
sudo certbot --nginx -d store.example.com
# 按提示选择把 80 重定向到 HTTPS；certbot 会部署证书并自动续期
sudo systemctl list-timers | grep certbot
```

**第三步（可选）：核对最终配置**。certbot 通常会生成 443 的 `server` 块与 80→443 跳转；确认其中包含上面的 `proxy_set_header X-Forwarded-For $remote_addr;` 等反代头（certbot 只加 TLS 相关指令，不会替你补这些头）。确认后：

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -sS https://store.example.com/healthz
```

前置条件：域名已解析到该 VM，安全组/防火墙放行 80 与 443；8080 **不要**对公网放行。

### 8.2 反向代理下的配置

确认 nginx 与 `warrior-store` 在同一台机器、且服务只监听 `127.0.0.1`，然后：

```bash
sudo sed -i 's/^WARRIOR_STORE_TRUST_PROXY=.*/WARRIOR_STORE_TRUST_PROXY=1/' /etc/warrior-store.env
sudo systemctl restart warrior-store
```

- 只有确实存在可信反代时才设 `1`；否则任何人都能伪造 `X-Forwarded-For`，绕过按 IP 的注册限流。
- `WARRIOR_STORE_TRUST_PROXY=1` **只适用于「前面恰好一层可信反向代理」**的部署；服务端取 `X-Forwarded-For` 的**最后一段**（即直连反代看到的对端地址）。上面的 nginx 示例用 `$remote_addr` 覆盖该头，正是为了让最后一段可信。
- 多层反向代理（如 CDN → nginx → 服务）需要自行调整：确认每一层都覆盖/清洗 XFF，并保证服务前面的最后一层写入的地址可信；否则同样可能被伪造。
- 如果反代不在本机，服务必须监听内网地址（如 `0.0.0.0` 或内网 IP），此时请用防火墙只放行反代地址，并自行评估链路安全。
- HTTPS 加解密由 nginx 完成，服务本身仍只说 HTTP。

---

## 9. 排错表

先看日志，大多数问题日志里有中文或明确异常：

```bash
sudo journalctl -u warrior-store -n 100 --no-pager
sudo journalctl -u warrior-store -f
sudo journalctl -u warrior-store-backup -n 50 --no-pager
```

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 服务起不来，`status=1/FAILURE` | 配置值非法（如端口不是整数、布尔不是 1/0）、数据库/目录/schema 错误、代码异常 | 看 `journalctl -u warrior-store -n 100 --no-pager`；**配置错误退出码 2**（打印「配置错误：环境变量 ...」），DB/代码错误退出码 1（打印「服务启动失败：...」） |
| `Address already in use` | 8080 被别的进程占用，或手动又起了一个实例 | `sudo ss -lntp \| grep 8080`；`ps aux \| grep '[p]ython3 -m app'`；停掉多余实例 |
| `Permission denied` / `Read-only file system` | 数据库路径不在 `ReadWritePaths` 内，或目录属主不对 | 用默认 `/var/lib/warrior-store`；检查 `ls -ld /var/lib/warrior-store` 应为 `warrior-store:warrior-store 0700`；改路径要同步改 unit（§5.3） |
| `database is locked` | 同时跑了第二个写进程，或有异常长事务 | 确认只有一个实例；停掉手动启动的 `python -m app`；服务内已有 `busy_timeout` 与有限重试 |
| 接口返回 `401 unauthorized` | 缺 token、token 写错、玩家已删除、pepper 被改过；`PATCH`/`DELETE`/`results` 对**不存在的玩家也返回 401**（鉴权先于存在性检查，避免探测） | 重新注册获取新 token；检查 `Authorization: Bearer <token>` 格式；不要用 401 判断玩家是否存在，查 `GET` |
| 接口返回 `404 not_found` | 仅 `GET` 玩家不存在/已删除、批量查询路径写错、未知路径；不会用于需要鉴权的接口 | 用注册/查询返回的完整 `player_id`；确认 `/api/v1` 前缀 |
| 接口返回 `413 payload_too_large` | 请求体超过 8 KiB | 精简请求体；确认没有走 chunked；nginx 反代时 `client_max_body_size` 不要小于 8k |
| 接口返回 `429 rate_limited` | 注册超过 20 次/小时/IP，或上报超过限额；失败/非法请求也占额度 | 响应带 `Retry-After: 3600`，等 1 小时窗口过去；局域网多人共用一个出口 IP 时可在 `/etc/warrior-store.env` 调大 `WARRIOR_STORE_REGISTER_PER_HOUR` 或设 0 |
| `/healthz` 返回 `503 db_unavailable` | 数据库文件不存在/被删、`user_version != 1`、`players/stats/result_events` 任一表缺失、打不开/权限错/磁盘满 | 检查数据库路径与权限、`df -h`、journal；修复/恢复后 `systemctl restart warrior-store`。注意 SQLite 会新建空库，`/healthz` 用文件存在 + schema + 三表检查，删库后会正确报 503 |
| nginx 后面所有客户端 IP 都是 `127.0.0.1` | 没信任 `X-Forwarded-For` | 确认反代可信后设 `WARRIOR_STORE_TRUST_PROXY=1` 并重启 |
| 备份定时器没跑 | timer 未启用/机器关机 | `systemctl list-timers warrior-store-backup.timer`；`sudo systemctl enable --now warrior-store-backup.timer`；`Persistent=true` 会在开机后补跑 |
| 备份失败 | 磁盘满、备份目录不可写、数据库损坏 | 看 `journalctl -u warrior-store-backup`；检查 `df -h` 与目录属主；脚本会打印中文原因并以 1 退出 |
| 访问日志没有 IP | 设置了 `WARRIOR_STORE_LOG_IP=0` | 改为 `1` 并重启；关闭 IP 是隐私选项，不是故障 |
| 日志完全看不到访问记录 | 设置了 `WARRIOR_STORE_ACCESS_LOG=0`，或日志级别过高 | 检查 `/etc/warrior-store.env`；`WARRIOR_STORE_LOG_LEVEL=INFO` |

---

## 10. 安全与隐私

- **token 即密码**：只在注册响应中出现一次，服务端只存 `SHA-256(token)`（设置 pepper 后为 HMAC-SHA256），比较用常数时间算法。日志、查询响应、错误响应都不会包含 token。
- **数据库权限**：服务以 `warrior-store` 用户运行，`UMask=0077`、`StateDirectoryMode=0700`，数据库与备份文件默认只有服务用户可读；备份目录同样在 `/var/lib/warrior-store` 内。
- **默认只监听本机** `127.0.0.1:8080`，不直接暴露公网。需要公网时走 nginx + TLS，并限制来源。
- **日志**：访问日志是单行 JSON（便于 journald 检索），不记录 Authorization、token 或请求体；默认记录客户端 IP，可用 `WARRIOR_STORE_LOG_IP=0` 关闭。访问日志会记录 **path（含 query string）**，因此**不要把 token 放在 URL 查询参数里**；鉴权只从 `Authorization: Bearer` 头读取。
- **版本库**：`server/data/`、`*.sqlite3`、`__pycache__/` 是本地产物。当前 `.gitignore` **未覆盖**这些路径（按项目硬规则未擅自修改），提交前需手动排除，或由用户决定是否补规则。
- **自报战绩无权威校验**：v1 由客户端上报自己的胜负，服务端无法验证对局真伪，恶意客户端可以虚增统计；PVP 双方各自上报各自一场，不做互证。反作弊/互证方案待裁决。
- **自助删除**：`DELETE /api/v1/players/{player_id}` 会删除资料、统计与幂等记录，token 立即失效。**已有历史备份不会被 DELETE 删除**：备份里仍可能包含该玩家的 ID、昵称、token 哈希与统计，需按备份保留期到期后随旧备份一起淘汰；备份保留期与删除后是否重写历史备份的策略仍待用户裁决。
- **备份即敏感数据**：备份包含玩家 ID、昵称、token 哈希与统计；异地同步和存放要限制访问。pepper 要单独备份，丢失或更改都会让 token 全部失效。
- **已知待裁决**：排行榜、公网入口/域名、数据保留期、反作弊方案。当前版本不提供排行榜，也不主动清理玩家数据。
- 速率限制仅防误用/轻量滥用，不是 DDoS 防护；公网部署应在 nginx/云防火墙层做额外限制。

### 10.1 设计取舍

- **为什么用标准库 `http.server` + `sqlite3`，不用 FastAPI/Django/ORM**：目标环境是 Ubuntu 24.04 自带的 Python 3.12，安装脚本不联网、不 `pip install`、不建 venv，评审者拿到源码就能跑；数据模型只有三张表、接口只有 7 个，手写路由与参数化 SQL 比引入框架/ORM/迁移工具更小、更可读。代价是 HTTP 边界要自己处理（严格的 `Content-Length`、短读拒绝、错误响应排空、未知方法返回 JSON 405/404），这些已写成测试；如果以后要做排行榜、多实例或复杂查询，再评估迁移到框架。
- **为什么默认不需要 nginx**：服务默认只监听 `127.0.0.1:8080`，本机客户端或同机反代直接访问即可；只有需要公网域名 + HTTPS 时才加 nginx 终结 TLS（§8）。这样默认部署不依赖证书、域名和额外进程，也避免把明文 HTTP 直接暴露到公网。
- **单实例的取舍**：SQLite 是单写库，限流计数在进程内存；单实例下两者都简单可靠，不需要 Redis/共享存储。代价是不能水平扩容、多实例不共享限流、重启后限流清零。当前目标是单机小规模统计，这个取舍成立；扩容需先改存储与限流方案。
- **8 KiB 请求体上限**：本服务只接收昵称和一场结果（`nickname`/`mode`/`result`/`event_id`），8 KiB 足够；上限同时约束内存和滥用面。超过返回 `413 payload_too_large`，且必须用 `Content-Length`（不支持 chunked），便于在读取前就拒绝。
- **限流取舍**：注册按 IP 默认 20 次/小时、上报按玩家默认 600 次/小时，固定窗口、内存计数；目的是防误用和轻量滥用，不是 DDoS 防护。失败/非法请求也会占额度（注册在解析 body 前计数，上报在鉴权后、解析 body 前计数），避免用错误请求绕过限制；需要更严格防护时在 nginx/云防火墙层做。
- **为什么用 `event_id` 幂等、窗口 2000**：网络重试、客户端超时重发都可能把同一场对局上报两次；客户端复用同一 `event_id` 时服务端返回 `duplicate: true` 且 **games/wins 都不增加**。每玩家保留最近 2000 条记录：按默认 600 次/小时满速上报可覆盖约 3 小时，远长于常见重试窗口，同时把单玩家存储控制在有限范围（写入时顺带清理更老的记录）。不带 `event_id` 的上报无法去重。

### 10.2 数据模型与表结构

SQLite schema `PRAGMA user_version = 1`，连接级 `PRAGMA foreign_keys=ON`、`journal_mode=WAL`、`synchronous=FULL`。三张表：

| 表 | 列 | 约束/说明 |
|---|---|---|
| `players` | `id TEXT PRIMARY KEY`、`nickname TEXT NOT NULL`、`token_hash BLOB NOT NULL`、`created_at TEXT NOT NULL`、`updated_at TEXT NOT NULL` | `id` 为 `p_` + 16 位小写十六进制；`token_hash` 只存 `SHA-256(token)`（配 pepper 时 HMAC-SHA256），永不存明文；`created_at` 对外返回，**`updated_at` 仅内部使用**（改昵称时更新，不出现在任何 API 响应中） |
| `stats` | `player_id TEXT NOT NULL`、`mode TEXT NOT NULL`、`games INTEGER NOT NULL DEFAULT 0`、`wins INTEGER NOT NULL DEFAULT 0` | `player_id REFERENCES players(id) ON DELETE CASCADE`；`mode CHECK (mode IN ('pve','pvp'))`；`games >= 0`、`wins >= 0 AND wins <= games`；`PRIMARY KEY (player_id, mode)`；注册时为 pve/pvp 各插一行 0/0 |
| `result_events` | `player_id TEXT NOT NULL`、`event_id TEXT NOT NULL`、`created_at TEXT NOT NULL` | `player_id REFERENCES players(id) ON DELETE CASCADE`；`PRIMARY KEY (player_id, event_id)`；用于 `event_id` 幂等，每玩家只保留最近 **2000 条**（写入新事件后按 `rowid DESC` 清理更老的） |

- 外键 `ON DELETE CASCADE`：`DELETE /api/v1/players/{id}` 删除 `players` 一行时，`stats` 与 `result_events` 一并删除，不需要应用层逐表清理。
- `win_rate` **不落库**，查询/上报响应时由 `wins / games` 计算，保留 4 位小数（常规四舍五入，`ROUND_HALF_UP`；如 1/32 → `0.0313`），`games == 0` 时为 `null`。
- 不存对局明细、伤害/扣血、回合数、角色/曜彩使用；没有其他业务表。新增统计字段必须先经用户裁决并同步 `API.md`/`DESIGN.md`。
- schema 版本高于程序支持时启动失败（中文报错、退出 1）；当前 1.0.0 不包含自动迁移。备份/恢复脚本同样校验 `user_version == 1` 与三表齐全。

### 10.3 术语表

| 术语 | 含义 |
|---|---|
| `player_id` / 玩家 ID | 服务端生成的公开标识，`p_` + 16 位小写十六进制（共 18 字符），注册响应返回，用于所有玩家路径 |
| 短 ID / `short_id` | `player_id` 前 6 个字符（如 `p_3f9a`），**仅展示用，不保证唯一**，不能用于 API 路径 |
| token | 注册时一次性返回的 32 字节随机凭证（URL-safe Base64，43 字符）；即密码，服务端只存哈希，丢失只能重新注册 |
| `event_id` | 客户端生成的事件 ID（8~64 位 `[A-Za-z0-9_-]`），用于上报幂等；网络重试必须复用同一个值 |
| `games` | 该模式累计上报场次（PVE/PVP 分开） |
| `wins` | 该模式累计胜场（`result == "win"` 时增加） |
| `win_rate` | `wins / games`，保留 4 位小数；`games == 0` 时为 `null` |
| `duplicate` | 上报响应字段；`true` 表示该 `player_id + event_id` 已记录过，本次 **games/wins 都不变** |
| 上报 | 客户端调用 `POST /api/v1/players/{id}/results` 记录一场 PVE/PVP 胜负 |
| 幂等 | 同一 `event_id` 重复上报只计一次；重复请求仍返回 200 与当前统计，并标记 `duplicate: true` |
| PVE / PVP | 人机 / 玩家对战两种模式；统计完全分开，互不影响 |

### 10.4 常见问题（FAQ）

- **token 丢了怎么办？** 服务端只存哈希，无法找回；只能重新注册一个新玩家。旧玩家的统计数据仍在，但没有 token 不能再上报/改名/删除。注册前建议客户端立即持久化 token。
- **局域网多人共用一个出口 IP，注册被 429？** 注册限流按 IP（默认 20 次/小时）。可在 `/etc/warrior-store.env` 调大 `WARRIOR_STORE_REGISTER_PER_HOUR` 或设 `0` 关闭注册限流，然后 `systemctl restart warrior-store`。共享出口的 NAT 下这是预期行为。
- **DELETE 之后备份里还有我的数据吗？** 会。`DELETE` 删除在线库中的资料、统计与幂等记录，token 立即失效；但**历史备份不会被删除**，备份里仍可能含 ID、昵称、token 哈希与统计，需等备份保留期到期后随旧备份淘汰。保留期与是否重写历史备份仍待用户裁决。
- **有排行榜/反作弊吗？** 没有。v1 只有单玩家统计查询与批量查询；自报战绩无权威校验，恶意客户端可虚增统计，PVP 双方各自上报、不做互证。反作弊/互证与排行榜口径待裁决。
- **能多实例/集群部署吗？** 不支持。SQLite 单写、限流在进程内存，多实例不共享限流；请只运行一个写进程。需要扩容要先改存储与限流方案。
- **游戏客户端接入了吗？** 没有。本轮只交付独立服务端，不改 `game/`；客户端接入是后续独立工作，接口格式可直接按 `API.md` 对接。
- **网络超时重试会不会重复计数？** 复用同一个 `event_id` 就不会：第二次返回 `duplicate: true`，games/wins 不变。每次重试生成新 `event_id` 则会被当成新对局。
- **收到 429 要等多久？** 响应头 `Retry-After: 3600`，即固定窗口 1 小时；等到窗口过去再重试，不要按 60 秒频繁重试。
- **为什么 `PATCH`/`DELETE` 对不存在的玩家返回 401 而不是 404？** 鉴权先于存在性检查，避免用状态码探测某个 `player_id` 是否存在；只有公开的 `GET` 与批量查询会返回/省略不存在玩家。
- **`/healthz` 返回 503 但进程还活着？** 说明数据库文件不存在、`user_version != 1`、三张表缺失或打不开；按 §9 排错表检查路径/权限/磁盘，修复后重启。
- **昵称里的 RTL/零宽字符会被拒绝吗？** 不会。当前只拒绝控制字符、行/段分隔符与孤立代理项；RTL/零宽等格式字符未额外禁止。如需更严格，必须先改 `API.md` 契约再改校验。

### 10.5 版本与变更说明

- **1.0.0（2026-11-12）**：首个交付版本。`/api/v1` 接口冻结；服务版本由 `/healthz` 的 `version` 返回；schema `user_version = 1`（无自动迁移）。
- **兼容性承诺**：`/api/v1` 内只做向后兼容的修正（补文档、修 bug、加不破坏现有字段的行为）；**破坏性变更必须升 `/api/v2`**，不得静默修改 v1 语义。新增统计字段属于口径变更，必须先经用户裁决。
- **本轮复核修复（2026-11-14，均不改变数据口径）**：严格 `Content-Length`（唯一、纯 ASCII 数字）与短读拒绝；错误响应尽量排空 body 并带 `Connection: close`；未知 HTTP 方法返回 JSON 405/404（不再 HTML 501）；JSON 解析异常统一 400（含深嵌套/超大整数）；数据库 schema/健康检查 fail-fast（文件 + `user_version` + 三表）；批量查询两条 SELECT 同一读快照；幂等窗口 500 → **2000**；胜率改为常规四舍五入 4 位；备份轮转严格按文件名时间戳并排除源库/本次文件；备份/恢复校验 schema 与三表；恢复新增 `--allow-running`、符号链接/非普通文件拒绝、sidecar 暂存回滚；安装脚本 staging 复制/导入/语法检查后再换入，并补建用户组。
- 变更记录以本节与 `API.md` §8、`DESIGN.md` §10 为准；`server/README.md` 只描述当前行为。

---

## 11. 验收清单

以下命令在 **Ubuntu 24.04 VM** 上执行，逐条核对期望现象。

### 11.1 安装与运行

| # | 命令 | 期望现象 |
|---|---|---|
| 1 | `python3 --version` | `Python 3.12.x` |
| 2 | `python3 -c "import sqlite3; print(sqlite3.sqlite_version)"` | 打印 SQLite 版本，无异常 |
| 3 | `cd /tmp/warrior-store-server && sudo bash deploy/install-ubuntu.sh` | 最后打印「安装完成」及后续命令；无错误退出 |
| 4 | `systemctl is-active warrior-store` | `active` |
| 5 | `systemctl is-enabled warrior-store warrior-store-backup.timer` | 均输出 `enabled` |
| 6 | `systemctl show warrior-store -p User -p Group -p StateDirectory` | `User=warrior-store`、`Group=warrior-store`、`StateDirectory=warrior-store` |
| 7 | `sudo ls -ld /var/lib/warrior-store` | `drwx------ ... warrior-store warrior-store ... /var/lib/warrior-store` |
| 8 | `sudo -u warrior-store test -w /var/lib/warrior-store && echo writable` | 输出 `writable` |
| 9 | `curl -sS http://127.0.0.1:8080/healthz` | `{"status":"ok","version":"1.0.0","db":"ok","uptime_s":...}` |
| 10 | `sudo ss -lntp \| grep 8080` | 仅 `127.0.0.1:8080`，进程 `python3` |
| 11 | `sudo journalctl -u warrior-store -n 100 --no-pager` | 无 Traceback、无 `Address already in use` |

### 11.2 API 与备份

| # | 命令 | 期望现象 |
|---|---|---|
| 12 | 在源码 `server/` 目录执行 `python3 tools/smoke.py` | 打印 12 条 `[OK] ...`，最后 `SMOKE OK`，退出码 0 |
| 13 | 按 §6.1 手动跑注册 → 查询 → 上报 → 重复上报 → 批量 → 改名 → 删除 | 状态码依次为 201/200/200/200/200/200/204/404，最后的 `/healthz` 为 200；重复上报 `duplicate: true` 且 games/wins 不增加 |
| 14 | `sudo systemctl start warrior-store-backup.service` | 命令成功返回 |
| 15 | `sudo journalctl -u warrior-store-backup -n 50 --no-pager` | 出现「备份完成：...」与「轮转：保留最新 14 份...」 |
| 16 | `sudo ls -lh /var/lib/warrior-store/backups/` | 至少一个 `warrior-store-YYYYmmdd-HHMMSS.sqlite3.gz`，权限 0600、属主 `warrior-store` |
| 17 | `systemctl list-timers warrior-store-backup.timer` | `NEXT` 在 04:00~04:05 之间（随机延迟 ≤5 分钟）；首次安装 `LAST` 可能为 `n/a` |
| 18 | 用 `--keep 2` 连续执行手动备份 3 次后 `sudo ls /var/lib/warrior-store/backups/ \| wc -l` | 只剩 2 份（验证轮转；不要用默认 14 只备份 2 次） |
| 19 | 按 §7.4 恢复到 `mktemp -d` 临时目录并查 `PRAGMA integrity_check` | `('ok',)`；清理整个临时目录（含 `-wal/-shm`） |
| 20 | 重启 VM 后 `systemctl is-active warrior-store` 与 `systemctl list-timers warrior-store-backup.timer` | 服务自动启动，timer 仍在计划中（可选验收） |
| 21 | 从另一台机器 `curl http://<VM_IP>:8080/healthz` | 默认配置下连接失败/超时（因为只监听 127.0.0.1），符合预期 |
| 22 | 在源码 `server/` 目录执行 `python3 -m unittest discover -s tests -v` | `Ran 131 tests`、`OK (skipped=2)`，退出码 0 |
| 23 | 重复安装/升级：向数据库写入一场后再次 `sudo bash deploy/install-ubuntu.sh` | 安装成功；`/etc/warrior-store.env` 内容保留；数据库与统计不丢；服务被重建为 active |
| 24 | 服务运行中先上报一场，再 `sudo systemctl start warrior-store-backup.service`，把新备份恢复到临时库查询 | 最新一场在备份中（运行中备份包含已提交写入） |
| 25 | 制造真实 WAL：服务运行中上报后 `systemctl stop`，确认存在 `store.sqlite3-wal/-shm`，用 `restore.py --force --remove-wal` 恢复 | 恢复成功，sidecar 被处理，`/healthz` 200；不加 `--remove-wal` 时应拒绝并退出 1 |
| 26 | 手动执行 `backup.py --no-gzip ...` | 生成 `.sqlite3`（无 `.gz`），可被 `restore.py` 恢复 |
| 27 | 服务运行中执行 `restore.py`（不加 `--allow-running`） | 拒绝恢复并退出 1；加 `--allow-running` 后跳过检查并打印警告（仅在确认无进程占用时使用） |
| 28 | `sudo ls -l /var/lib/warrior-store/store.sqlite3 /var/lib/warrior-store/backups/` | 数据库与备份均 `-rw-------`（0600）、属主 `warrior-store` |
| 29 | `sudo systemctl stop warrior-store` 后看 `systemctl is-active warrior-store` 与 journal | `inactive`，journal 出现「收到信号 ... 正在停止服务…」「服务已停止」，无 Traceback |
| 30 | 在源码目录检查换行符（如 `grep -rlU $'\r' app deploy tools tests`） | 无输出（脚本/单元/代码均为 LF；Windows 编辑后尤其要查） |
| 31 | `curl -i` 触发 401 与 429 | 401 带 `WWW-Authenticate: Bearer`；429 带 `Retry-After: 3600`；两者均为 JSON 错误体，带 `no-store`/`nosniff` |

### 11.3 本次交付的验证状态（如实说明，2026-11-14）

**已执行并通过（2026-11-14，本机 Windows + Python 3.13 + Git Bash；cwd 为 `server/`，除标注外）：**

- `bash -n deploy/install-ubuntu.sh`：语法检查通过。
- `python -m py_compile deploy/backup.py deploy/restore.py tools/smoke.py`：编译检查通过。
- `python -m compileall app tests tools`：通过，退出码 0。
- `python -m unittest discover -s tests -v`：**131 项 OK、2 项跳过**（`Ran 131 tests` / `OK (skipped=2)`）。应用层 116 项；部署脚本 15 项（13 通过 + 2 项 POSIX-only 跳过：符号链接、伪 `systemctl`）。覆盖存储/幂等/级联删除/并发、昵称/模式/结果/事件 ID/玩家 ID 边界、HTTP 全接口、鉴权、限流 429、413、405、持久化、配置解析与部署脚本。
- `python tools/smoke.py`：12 条 `[OK]`，最后 **`SMOKE OK`**（自起临时服务 + 临时数据库，覆盖注册→查询→上报→幂等→批量→改名→删除）。
- `python -m app --db <临时库> --port 18099` + `curl /healthz`：返回 `{"status":"ok","version":"1.0.0","db":"ok",...}`。
- `backup.py` / `restore.py` 功能自测（Windows + Python 3.13 + SQLite 3.50.4，临时目录）：gzip 备份、运行时快照、`integrity_check`、恢复、无 `--force` 拒绝覆盖、`--force` 覆盖、`--no-gzip`、`--keep` 轮转、坏库/空库/错 schema/截断 gzip 失败并清理半成品、运行中恢复拒绝与 `--allow-running`、WAL/SHM/journal 残留默认拒绝与 `--remove-wal`，均符合预期。
- `python -m unittest tests.test_deploy_scripts -v`：15 项中 13 项通过、2 项跳过（gzip 完整性、轮转/源库与无关文件/未来 mtime、无效源库、真实未 checkpoint WAL、`--force`、`--no-gzip`、sidecar 与 `--remove-wal`、坏备份/错 schema/截断 gzip、目录/符号链接目标、运行中服务与 `--allow-running`）。

**尚未验证（需在对应环境补做）：**

- `systemd` 单元、`install-ubuntu.sh` 的实际安装流程、备份 timer 的定时触发：**未在真实 Ubuntu 24.04 上执行过**（本机是 Windows，无法运行 systemd；也没有获得 VM 的 SSH 授权）。必须在 VM 上按 §11.1/§11.2 逐条验收（第 22~31 条是本轮新增的补充验收）。
- 信号优雅停止（SIGTERM/SIGINT）在 Windows 上无法按 Unix 语义验证，需在 Ubuntu/systemd 上确认 `systemctl stop` 能干净退出。
- nginx/TLS、异地备份：属于可选部署，示例配置未在本机验证。

---

## 12. 明确不做

- 不改游戏客户端；客户端接入是后续独立工作。
- 不做排行榜、域名申请、HTTPS 终结（TLS 由 nginx 等外部组件负责，服务只说 HTTP）。
- 不存对局明细、伤害/扣血、回合数、角色或曜彩使用情况。
- 不做多实例/集群部署；限流计数在进程内存，SQLite 单写。
- 不提供密码找回：token 丢失只能重新注册。
- 不自动清理玩家数据；保留期策略待用户裁决。
