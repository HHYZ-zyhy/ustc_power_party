#!/usr/bin/env bash
# 科大战力党玩家数据存储服务 —— Ubuntu 24.04 安装脚本
#
# 用法（必须 root）：
#   sudo bash deploy/install-ubuntu.sh
#
# 脚本只做本机安装：暂存复制代码 → 检查导入/语法 → 创建系统用户
# → 安装环境变量文件与 systemd 单元 → 换入新代码 → daemon-reload
# → 启用并启动服务与备份定时器 → 确认服务处于 active。
# 不联网、不写密码、不删除已有数据库；已存在的 /etc/warrior-store.env 保留内容，
# 只把属主/权限重置为 root:root 0640。
set -euo pipefail

INSTALL_DIR="/opt/warrior-store"
ENV_FILE="/etc/warrior-store.env"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_USER="warrior-store"
SERVICE_UNIT="warrior-store.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "错误：请用 root 运行，例如：sudo bash deploy/install-ubuntu.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$1"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -f -- "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

SRC_REAL="$(resolve_path "${SRC_ROOT}")"
INSTALL_REAL="$(resolve_path "${INSTALL_DIR}")"

echo "源目录：${SRC_REAL}"
echo "安装目录：${INSTALL_REAL}"

# 源目录保护：绝不能在安装目录里“复制自身再删除旧目录”，否则会清空源码。
if [[ "${SRC_REAL}" == "${INSTALL_REAL}" ]]; then
  echo "错误：检测到正在从安装目录自身（${INSTALL_REAL}）运行安装脚本。" >&2
  echo "      脚本会替换 app/ 与 deploy/，从安装目录运行会破坏源码。" >&2
  echo "      请从源码 checkout（例如 git clone 后的 server/ 目录）运行：" >&2
  echo "      sudo bash <源码目录>/deploy/install-ubuntu.sh" >&2
  exit 1
fi

# ---------- 前置检查（不联网、不装包） ----------
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：找不到 python3。Ubuntu 24.04 应自带，请先安装 python3。" >&2
  exit 1
fi
if ! python3 -c 'import sqlite3' >/dev/null 2>&1; then
  echo "错误：python3 缺少 sqlite3 模块（Ubuntu 上通常由 python3 包自带）。" >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "错误：找不到 systemctl，本脚本只适用于 systemd 系统（Ubuntu 24.04）。" >&2
  exit 1
fi

for required in \
  "${SRC_ROOT}/app/__init__.py" \
  "${SRC_ROOT}/app/__main__.py" \
  "${SRC_ROOT}/app/main.py" \
  "${SRC_ROOT}/app/http_api.py" \
  "${SRC_ROOT}/app/ratelimit.py" \
  "${SRC_ROOT}/app/db.py" \
  "${SRC_ROOT}/app/config.py" \
  "${SRC_ROOT}/app/validation.py" \
  "${SRC_ROOT}/app/auth.py" \
  "${SRC_ROOT}/app/errors.py" \
  "${SRC_ROOT}/app/log.py" \
  "${SCRIPT_DIR}/warrior-store.service" \
  "${SCRIPT_DIR}/warrior-store-backup.service" \
  "${SCRIPT_DIR}/warrior-store-backup.timer" \
  "${SCRIPT_DIR}/warrior-store.env.example" \
  "${SCRIPT_DIR}/backup.py" \
  "${SCRIPT_DIR}/restore.py"
do
  if [[ ! -f "${required}" ]]; then
    echo "错误：缺少安装所需文件：${required}" >&2
    echo "      请在完整的 server/ 目录中运行本脚本。" >&2
    exit 1
  fi
done

# ---------- 暂存复制（不先删除现有 app/deploy） ----------
install -d -o root -g root -m 0755 "${INSTALL_DIR}"

STAGING="${INSTALL_DIR}/.staging"
OLD_APP="${INSTALL_DIR}/.old-app.$$"
OLD_DEPLOY="${INSTALL_DIR}/.old-deploy.$$"

cleanup_staging() {
  rm -rf -- "${STAGING}"
}
trap cleanup_staging EXIT

rm -rf -- "${STAGING}"
install -d -o root -g root -m 0700 "${STAGING}"
cp -a -- "${SRC_ROOT}/app" "${STAGING}/app"
cp -a -- "${SCRIPT_DIR}" "${STAGING}/deploy"
chown -R root:root "${STAGING}/app" "${STAGING}/deploy"
chmod -R u=rwX,go=rX "${STAGING}/app" "${STAGING}/deploy"
echo "已暂存复制 app/ 与 deploy/ 到 ${STAGING}（属主 root:root）。"

# 在 staging 内做导入/语法检查：失败时现有 app/deploy 完全不动，旧服务不受影响。
if ! (cd "${STAGING}" && env -u PYTHONPATH PYTHONDONTWRITEBYTECODE=1 python3 -c 'import app.main'); then
  echo "错误：暂存代码无法导入，已中止（现有安装与旧服务未改动）。" >&2
  echo "  请检查是否复制完整，或手动运行：cd ${STAGING} && python3 -c 'import app.main'" >&2
  exit 1
fi

if ! env -u PYTHONPATH PYTHONDONTWRITEBYTECODE=1 python3 - "${STAGING}" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
failed: list[str] = []
for sub in ("app", "deploy"):
    for path in sorted((root / sub).glob("*.py")):
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except (SyntaxError, UnicodeDecodeError) as exc:
            failed.append(f"{path}: {exc}")
if failed:
    print("语法检查失败：", file=sys.stderr)
    print("\n".join(failed), file=sys.stderr)
    sys.exit(1)
PY
then
  echo "错误：暂存代码存在语法错误，已中止（现有安装与旧服务未改动）。" >&2
  exit 1
fi
echo "暂存代码导入与语法检查通过。"

# ---------- 系统用户 ----------
if id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  echo "系统用户 ${SERVICE_USER} 已存在，跳过创建。"
else
  useradd --system --home "${INSTALL_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}"
  echo "已创建系统用户 ${SERVICE_USER}（不可登录、无密码）。"
fi

# systemd 单元使用 Group=warrior-store；确保同名用户组一定存在。
if ! getent group "${SERVICE_USER}" >/dev/null 2>&1; then
  groupadd --system "${SERVICE_USER}"
  usermod --gid "${SERVICE_USER}" "${SERVICE_USER}"
  echo "已补建用户组 ${SERVICE_USER} 并设为该用户的主组。"
fi

# ---------- 环境变量文件 ----------
if [[ -f "${ENV_FILE}" ]]; then
  chown root:root "${ENV_FILE}"
  chmod 0640 "${ENV_FILE}"
  echo "已存在 ${ENV_FILE}，保留原内容不覆盖（属主/权限已重置为 root:root 0640）。"
  if ! grep -Eq '^[[:space:]]*WARRIOR_STORE_DB=/' "${ENV_FILE}"; then
    echo "警告：${ENV_FILE} 中未找到以 / 开头的 WARRIOR_STORE_DB= 绝对路径行。" >&2
    echo "      服务可能使用默认数据库路径；如非预期，请编辑该文件后执行：" >&2
    echo "      sudo systemctl restart warrior-store" >&2
  fi
  echo "  如需调整监听地址/端口/数据库路径，请编辑该文件后执行："
  echo "  sudo systemctl restart warrior-store"
else
  install -o root -g root -m 0640 "${SCRIPT_DIR}/warrior-store.env.example" "${ENV_FILE}"
  echo "已创建 ${ENV_FILE}（root:root，0640）。"
  echo "  建议首次启动前检查其中的监听地址与 WARRIOR_STORE_PEPPER。"
fi

# ---------- 换入新代码（失败自动还原旧目录） ----------
had_app=0
had_deploy=0
rm -rf -- "${OLD_APP}" "${OLD_DEPLOY}"

if [[ -e "${INSTALL_DIR}/app" ]]; then
  mv -- "${INSTALL_DIR}/app" "${OLD_APP}"
  had_app=1
fi
if [[ -e "${INSTALL_DIR}/deploy" ]]; then
  mv -- "${INSTALL_DIR}/deploy" "${OLD_DEPLOY}"
  had_deploy=1
fi

rollback_swap() {
  rm -rf -- "${INSTALL_DIR}/app" "${INSTALL_DIR}/deploy"
  if [[ "${had_app}" -eq 1 ]]; then
    mv -- "${OLD_APP}" "${INSTALL_DIR}/app"
  fi
  if [[ "${had_deploy}" -eq 1 ]]; then
    mv -- "${OLD_DEPLOY}" "${INSTALL_DIR}/deploy"
  fi
}

if ! mv -- "${STAGING}/app" "${INSTALL_DIR}/app"; then
  echo "错误：换入新 app/ 失败，正在还原旧版本。" >&2
  rollback_swap
  exit 1
fi
if ! mv -- "${STAGING}/deploy" "${INSTALL_DIR}/deploy"; then
  echo "错误：换入新 deploy/ 失败，正在还原旧版本。" >&2
  rollback_swap
  exit 1
fi
echo "已换入新 app/ 与 deploy/。"

# ---------- systemd 单元 ----------
for unit in warrior-store.service warrior-store-backup.service warrior-store-backup.timer; do
  install -o root -g root -m 0644 "${SCRIPT_DIR}/${unit}" "${SYSTEMD_DIR}/${unit}"
done
echo "已安装 systemd 单元到 ${SYSTEMD_DIR}。"

systemctl daemon-reload

was_active=0
if systemctl is-active --quiet "${SERVICE_UNIT}"; then
  was_active=1
fi

if ! systemctl enable --now "${SERVICE_UNIT}" warrior-store-backup.timer; then
  echo "错误：服务或定时器启动失败。请查看：" >&2
  echo "  sudo journalctl -u warrior-store -n 50 --no-pager" >&2
  exit 1
fi

# 重新安装（升级）时让新代码立即生效；首次安装时 enable --now 已启动新代码。
if [[ "${was_active}" -eq 1 ]]; then
  systemctl restart "${SERVICE_UNIT}"
  echo "检测到服务原本在运行，已重启以加载新代码。"
fi

# 启动后确认：给进程一点时间绑定端口/初始化数据库，再检查 active。
sleep 2
if ! systemctl is-active --quiet "${SERVICE_UNIT}"; then
  echo "错误：warrior-store 服务启动后未处于 active 状态。" >&2
  echo "  请查看最近日志：sudo journalctl -u warrior-store -n 50 --no-pager" >&2
  echo "  最近 50 行日志：" >&2
  journalctl -u warrior-store -n 50 --no-pager >&2 || true
  echo "  旧版本备份保留在：${OLD_APP} / ${OLD_DEPLOY}" >&2
  echo "  如确认新版本不可用，可手动把上述目录改回 app/ 与 deploy/ 后重启。" >&2
  exit 1
fi
echo "服务确认处于 active 状态。"

# 启动成功后才清理旧版本与暂存目录。
rm -rf -- "${STAGING}" "${OLD_APP}" "${OLD_DEPLOY}"

cat <<EOF

安装完成。数据库目录（systemd StateDirectory）：/var/lib/warrior-store
默认数据库文件：/var/lib/warrior-store/store.sqlite3
配置文件：${ENV_FILE}（修改后执行 sudo systemctl restart warrior-store）

后续检查命令：
  sudo systemctl status warrior-store --no-pager
  sudo journalctl -u warrior-store -f
  curl -sS http://127.0.0.1:8080/healthz

备份定时器：
  systemctl list-timers warrior-store-backup.timer
  sudo systemctl start warrior-store-backup.service    # 手动立即备份一次
  sudo journalctl -u warrior-store-backup -n 50 --no-pager

如需局域网/公网访问，请先阅读 server/README.md §5 的安全警告再改监听地址。
EOF
