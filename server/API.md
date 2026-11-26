# 玩家数据存储服务 API（v1，冻结契约）

> 服务端只保存：玩家 ID、昵称、创建时间、PVE/PVP 的场次与胜场。
> **不保存对局明细，也不统计伤害/扣血、回合数、角色或曜彩使用等任何其他数据**（DESIGN §11 P3 口径）。
> 本文是实现与客户端对接的唯一契约；实现变更必须先改本文。

## 0. 接口总览

| 方法 | 路径 | 鉴权 | 限流 | 成功响应 |
|---|---|---|---|---|
| `POST` | `/api/v1/players` | 无 | 20 次/小时/IP | `201` 玩家资料 + 一次性 token |
| `GET` | `/api/v1/players?ids=a,b,c` | 无 | 无 | `200` `{"players":[...]}` |
| `GET` | `/api/v1/players/{player_id}` | 无 | 无 | `200` 公开资料 |
| `PATCH` | `/api/v1/players/{player_id}` | Bearer | 无 | `200` 最新公开资料 |
| `POST` | `/api/v1/players/{player_id}/results` | Bearer | 600 次/小时/玩家 | `200` 最新统计 |
| `DELETE` | `/api/v1/players/{player_id}` | Bearer | 无 | `204` 无响应体 |
| `GET` | `/healthz` | 无 | 无 | `200` 健康；DB 异常 `503` |

限流次数均可配置（见 §6）；表中的是默认值。

## 1. 基本约定

- Base URL：`http://<host>:<port>`，业务接口前缀 `/api/v1`。
- 请求/响应：UTF-8 JSON，字段名 snake_case。
- 时间：UTC ISO8601，形如 `2026-11-12T08:00:00Z`。`updated_at` 仅内部使用，不出现在任何响应中。
- **响应头**：
  - 所有响应带 `Cache-Control: no-store`、`X-Content-Type-Options: nosniff`。
  - 带 JSON body 的响应带 `Content-Type: application/json; charset=utf-8`。
  - `204` **没有 body、没有 `Content-Type`**，但仍带上述两个安全头。
  - `401` 带 `WWW-Authenticate: Bearer`；`429` 带 `Retry-After: 3600`；需要关闭连接的错误带 `Connection: close`。
- **请求体**：上限 **8 KiB**；必须带**唯一**的 `Content-Length`（纯 ASCII 数字）；**不支持** `Transfer-Encoding: chunked`；短读/半关闭视为错误（不会落库）。
- 鉴权：`Authorization: Bearer <token>`。token 只在注册响应中返回一次，服务端只存哈希。
- 玩家 ID：`p_` + 16 位小写十六进制（8 字节随机）。短 ID 为玩家 ID 前 6 个字符（如 `p_3f9a`），**仅用于展示，不保证唯一**。
- 胜率 `win_rate`：`wins / games`，常规四舍五入保留 4 位小数（如 1/32 → `0.0313`）；`games == 0` 时为 `null`。
- PVE 与 PVP 分开计数，互不影响。

## 2. 数据口径（硬边界）

| 存 | 不存 |
|---|---|
| 玩家 ID（服务端生成） | 对局明细、时间线、回合数 |
| 昵称（可重名） | 伤害、扣血、治疗数值 |
| 创建/更新时间（更新时间仅内部） | 角色、曜彩骰使用情况 |
| PVE/PVP 的 `games`、`wins` | 胜率（查询时计算，不落库） |

任何新增统计字段都必须先经用户裁决并同步 `DESIGN.md`，不得由实现擅自扩展。

## 3. 错误格式

所有错误响应（包括未知 HTTP 方法、短读、重复头等协议错误）都是 JSON：

```json
{"error": {"code": "invalid_nickname", "message": "昵称长度必须为 1~24 个字符"}}
```

| HTTP | code | 含义 |
|---|---|---|
| 400 | `invalid_json` | 请求体不是合法 JSON、不是 JSON 对象、深嵌套/超大数字导致解析失败 |
| 400 | `invalid_body` | `Content-Length` 非法/重复、使用 chunked、请求体短读等传输格式错误 |
| 400 | `invalid_nickname` | 昵称不合法 |
| 400 | `invalid_mode` | `mode` 不是 `pve`/`pvp` |
| 400 | `invalid_result` | `result` 不是 `win`/`loss` |
| 400 | `invalid_event_id` | `event_id` 格式不合法 |
| 400 | `invalid_player_id` | 路径中的玩家 ID 格式不合法 |
| 400 | `missing_ids` | 批量查询缺少 `ids` 参数 |
| 400 | `too_many_ids` | 批量查询超过 50 个 ID |
| 400 | `length_required` | POST/PATCH 缺少 `Content-Length` |
| 401 | `unauthorized` | 缺少/无效的 Bearer token；或需要鉴权的接口中玩家不存在 |
| 404 | `not_found` | **仅**：`GET` 玩家不存在、未知路径、未知路径的任意方法 |
| 405 | `method_not_allowed` | 路径存在但方法不允许（带 `Allow` 头） |
| 413 | `payload_too_large` | 请求体超过 8 KiB |
| 429 | `rate_limited` | 触发限流（带 `Retry-After: 3600`） |
| 500 | `internal_error` | 服务端内部错误（不返回堆栈细节） |
| 503 | `db_unavailable` | 数据库不可用（仅 `/healthz`） |

**错误优先级**：需要鉴权的接口先校验 `Authorization`，再检查玩家是否存在与请求体；因此 `PATCH`/`DELETE`/`results` 对不存在的玩家返回 **401**，不会用 404 暴露 `player_id` 是否存在。公开接口先校验路径/ID/方法，再校验请求体。

## 4. 接口

### 4.1 注册 `POST /api/v1/players`

请求：

```json
{"nickname": "科大路人甲"}
```

- 昵称：字符串，strip 后 1~24 个 Unicode 码点；拒绝控制字符（`\x00-\x1f`、`\x7f`、`\u2028`、`\u2029`）与孤立代理项（`U+D800–U+DFFF`，无法 UTF-8 编码）；允许中文、emoji、重名。

响应 `201`：

```json
{
  "player_id": "p_3f9a1c2d4e5f6a7b",
  "short_id": "p_3f9a",
  "nickname": "科大路人甲",
  "token": "Vq3...43字符...",
  "created_at": "2026-11-12T08:00:00Z"
}
```

- `token` 仅此一次返回，请客户端立即保存；丢失只能重新注册。
- 限流：默认 20 次/小时/IP（`WARRIOR_STORE_REGISTER_PER_HOUR`，0 = 关闭）。**在解析请求体前计数**，非法请求也占额度。

```bash
curl -sS -X POST http://127.0.0.1:8080/api/v1/players \
  -H 'Content-Type: application/json' \
  -d '{"nickname":"科大路人甲"}'
```

### 4.2 查询玩家 `GET /api/v1/players/{player_id}`

公开接口，无需鉴权。响应 `200`：

```json
{
  "player_id": "p_3f9a1c2d4e5f6a7b",
  "short_id": "p_3f9a",
  "nickname": "科大路人甲",
  "created_at": "2026-11-12T08:00:00Z",
  "pve": {"games": 12, "wins": 7, "win_rate": 0.5833},
  "pvp": {"games": 0, "wins": 0, "win_rate": null}
}
```

不存在返回 `404 not_found`；ID 格式不合法返回 `400 invalid_player_id`。响应中永远不含 token/token 哈希。

```bash
curl -sS http://127.0.0.1:8080/api/v1/players/p_3f9a1c2d4e5f6a7b
```

### 4.3 批量查询 `GET /api/v1/players?ids=a,b,c`

- 最多 50 个 ID；返回顺序与请求顺序一致。
- **格式合法但不存在**的 ID 直接省略（不报错）；**格式非法**的 ID 仍返回 `400 invalid_player_id`。
- 重复 ID 按重复次数返回（同一玩家可能出现多次）。

```json
{"players": [{"player_id": "...", "short_id": "...", "nickname": "...", "created_at": "...",
              "pve": {"games": 1, "wins": 1, "win_rate": 1.0},
              "pvp": {"games": 0, "wins": 0, "win_rate": null}}]}
```

```bash
curl -sS 'http://127.0.0.1:8080/api/v1/players?ids=p_aaaa000000000000,p_bbbb111111111111'
```

### 4.4 改昵称 `PATCH /api/v1/players/{player_id}`

需要 Bearer token（必须是该玩家自己的 token）。请求：

```json
{"nickname": "新昵称"}
```

- 校验规则同注册；成功返回 `200` 与最新公开资料（同 4.2）。
- 昵称可重名，不做唯一性检查。
- 玩家不存在或 token 不匹配 → `401 unauthorized`（不区分，避免探测）。

```bash
curl -sS -X PATCH http://127.0.0.1:8080/api/v1/players/p_3f9a1c2d4e5f6a7b \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <token>' \
  -d '{"nickname":"新昵称"}'
```

### 4.5 上报一场 `POST /api/v1/players/{player_id}/results`

需要 Bearer token。请求：

```json
{"mode": "pve", "result": "win", "event_id": "a1b2c3d4e5"}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `mode` | 是 | `pve` 或 `pvp` |
| `result` | 是 | `win` 或 `loss` |
| `event_id` | 否 | 客户端生成的事件 ID（8~64 位 `[A-Za-z0-9_-]`）；用于网络重试去重 |

响应 `200`：

```json
{
  "pve": {"games": 13, "wins": 8, "win_rate": 0.6154},
  "pvp": {"games": 0, "wins": 0, "win_rate": null},
  "duplicate": false
}
```

- **非重复提交**：`games` +1；`wins` 仅在 `result == "win"` 时 +1。
- **相同 `player_id + event_id` 重复提交**：`duplicate: true`，**games/wins 都不变**，返回当前统计。
- 幂等记录每玩家保留最近 **2000 条**（写入时顺带清理更老的；默认 600 次/小时满速上报可覆盖约 3 小时，长于常见重试窗口）。
- 玩家不存在或 token 不匹配 → `401 unauthorized`。
- 限流：默认 600 次/小时/玩家（`WARRIOR_STORE_RESULTS_PER_HOUR`，0 = 关闭）。**在鉴权后、解析请求体前计数**，非法请求也占额度。

```bash
curl -sS -X POST http://127.0.0.1:8080/api/v1/players/p_3f9a1c2d4e5f6a7b/results \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <token>' \
  -d '{"mode":"pve","result":"win","event_id":"a1b2c3d4e5"}'
```

### 4.6 删除本人数据 `DELETE /api/v1/players/{player_id}`

需要 Bearer token。成功返回 `204 No Content`（无响应体、无 `Content-Type`，带 `Cache-Control: no-store` 与 `X-Content-Type-Options: nosniff`）。该玩家的资料、统计、幂等记录一并删除，token 立即失效。

- 玩家不存在或 token 不匹配 → `401 unauthorized`。
- 本接口用于隐私自助删除；**已有历史备份不会被删除**（备份中仍可能保留该玩家的 ID、昵称、token 哈希与统计），备份保留期策略仍待用户裁决（见 §7）。

```bash
curl -sS -X DELETE http://127.0.0.1:8080/api/v1/players/p_3f9a1c2d4e5f6a7b \
  -H 'Authorization: Bearer <token>' -i
```

### 4.7 健康检查 `GET /healthz`

公开接口，无版本前缀。响应 `200`：

```json
{"status": "ok", "version": "1.0.0", "db": "ok", "uptime_s": 123}
```

以下任一情况返回 `503` 与 `{"error":{"code":"db_unavailable","message":"数据库不可用"}}`：

- 数据库文件不存在/被删/打不开；
- `PRAGMA user_version != 1`；
- `players` / `stats` / `result_events` 任一表缺失；
- 磁盘满/权限错误等 SQLite 异常。

```bash
curl -sS http://127.0.0.1:8080/healthz
```

### 4.8 HTTP 方法限制

- 已知路径使用未定义的方法（如 `PUT /api/v1/players`）→ `405 method_not_allowed` + `Allow` 头，JSON 错误体。
- 未知路径的任意方法 → `404 not_found`，JSON 错误体。
- 不支持 `HEAD`（也返回 405 JSON，只是不发送 body）；健康检查请用 `GET`。

## 5. 鉴权

- 注册时服务端生成 32 字节随机 token（`secrets.token_urlsafe(32)`，43 字符）。
- 服务端只保存 `SHA-256(token)`（配置 `WARRIOR_STORE_PEPPER` 时改为 `HMAC-SHA256(pepper, token)`），比较使用常数时间算法。
- token 即密码：客户端必须安全保存；日志与响应中不会再次出现。访问日志会记录 path（含 query），因此不要把 token 放在 URL 查询参数里。
- 多个 `Authorization` 头会被拒绝（`401`），避免不同代理/后端取值不一致。
- 无效/缺失 token 一律 `401 unauthorized`，不区分「玩家不存在」与「token 不匹配」，避免探测。
- 设置过 `WARRIOR_STORE_PEPPER` 后不可更改，否则所有已发 token 立即失效。

## 6. 限流与并发

- 注册：默认 20 次/小时/IP（`WARRIOR_STORE_REGISTER_PER_HOUR`）；上报：默认 600 次/小时/玩家（`WARRIOR_STORE_RESULTS_PER_HOUR`）；两者设 `0` 关闭。
- 固定窗口计数保存在内存，进程重启清零；多实例部署时不共享（当前单实例部署）。
- 注册在解析 body 前计数；上报在鉴权后、解析 body 前计数；失败/非法请求也占额度。
- 429 响应带 `Retry-After: 3600`（与 1 小时窗口一致）。
- 存储为 SQLite（WAL）：读并发、写串行；写事务使用 `BEGIN IMMEDIATE` + `busy_timeout=5000`，应用层有限重试；批量查询在同一读快照内完成。

## 7. 已知限制与待裁决事项

- **自报战绩**：v1 由客户端上报自己的胜负，服务端没有对局权威校验，恶意客户端可以虚增自己的统计；PVP 双方各自上报各自一场，不做互证。反作弊/互证方案待裁决。
- **排行榜**：当前不提供。排行榜口径待用户裁决。
- **公网入口/域名/HTTPS**：当前默认只监听 `127.0.0.1`。公网部署需另行决定，并建议前置 nginx 终结 TLS（README 给示例，默认不依赖）。
- **隐私与保留期**：保留期策略待用户裁决；当前提供 `DELETE` 自助删除。**DELETE 不会删除历史备份**，备份中的副本会随备份保留期到期而淘汰。
- **数据库升级**：当前 schema `user_version = 1`；后续变更需先更新本文并提供迁移步骤。程序遇到更高版本或缺少迁移步骤的旧版本会 fail-fast（启动失败，不会静默运行）。
- **多实例**：不支持；SQLite 单写、限流计数在进程内存。扩容前需改存储与限流方案。
- **昵称字符集**：只拒绝控制字符、行/段分隔符与孤立代理项；RTL/零宽等格式字符未额外禁止（如需更严格需先改契约）。
- **客户端**：Godot 客户端尚未接入；本服务不提供 SDK。

## 8. 版本

- 服务版本：`1.0.0`（`/healthz` 返回）。
- 接口版本：`/api/v1`。破坏性变更必须升 `/api/v2`，不得静默修改 v1 语义。
- 变更记录见 `server/README.md` §10.5 与 `DESIGN.md` §10。
