#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FEED_OPENSEARCH_CONFIG:-${SERVICE_DIR}/config.env}"
COMPOSE_FILE="${SERVICE_DIR}/docker/opensearch/docker-compose.yml"
VENV_DIR="${FEED_OPENSEARCH_VENV:-${SERVICE_DIR}/venv}"
REQUIREMENTS_FILE="${SERVICE_DIR}/requirements.txt"
INDEXER_SCHEMA_FILE="${SERVICE_DIR}/sql/indexer/schema_mysql.sql"
SYSTEMD_WORKER_TEMPLATE="${FEED_OPENSEARCH_WORKER_TEMPLATE:-pa-feed-opensearch-worker@.service}"
SYSTEMD_REAPER_TEMPLATE="${FEED_OPENSEARCH_REAPER_TEMPLATE:-pa-feed-opensearch-reaper@.service}"
LEGACY_SYSTEMD_WORKER_SERVICE="${FEED_OPENSEARCH_WORKER_SERVICE:-pa-feed-opensearch-worker.service}"
LEGACY_SYSTEMD_REAPER_SERVICE="${FEED_OPENSEARCH_REAPER_SERVICE:-pa-feed-opensearch-reaper.service}"
SYSTEMD_DIR="${FEED_OPENSEARCH_SYSTEMD_DIR:-/etc/systemd/system}"
LOGROTATE_FILE="${FEED_OPENSEARCH_LOGROTATE_FILE:-/etc/logrotate.d/pa-feed-opensearch-indexer}"

if [[ -f "${CONFIG_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  set +a
fi

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if [[ -x "${VENV_DIR}/bin/python" ]]; then
    PYTHON_BIN="${VENV_DIR}/bin/python"
  else
    PYTHON_BIN="python3"
  fi
fi

DB_ENGINE="${DB_ENGINE:-mysql}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-pa_indexer}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-Pa_Indexer_2026!ChangeMe}"
MYSQL_DATABASE="${MYSQL_DATABASE:-pa_opensearch_indexer}"
MYSQL_APP_HOST="${MYSQL_APP_HOST:-localhost}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQL_ADMIN_BIN="${MYSQL_ADMIN_BIN:-sudo}"
MYSQL_ADMIN_ARGS="${MYSQL_ADMIN_ARGS:-mysql}"
SERVICE_USER="${SERVICE_USER:-pa_indexer}"
SERVICE_GROUP="${SERVICE_GROUP:-${SERVICE_USER}}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-logs/pa_opensearch_indexer.log}"
DAEMON_BATCH_SIZE="${DAEMON_BATCH_SIZE:-100}"
DAEMON_CLAIM_STRATEGY="${DAEMON_CLAIM_STRATEGY:-simple}"
REAPER_STALE_SECONDS="${REAPER_STALE_SECONDS:-600}"
WORKER_COUNT="${WORKER_COUNT:-1}"
REAPER_COUNT="${REAPER_COUNT:-1}"

cd "${SERVICE_DIR}"

log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_timestamp)" "$*"
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_timestamp)" "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  ./feed_opensearch_ctl.sh <command>

Install / Configure:
  doctor                Check OS, commands, config, venv, Docker, and systemd units
  install-deps          Install base OS dependencies on Ubuntu/Debian or CentOS/RHEL
  setup-venv            Create/update Python venv and install requirements.txt
  init-config           Create config.env from config.example.env if missing
  configure             Interactively write config.env
  db:install            Interactively create/reset MySQL database, user, grants, and schema
  db:uninstall          Interactively drop MySQL schema, database, and/or user
  db:schema             Interactively create/reset only indexer schema relations
  db:status             Check app MySQL login and indexer schema visibility
  show-db-sql           Print admin SQL for database, user, and grants
  install-service-user  Create the dedicated Linux service user/group
  fix-permissions       Apply service-user ownership and private config permissions
  install-systemd       Install and enable worker/reaper systemd services
  uninstall             Interactively uninstall systemd/logrotate/db/user pieces
  uninstall-systemd     Disable and remove worker/reaper systemd services
  show-systemd          Print generated systemd service files
  install-logrotate     Install logrotate rule for LOG_FILE directory
  uninstall-logrotate   Remove managed logrotate rule
  show-logrotate        Print active or generated logrotate rule

OpenSearch:
  opensearch:start      Start the local OpenSearch Docker container
  opensearch:stop       Stop the local OpenSearch Docker container
  opensearch:restart    Restart the local OpenSearch Docker container
  opensearch:status     Show OpenSearch container status
  opensearch:logs       Follow OpenSearch logs

Indexer:
  worker:run            Run the indexing worker in the foreground
  reaper:run            Run stale job ownership recovery in the foreground
  worker:start          Start worker systemd service
  worker:stop           Stop worker systemd service
  worker:restart        Restart worker systemd service
  worker:status         Show configured worker systemd instance status
  worker:logs           Show worker systemd journal logs
  reaper:start          Start reaper systemd service
  reaper:stop           Stop reaper systemd service
  reaper:restart        Restart reaper systemd service
  reaper:status         Show configured reaper systemd instance status
  reaper:logs           Show reaper systemd journal logs
  services:start        Start worker and reaper services
  services:stop         Stop worker and reaper services
  services:restart      Restart worker and reaper services
  services:status       Show worker and reaper service status
  services:logs         Show worker and reaper systemd journal logs

Project:
  config                Print resolved project paths and command settings
  help                  Show this help

Configuration:
  ./feed_opensearch_ctl.sh init-config
  ./feed_opensearch_ctl.sh configure
  Set FEED_OPENSEARCH_CONFIG=/path/to/config.env to load a different config file.
USAGE
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

mysql_admin() {
  local args=()

  if [[ -n "${MYSQL_ADMIN_ARGS}" ]]; then
    # MYSQL_ADMIN_ARGS intentionally supports values like: -u root -p
    # shellcheck disable=SC2206
    args=(${MYSQL_ADMIN_ARGS})
  fi

  "${MYSQL_ADMIN_BIN}" "${args[@]}" "$@"
}

mysql_app() {
  MYSQL_PWD="${MYSQL_PASSWORD}" "${MYSQL_BIN}" \
    -h "${MYSQL_HOST}" \
    -P "${MYSQL_PORT}" \
    -u "${MYSQL_USER}" \
    "$@"
}

sql_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\'\'}"
  printf "'%s'" "${value}"
}

sql_ident() {
  local value="$1"

  if [[ ! "${value}" =~ ^[A-Za-z0-9_]+$ ]]; then
    log_error "Unsafe MySQL identifier: ${value}"
    log_error "Use only letters, numbers, and underscores for MYSQL_DATABASE."
    exit 1
  fi

  printf '`%s`' "${value}"
}

validate_mysql_account_part() {
  local name="$1"
  local value="$2"

  if [[ -z "${value}" || "${value}" == *"'"* || "${value}" == *"\\"* ]]; then
    log_error "Unsafe ${name}: ${value}"
    log_error "Avoid quotes and backslashes in MySQL user/host settings."
    exit 1
  fi
}

require_mysql_client() {
  if ! command_exists "${MYSQL_BIN}"; then
    log_error "Missing MySQL client command: ${MYSQL_BIN}"
    exit 1
  fi

  if ! command_exists "${MYSQL_ADMIN_BIN}"; then
    log_error "Missing MySQL admin command: ${MYSQL_ADMIN_BIN}"
    exit 1
  fi
}

require_schema_file() {
  if [[ ! -f "${INDEXER_SCHEMA_FILE}" ]]; then
    log_error "Missing indexer schema file: ${INDEXER_SCHEMA_FILE}"
    exit 1
  fi
}

as_root_write_file() {
  local target="$1"
  local mode="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  cat > "${tmp_file}"

  if [[ "$(id -u)" -eq 0 ]]; then
    install -m "${mode}" "${tmp_file}" "${target}"
  else
    sudo install -m "${mode}" "${tmp_file}" "${target}"
  fi

  rm -f "${tmp_file}"
}

as_root_remove_file() {
  local target="$1"

  if [[ "$(id -u)" -eq 0 ]]; then
    rm -f "${target}"
  else
    sudo rm -f "${target}"
  fi
}

run_systemctl() {
  if [[ "$(id -u)" -eq 0 ]]; then
    systemctl "$@"
  else
    sudo systemctl "$@"
  fi
}

detect_os_family() {
  local id=""
  local id_like=""

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  case "${id} ${id_like}" in
    *debian*|*ubuntu*) printf '%s\n' debian ;;
    *rhel*|*centos*|*fedora*) printf '%s\n' rhel ;;
    *) printf '%s\n' unknown ;;
  esac
}

package_manager() {
  if command_exists apt-get; then
    printf '%s\n' apt-get
  elif command_exists dnf; then
    printf '%s\n' dnf
  elif command_exists yum; then
    printf '%s\n' yum
  else
    printf '%s\n' unknown
  fi
}

install_deps() {
  local pm
  pm="$(package_manager)"

  case "${pm}" in
    apt-get)
      log_info "Installing base dependencies with apt-get."
      if [[ "$(id -u)" -eq 0 ]]; then
        apt-get update
        apt-get install -y python3 python3-venv python3-pip curl ca-certificates docker.io docker-compose-plugin logrotate
      else
        sudo apt-get update
        sudo apt-get install -y python3 python3-venv python3-pip curl ca-certificates docker.io docker-compose-plugin logrotate
      fi
      ;;
    dnf|yum)
      log_info "Installing base dependencies with ${pm}."
      if [[ "$(id -u)" -eq 0 ]]; then
        "${pm}" install -y python3 python3-pip curl ca-certificates logrotate
      else
        sudo "${pm}" install -y python3 python3-pip curl ca-certificates logrotate
      fi
      log_info "MySQL is treated as an external prerequisite; doctor will report mysql client status."
      log_info "Docker/OpenSearch packaging differs across CentOS/RHEL installations; doctor will report Docker status."
      ;;
    *)
      log_error "No supported package manager found. Install python3, venv/pip, curl, ca-certificates, logrotate, and Docker manually. MySQL is an external prerequisite."
      exit 1
      ;;
  esac
}

setup_venv() {
  if ! command_exists python3; then
    log_error "python3 is missing. Run install-deps first."
    exit 1
  fi

  if [[ ! -f "${REQUIREMENTS_FILE}" ]]; then
    log_error "Missing requirements file: ${REQUIREMENTS_FILE}"
    exit 1
  fi

  log_info "Creating/updating Python venv: ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/python" -m pip install --upgrade pip
  "${VENV_DIR}/bin/python" -m pip install -r "${REQUIREMENTS_FILE}"
}

init_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    log_info "Config already exists: ${CONFIG_FILE}"
    return
  fi

  if [[ ! -f "${SERVICE_DIR}/config.example.env" ]]; then
    log_error "Missing config example: ${SERVICE_DIR}/config.example.env"
    exit 1
  fi

  cp "${SERVICE_DIR}/config.example.env" "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}"
  log_info "Created config: ${CONFIG_FILE}"
  log_info "Edit it directly or run: ./feed_opensearch_ctl.sh configure"
}

prompt_value() {
  local name="$1"
  local default_value="$2"
  local value

  read -r -p "${name} [${default_value}]: " value
  printf '%s\n' "${value:-${default_value}}"
}

shell_quote() {
  printf '%q' "$1"
}

configure() {
  local mysql_password
  local log_file
  local python_bin

  log_info "Writing interactive config: ${CONFIG_FILE}"

  DB_ENGINE="$(prompt_value DB_ENGINE "${DB_ENGINE}")"
  MYSQL_HOST="$(prompt_value MYSQL_HOST "${MYSQL_HOST}")"
  MYSQL_PORT="$(prompt_value MYSQL_PORT "${MYSQL_PORT}")"
  MYSQL_USER="$(prompt_value MYSQL_USER "${MYSQL_USER}")"
  MYSQL_DATABASE="$(prompt_value MYSQL_DATABASE "${MYSQL_DATABASE}")"
  MYSQL_APP_HOST="$(prompt_value MYSQL_APP_HOST "${MYSQL_APP_HOST}")"
  MYSQL_BIN="$(prompt_value MYSQL_BIN "${MYSQL_BIN}")"
  MYSQL_ADMIN_BIN="$(prompt_value MYSQL_ADMIN_BIN "${MYSQL_ADMIN_BIN}")"
  MYSQL_ADMIN_ARGS="$(prompt_value MYSQL_ADMIN_ARGS "${MYSQL_ADMIN_ARGS}")"
  SERVICE_USER="$(prompt_value SERVICE_USER "${SERVICE_USER}")"
  SERVICE_GROUP="$(prompt_value SERVICE_GROUP "${SERVICE_GROUP}")"
  read -r -s -p "MYSQL_PASSWORD [leave blank to keep current]: " mysql_password
  printf '\n'
  if [[ -z "${mysql_password}" ]]; then
    mysql_password="${MYSQL_PASSWORD}"
  fi
  log_file="$(prompt_value LOG_FILE "${LOG_FILE}")"
  python_bin="$(prompt_value PYTHON_BIN "${VENV_DIR}/bin/python")"
  DAEMON_BATCH_SIZE="$(prompt_value DAEMON_BATCH_SIZE "${DAEMON_BATCH_SIZE}")"
  DAEMON_CLAIM_STRATEGY="$(prompt_value DAEMON_CLAIM_STRATEGY "${DAEMON_CLAIM_STRATEGY}")"
  REAPER_STALE_SECONDS="$(prompt_value REAPER_STALE_SECONDS "${REAPER_STALE_SECONDS}")"
  WORKER_COUNT="$(prompt_value WORKER_COUNT "${WORKER_COUNT}")"
  REAPER_COUNT="$(prompt_value REAPER_COUNT "${REAPER_COUNT}")"

  umask 077
  cat > "${CONFIG_FILE}" <<EOF
# Feed OpenSearch indexer configuration.
DB_ENGINE=$(shell_quote "${DB_ENGINE}")
MYSQL_HOST=$(shell_quote "${MYSQL_HOST}")
MYSQL_PORT=$(shell_quote "${MYSQL_PORT}")
MYSQL_USER=$(shell_quote "${MYSQL_USER}")
MYSQL_PASSWORD=$(shell_quote "${mysql_password}")
MYSQL_DATABASE=$(shell_quote "${MYSQL_DATABASE}")
MYSQL_APP_HOST=$(shell_quote "${MYSQL_APP_HOST}")
MYSQL_BIN=$(shell_quote "${MYSQL_BIN}")
MYSQL_ADMIN_BIN=$(shell_quote "${MYSQL_ADMIN_BIN}")
MYSQL_ADMIN_ARGS=$(shell_quote "${MYSQL_ADMIN_ARGS}")
SERVICE_USER=$(shell_quote "${SERVICE_USER}")
SERVICE_GROUP=$(shell_quote "${SERVICE_GROUP}")

PYTHON_BIN=$(shell_quote "${python_bin}")
LOG_LEVEL=$(shell_quote "${LOG_LEVEL}")
LOG_FILE=$(shell_quote "${log_file}")

DAEMON_POLL_INTERVAL_SECONDS=2
DAEMON_BATCH_DELAY_SECONDS=0
DAEMON_BATCH_SIZE=${DAEMON_BATCH_SIZE}
DAEMON_CLAIM_STRATEGY=$(shell_quote "${DAEMON_CLAIM_STRATEGY}")
DAEMON_RETRY_DELAY_SECONDS=0

DB_RETRY_ATTEMPTS=3
DB_RETRY_BASE_DELAY_SECONDS=0.1
DB_RETRY_MAX_DELAY_SECONDS=2

REAPER_POLL_INTERVAL_SECONDS=60
REAPER_BATCH_DELAY_SECONDS=0.5
REAPER_BATCH_SIZE=1000
REAPER_STALE_SECONDS=${REAPER_STALE_SECONDS}
REAPER_RELEASE_DELAY_SECONDS=600

WORKER_COUNT=${WORKER_COUNT}
REAPER_COUNT=${REAPER_COUNT}
EOF
  log_info "Wrote config: ${CONFIG_FILE}"
}

service_owner() {
  printf '%s\n' "${SERVICE_USER}"
}

service_group() {
  printf '%s\n' "${SERVICE_GROUP}"
}

install_service_user() {
  local create_home_flag="--no-create-home"
  local shell_path="/sbin/nologin"

  if ! command_exists getent; then
    log_error "Missing command: getent"
    exit 1
  fi

  if ! getent group "${SERVICE_GROUP}" >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      groupadd --system "${SERVICE_GROUP}"
    else
      sudo groupadd --system "${SERVICE_GROUP}"
    fi
    log_info "Created service group: ${SERVICE_GROUP}"
  fi

  if [[ ! -x "${shell_path}" ]]; then
    shell_path="/usr/sbin/nologin"
  fi

  if ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      useradd --system "${create_home_flag}" --gid "${SERVICE_GROUP}" --home-dir "${SERVICE_DIR}" --shell "${shell_path}" "${SERVICE_USER}"
    else
      sudo useradd --system "${create_home_flag}" --gid "${SERVICE_GROUP}" --home-dir "${SERVICE_DIR}" --shell "${shell_path}" "${SERVICE_USER}"
    fi
    log_info "Created service user: ${SERVICE_USER}"
  else
    log_info "Service user already exists: ${SERVICE_USER}"
  fi
}

fix_permissions() {
  local log_dir
  log_dir="$(service_log_dir)"

  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "${log_dir}"
    chgrp -R "${SERVICE_GROUP}" "${SERVICE_DIR}"
    chmod -R g+rX,o-rwx "${SERVICE_DIR}"
    chmod 750 "${SERVICE_DIR}"
    chmod 750 "${SERVICE_DIR}/feed_opensearch_ctl.sh"
    [[ -f "${CONFIG_FILE}" ]] && chmod 640 "${CONFIG_FILE}"
    chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${log_dir}"
    chmod 750 "${log_dir}"
  else
    sudo mkdir -p "${log_dir}"
    sudo chgrp -R "${SERVICE_GROUP}" "${SERVICE_DIR}"
    sudo chmod -R g+rX,o-rwx "${SERVICE_DIR}"
    sudo chmod 750 "${SERVICE_DIR}"
    sudo chmod 750 "${SERVICE_DIR}/feed_opensearch_ctl.sh"
    [[ -f "${CONFIG_FILE}" ]] && sudo chmod 640 "${CONFIG_FILE}"
    sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${log_dir}"
    sudo chmod 750 "${log_dir}"
  fi

  log_info "Applied service read permissions for ${SERVICE_GROUP} under ${SERVICE_DIR}"
  log_info "Applied service write ownership for ${SERVICE_USER}:${SERVICE_GROUP} under ${log_dir}"
}

uninstall_service_user() {
  if ! command_exists getent; then
    log_error "Missing command: getent"
    exit 1
  fi

  if getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      userdel "${SERVICE_USER}"
    else
      sudo userdel "${SERVICE_USER}"
    fi
    log_info "Removed service user: ${SERVICE_USER}"
  else
    log_info "Service user does not exist: ${SERVICE_USER}"
  fi

  if getent group "${SERVICE_GROUP}" >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      groupdel "${SERVICE_GROUP}" || log_info "Service group still in use: ${SERVICE_GROUP}"
    else
      sudo groupdel "${SERVICE_GROUP}" || log_info "Service group still in use: ${SERVICE_GROUP}"
    fi
  else
    log_info "Service group does not exist: ${SERVICE_GROUP}"
  fi
}


positive_int() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

validate_positive_int() {
  local name="$1"
  local value="$2"

  if ! positive_int "${value}"; then
    log_error "Invalid ${name}: expected positive integer, got '${value}'."
    exit 1
  fi
}

validate_instance_counts() {
  validate_positive_int WORKER_COUNT "${WORKER_COUNT}"
  validate_positive_int REAPER_COUNT "${REAPER_COUNT}"
}

worker_template_unit() {
  printf '%s\n' "${SYSTEMD_WORKER_TEMPLATE}"
}

reaper_template_unit() {
  printf '%s\n' "${SYSTEMD_REAPER_TEMPLATE}"
}

worker_instance_unit() {
  local instance="$1"
  printf 'pa-feed-opensearch-worker@%s.service\n' "${instance}"
}

reaper_instance_unit() {
  local instance="$1"
  printf 'pa-feed-opensearch-reaper@%s.service\n' "${instance}"
}

systemd_template_content() {
  local command_name="$1"
  local description="$2"
  local owner
  local group

  owner="$(service_owner)"
  group="$(service_group)"

  cat <<EOF
[Unit]
Description=${description} %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${owner}
Group=${group}
WorkingDirectory=${SERVICE_DIR}
Environment=FEED_OPENSEARCH_CONFIG=${CONFIG_FILE}
Environment=FEED_OPENSEARCH_INSTANCE=%i
ExecStart=${SERVICE_DIR}/feed_opensearch_ctl.sh ${command_name}
Restart=always
RestartSec=5
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF
}

for_worker_instances() {
  local action="$1"
  local i

  validate_instance_counts
  for (( i = 1; i <= WORKER_COUNT; i++ )); do
    "${action}" "$(worker_instance_unit "${i}")"
  done
}

for_reaper_instances() {
  local action="$1"
  local i

  validate_instance_counts
  for (( i = 1; i <= REAPER_COUNT; i++ )); do
    "${action}" "$(reaper_instance_unit "${i}")"
  done
}

systemctl_start_unit() {
  run_systemctl start "$1"
}

systemctl_stop_unit() {
  run_systemctl stop "$1"
}

systemctl_restart_unit() {
  run_systemctl restart "$1"
}

systemctl_enable_unit() {
  run_systemctl enable "$1"
}

systemctl_disable_now_unit() {
  run_systemctl disable --now "$1" || true
}

systemctl_status_unit() {
  run_systemctl status "$1" || true
}

journal_unit() {
  if [[ "$(id -u)" -eq 0 ]]; then
    journalctl -u "$1" -n "${JOURNAL_LINES:-100}" --no-pager
  else
    sudo journalctl -u "$1" -n "${JOURNAL_LINES:-100}" --no-pager
  fi
}

journal_unit_action() {
  journal_unit "$1"
}

legacy_disable_remove() {
  run_systemctl disable --now "${LEGACY_SYSTEMD_WORKER_SERVICE}" "${LEGACY_SYSTEMD_REAPER_SERVICE}" >/dev/null 2>&1 || true
  as_root_remove_file "${SYSTEMD_DIR}/${LEGACY_SYSTEMD_WORKER_SERVICE}"
  as_root_remove_file "${SYSTEMD_DIR}/${LEGACY_SYSTEMD_REAPER_SERVICE}"
}

install_systemd() {
  if ! command_exists systemctl; then
    log_error "systemctl is missing; systemd install is not available on this host."
    exit 1
  fi

  validate_instance_counts
  init_config
  log_info "Installing systemd templates to ${SYSTEMD_DIR}."
  legacy_disable_remove
  systemd_template_content worker:run "Praxi Agapis Feed OpenSearch Indexer Worker" | as_root_write_file "${SYSTEMD_DIR}/$(worker_template_unit)" 0644
  systemd_template_content reaper:run "Praxi Agapis Feed OpenSearch Indexer Reaper" | as_root_write_file "${SYSTEMD_DIR}/$(reaper_template_unit)" 0644
  run_systemctl daemon-reload
  for_worker_instances systemctl_enable_unit
  for_reaper_instances systemctl_enable_unit
  log_info "Installed worker template $(worker_template_unit), count=${WORKER_COUNT}."
  log_info "Installed reaper template $(reaper_template_unit), count=${REAPER_COUNT}."
  log_info "Start them with: ./feed_opensearch_ctl.sh services:start"
}

uninstall_systemd() {
  if ! command_exists systemctl; then
    log_error "systemctl is missing; systemd uninstall is not available on this host."
    exit 1
  fi

  log_info "Stopping/disabling systemd instances."
  for_worker_instances systemctl_disable_now_unit
  for_reaper_instances systemctl_disable_now_unit
  legacy_disable_remove
  as_root_remove_file "${SYSTEMD_DIR}/$(worker_template_unit)"
  as_root_remove_file "${SYSTEMD_DIR}/$(reaper_template_unit)"
  run_systemctl daemon-reload
  log_info "Removed managed systemd templates and instances."
}

show_systemd() {
  printf '# %s/%s\n' "${SYSTEMD_DIR}" "$(worker_template_unit)"
  systemd_template_content worker:run "Praxi Agapis Feed OpenSearch Indexer Worker"
  printf '\n# %s/%s\n' "${SYSTEMD_DIR}" "$(reaper_template_unit)"
  systemd_template_content reaper:run "Praxi Agapis Feed OpenSearch Indexer Reaper"
  printf '\n# configured instances\n'
  printf 'workers=%s\n' "${WORKER_COUNT}"
  printf 'reapers=%s\n' "${REAPER_COUNT}"
}

service_log_dir() {
  local log_dir
  log_dir="$(dirname "${LOG_FILE}")"

  case "${log_dir}" in
    .) printf '%s\n' "${SERVICE_DIR}" ;;
    /*) printf '%s\n' "${log_dir}" ;;
    *) printf '%s\n' "${SERVICE_DIR}/${log_dir}" ;;
  esac
}

ensure_log_dir() {
  mkdir -p "$(service_log_dir)"
}

logrotate_content() {
  local owner
  local group
  owner="$(service_owner)"
  group="$(service_group)"

  cat <<EOF
$(service_log_dir)/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
    su ${owner} ${group}
}
EOF
}

install_logrotate() {
  ensure_log_dir
  log_info "Installing logrotate config: ${LOGROTATE_FILE}"
  logrotate_content | as_root_write_file "${LOGROTATE_FILE}" 0644
}

uninstall_logrotate() {
  log_info "Removing logrotate config: ${LOGROTATE_FILE}"
  as_root_remove_file "${LOGROTATE_FILE}"
}

show_logrotate() {
  if [[ -f "${LOGROTATE_FILE}" ]]; then
    cat "${LOGROTATE_FILE}"
    return
  fi

  logrotate_content
}

compose() {
  docker compose -f "${COMPOSE_FILE}" "$@"
}

require_compose_file() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_error "Missing compose file: ${COMPOSE_FILE}"
    exit 1
  fi
}

require_systemctl() {
  if ! command_exists systemctl; then
    log_error "systemctl is missing."
    exit 1
  fi
}


confirm_exact() {
  local prompt="$1"
  local expected="$2"
  local value

  read -r -p "${prompt}: " value
  if [[ "${value}" != "${expected}" ]]; then
    log_error "Confirmation did not match; aborting."
    exit 1
  fi
}

prompt_choice() {
  local name="$1"
  local default_value="$2"
  local allowed="$3"
  local value

  read -r -p "${name} [${default_value}] (${allowed}): " value
  value="${value:-${default_value}}"

  case " ${allowed} " in
    *" ${value} "*) printf '%s\n' "${value}" ;;
    *)
      log_error "Invalid ${name}: ${value}"
      log_error "Allowed values: ${allowed}"
      exit 1
      ;;
  esac
}

mysql_account_sql() {
  printf '%s@%s' "$(sql_string "${MYSQL_USER}")" "$(sql_string "${MYSQL_APP_HOST}")"
}

validate_mysql_bootstrap_settings() {
  require_mysql_client
  require_schema_file
  sql_ident "${MYSQL_DATABASE}" >/dev/null
  validate_mysql_account_part MYSQL_USER "${MYSQL_USER}"
  validate_mysql_account_part MYSQL_APP_HOST "${MYSQL_APP_HOST}"
}

require_mysql_password_for_user() {
  if [[ -z "${MYSQL_PASSWORD}" ]]; then
    log_error "MYSQL_PASSWORD is empty; refusing to create/update MySQL user '${MYSQL_USER}'."
    log_error "Run ./feed_opensearch_ctl.sh configure or edit ${CONFIG_FILE}."
    exit 1
  fi
}

show_db_sql() {
  local db_ident
  local account
  local password_sql

  validate_mysql_bootstrap_settings
  db_ident="$(sql_ident "${MYSQL_DATABASE}")"
  account="$(mysql_account_sql)"
  password_sql="$(sql_string "${MYSQL_PASSWORD:-CHANGE_ME}")"

  if [[ -z "${MYSQL_PASSWORD}" ]]; then
    printf '%s\n' '-- MYSQL_PASSWORD is empty in config; replace CHANGE_ME before running this SQL.'
  fi

  cat <<EOF
CREATE DATABASE IF NOT EXISTS ${db_ident}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS ${account} IDENTIFIED BY ${password_sql};
ALTER USER ${account} IDENTIFIED BY ${password_sql};
GRANT SELECT, INSERT, UPDATE, DELETE ON ${db_ident}.* TO ${account};
FLUSH PRIVILEGES;
EOF
}

apply_database_action() {
  local action="$1"
  local db_ident

  db_ident="$(sql_ident "${MYSQL_DATABASE}")"

  case "${action}" in
    skip)
      log_info "Skipping database step."
      ;;
    create-missing)
      mysql_admin -e "CREATE DATABASE IF NOT EXISTS ${db_ident} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      log_info "Database ready: ${MYSQL_DATABASE}"
      ;;
    drop-recreate)
      confirm_exact "Type ${MYSQL_DATABASE} to DROP and recreate database ${MYSQL_DATABASE}" "${MYSQL_DATABASE}"
      mysql_admin -e "DROP DATABASE IF EXISTS ${db_ident}; CREATE DATABASE ${db_ident} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      log_info "Database recreated: ${MYSQL_DATABASE}"
      ;;
  esac
}

apply_user_action() {
  local action="$1"
  local db_ident
  local account
  local password_sql

  db_ident="$(sql_ident "${MYSQL_DATABASE}")"
  account="$(mysql_account_sql)"
  password_sql="$(sql_string "${MYSQL_PASSWORD}")"

  case "${action}" in
    skip)
      log_info "Skipping MySQL user/grants step."
      ;;
    create-update)
      require_mysql_password_for_user
      mysql_admin -e "CREATE USER IF NOT EXISTS ${account} IDENTIFIED BY ${password_sql}; ALTER USER ${account} IDENTIFIED BY ${password_sql}; GRANT SELECT, INSERT, UPDATE, DELETE ON ${db_ident}.* TO ${account}; FLUSH PRIVILEGES;"
      log_info "Runtime MySQL user/grants ready: ${MYSQL_USER}@${MYSQL_APP_HOST}"
      ;;
    drop-recreate)
      require_mysql_password_for_user
      confirm_exact "Type ${MYSQL_USER} to DROP and recreate MySQL user ${MYSQL_USER}@${MYSQL_APP_HOST}" "${MYSQL_USER}"
      mysql_admin -e "DROP USER IF EXISTS ${account}; CREATE USER ${account} IDENTIFIED BY ${password_sql}; GRANT SELECT, INSERT, UPDATE, DELETE ON ${db_ident}.* TO ${account}; FLUSH PRIVILEGES;"
      log_info "Runtime MySQL user/grants recreated: ${MYSQL_USER}@${MYSQL_APP_HOST}"
      ;;
  esac
}

apply_schema_action() {
  local action="$1"
  local table_ident='`search_index_jobs`'

  case "${action}" in
    skip)
      log_info "Skipping schema step."
      ;;
    create-missing)
      mysql_admin "${MYSQL_DATABASE}" < "${INDEXER_SCHEMA_FILE}"
      log_info "Schema ready from ${INDEXER_SCHEMA_FILE}"
      ;;
    drop-recreate)
      confirm_exact "Type ${MYSQL_DATABASE} to DROP and recreate indexer schema in ${MYSQL_DATABASE}" "${MYSQL_DATABASE}"
      mysql_admin "${MYSQL_DATABASE}" -e "DROP TABLE IF EXISTS ${table_ident};"
      mysql_admin "${MYSQL_DATABASE}" < "${INDEXER_SCHEMA_FILE}"
      log_info "Schema recreated from ${INDEXER_SCHEMA_FILE}"
      ;;
  esac
}

drop_indexer_schema() {
  local table_ident='`search_index_jobs`'

  confirm_exact "Type ${MYSQL_DATABASE} to DROP indexer schema table(s) in ${MYSQL_DATABASE}" "${MYSQL_DATABASE}"
  mysql_admin "${MYSQL_DATABASE}" -e "DROP TABLE IF EXISTS ${table_ident};"
  log_info "Dropped indexer schema table(s) from ${MYSQL_DATABASE}"
}

drop_database() {
  local db_ident

  db_ident="$(sql_ident "${MYSQL_DATABASE}")"
  confirm_exact "Type ${MYSQL_DATABASE} to DROP database ${MYSQL_DATABASE}" "${MYSQL_DATABASE}"
  mysql_admin -e "DROP DATABASE IF EXISTS ${db_ident};"
  log_info "Dropped database: ${MYSQL_DATABASE}"
}

drop_mysql_user() {
  local account

  account="$(mysql_account_sql)"
  confirm_exact "Type ${MYSQL_USER} to DROP MySQL user ${MYSQL_USER}@${MYSQL_APP_HOST}" "${MYSQL_USER}"
  mysql_admin -e "DROP USER IF EXISTS ${account}; FLUSH PRIVILEGES;"
  log_info "Dropped MySQL user: ${MYSQL_USER}@${MYSQL_APP_HOST}"
}

db_uninstall() {
  local schema_action
  local database_action
  local user_action

  validate_mysql_bootstrap_settings

  printf 'MySQL admin command: %s %s\n' "${MYSQL_ADMIN_BIN}" "${MYSQL_ADMIN_ARGS}"
  printf 'Target database: %s\n' "${MYSQL_DATABASE}"
  printf 'Runtime user: %s@%s\n' "${MYSQL_USER}" "${MYSQL_APP_HOST}"

  schema_action="$(prompt_choice schema keep 'keep drop')"
  database_action="$(prompt_choice database keep 'keep drop')"
  user_action="$(prompt_choice user keep 'keep drop')"

  if [[ "${schema_action}" == "drop" && "${database_action}" == "drop" ]]; then
    log_info "Database drop selected; skipping separate schema drop."
    schema_action="keep"
  fi

  [[ "${schema_action}" == "drop" ]] && drop_indexer_schema
  [[ "${database_action}" == "drop" ]] && drop_database
  [[ "${user_action}" == "drop" ]] && drop_mysql_user

  log_info "MySQL uninstall step finished."
}

remove_logs() {
  local log_dir
  log_dir="$(service_log_dir)"

  confirm_exact "Type DELETE LOGS to remove ${log_dir}" "DELETE LOGS"
  if [[ "$(id -u)" -eq 0 ]]; then
    rm -rf "${log_dir}"
  else
    sudo rm -rf "${log_dir}"
  fi
  log_info "Removed log directory: ${log_dir}"
}

uninstall_all() {
  local systemd_action
  local logrotate_action
  local db_action
  local service_user_action
  local logs_action

  printf 'Feed OpenSearch Indexer uninstall\n'
  printf 'Service directory: %s\n' "${SERVICE_DIR}"
  printf 'Database: %s\n' "${MYSQL_DATABASE}"
  printf 'MySQL user: %s@%s\n' "${MYSQL_USER}" "${MYSQL_APP_HOST}"
  printf 'Linux service user: %s:%s\n' "${SERVICE_USER}" "${SERVICE_GROUP}"

  systemd_action="$(prompt_choice systemd remove 'remove keep')"
  logrotate_action="$(prompt_choice logrotate remove 'remove keep')"
  db_action="$(prompt_choice mysql keep 'keep interactive-drop')"
  service_user_action="$(prompt_choice service-user keep 'keep remove')"
  logs_action="$(prompt_choice logs keep 'keep remove')"

  if [[ "${systemd_action}" == "remove" ]]; then
    uninstall_systemd
  fi

  if [[ "${logrotate_action}" == "remove" ]]; then
    uninstall_logrotate
  fi

  if [[ "${db_action}" == "interactive-drop" ]]; then
    db_uninstall
  fi

  if [[ "${service_user_action}" == "remove" ]]; then
    uninstall_service_user
  fi

  if [[ "${logs_action}" == "remove" ]]; then
    remove_logs
  fi

  log_info "Uninstall flow finished. Project files were not removed."
}

db_install() {
  local database_action
  local user_action
  local schema_action

  validate_mysql_bootstrap_settings

  printf 'MySQL admin command: %s %s\n' "${MYSQL_ADMIN_BIN}" "${MYSQL_ADMIN_ARGS}"
  printf 'Target database: %s\n' "${MYSQL_DATABASE}"
  printf 'Runtime user: %s@%s\n' "${MYSQL_USER}" "${MYSQL_APP_HOST}"
  printf 'Schema file: %s\n' "${INDEXER_SCHEMA_FILE}"

  database_action="$(prompt_choice database create-missing 'create-missing skip drop-recreate')"
  user_action="$(prompt_choice user create-update 'create-update skip drop-recreate')"
  schema_action="$(prompt_choice schema create-missing 'create-missing skip drop-recreate')"

  if [[ "${user_action}" != "skip" ]]; then
    require_mysql_password_for_user
  fi

  apply_database_action "${database_action}"
  apply_user_action "${user_action}"
  apply_schema_action "${schema_action}"

  log_info "MySQL bootstrap finished. Run ./feed_opensearch_ctl.sh db:status to verify runtime access."
}

db_schema() {
  local schema_action

  validate_mysql_bootstrap_settings
  printf 'Target database: %s\n' "${MYSQL_DATABASE}"
  printf 'Schema file: %s\n' "${INDEXER_SCHEMA_FILE}"
  schema_action="$(prompt_choice schema create-missing 'create-missing skip drop-recreate')"
  apply_schema_action "${schema_action}"
}

db_status() {
  local output
  local table_count
  local queue_count

  require_mysql_client
  sql_ident "${MYSQL_DATABASE}" >/dev/null

  printf 'MySQL runtime status\n'
  printf 'host=%s\n' "${MYSQL_HOST}"
  printf 'port=%s\n' "${MYSQL_PORT}"
  printf 'user=%s\n' "${MYSQL_USER}"
  printf 'database=%s\n' "${MYSQL_DATABASE}"
  printf 'password_set=%s\n' "$([[ -n "${MYSQL_PASSWORD}" ]] && printf yes || printf no)"

  if ! output="$(mysql_app "${MYSQL_DATABASE}" -N -B -e 'SELECT 1;' 2>&1)"; then
    printf 'fail runtime login/query: %s\n' "${output}"
    return 1
  fi
  printf 'ok   runtime login/query\n'

  table_count="$(mysql_app "${MYSQL_DATABASE}" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'search_index_jobs';")"
  if [[ "${table_count}" == "1" ]]; then
    printf 'ok   table search_index_jobs exists\n'
    queue_count="$(mysql_app "${MYSQL_DATABASE}" -N -B -e 'SELECT COUNT(*) FROM search_index_jobs;')"
    printf 'ok   queue rows=%s\n' "${queue_count}"
  else
    printf 'miss table search_index_jobs\n'
    return 1
  fi
}

print_config() {
  cat <<EOF
service_dir=${SERVICE_DIR}
config_file=${CONFIG_FILE}
compose_file=${COMPOSE_FILE}
venv_dir=${VENV_DIR}
requirements_file=${REQUIREMENTS_FILE}
python_bin=${PYTHON_BIN}
os_family=$(detect_os_family)
package_manager=$(package_manager)
db_engine=${DB_ENGINE}
mysql_host=${MYSQL_HOST}
mysql_port=${MYSQL_PORT}
mysql_user=${MYSQL_USER}
mysql_password_set=$([[ -n "${MYSQL_PASSWORD}" ]] && printf yes || printf no)
mysql_database=${MYSQL_DATABASE}
mysql_app_host=${MYSQL_APP_HOST}
mysql_bin=${MYSQL_BIN}
mysql_admin_bin=${MYSQL_ADMIN_BIN}
mysql_admin_args_set=$([[ -n "${MYSQL_ADMIN_ARGS}" ]] && printf yes || printf no)
service_user=${SERVICE_USER}
service_group=${SERVICE_GROUP}
indexer_schema_file=${INDEXER_SCHEMA_FILE}
log_file=${LOG_FILE}
log_dir=$(service_log_dir)
daemon_batch_size=${DAEMON_BATCH_SIZE}
daemon_claim_strategy=${DAEMON_CLAIM_STRATEGY}
reaper_stale_seconds=${REAPER_STALE_SECONDS}
worker_template=$(worker_template_unit)
reaper_template=$(reaper_template_unit)
worker_count=${WORKER_COUNT}
reaper_count=${REAPER_COUNT}
systemd_dir=${SYSTEMD_DIR}
logrotate_file=${LOGROTATE_FILE}
EOF
}

doctor_check_command() {
  local command_name="$1"
  if command_exists "${command_name}"; then
    printf 'ok   command %s -> %s\n' "${command_name}" "$(command -v "${command_name}")"
  else
    printf 'miss command %s\n' "${command_name}"
  fi
}

doctor_check_python_venv_module() {
  if python3 -m venv --help >/dev/null 2>&1; then
    printf 'ok   python3 venv module\n'
  else
    printf 'miss python3 venv module\n'
  fi
}

doctor_check_file() {
  local label="$1"
  local file_path="$2"
  if [[ -f "${file_path}" ]]; then
    printf 'ok   %s %s\n' "${label}" "${file_path}"
  else
    printf 'miss %s %s\n' "${label}" "${file_path}"
  fi
}

doctor_check_password() {
  if [[ -n "${MYSQL_PASSWORD}" ]]; then
    printf 'ok   MYSQL_PASSWORD is set\n'
  else
    printf 'warn MYSQL_PASSWORD is empty\n'
  fi
}
doctor_check_service() {
  local service_name="$1"
  if ! command_exists systemctl; then
    printf 'miss systemd unavailable for %s\n' "${service_name}"
    return
  fi

  if systemctl list-unit-files "${service_name}" >/dev/null 2>&1; then
    printf 'ok   systemd unit visible %s\n' "${service_name}"
  else
    printf 'miss systemd unit %s\n' "${service_name}"
  fi
}

doctor() {
  printf 'Feed OpenSearch Indexer doctor\n'
  printf 'os_family=%s\n' "$(detect_os_family)"
  printf 'package_manager=%s\n' "$(package_manager)"
  doctor_check_command python3
  if command_exists python3; then
    doctor_check_python_venv_module
  fi
  doctor_check_command "${MYSQL_BIN}"
  if [[ "${MYSQL_ADMIN_BIN}" != "${MYSQL_BIN}" ]]; then
    doctor_check_command "${MYSQL_ADMIN_BIN}"
  fi
  doctor_check_command curl
  doctor_check_command systemctl
  doctor_check_command logrotate
  doctor_check_command docker
  doctor_check_password
  if command_exists getent; then
    if getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
      printf 'ok   service user %s\n' "${SERVICE_USER}"
    else
      printf 'miss service user %s\n' "${SERVICE_USER}"
    fi
  else
    printf 'miss command getent\n'
  fi
  doctor_check_file config "${CONFIG_FILE}"
  doctor_check_file requirements "${REQUIREMENTS_FILE}"
  doctor_check_file indexer_schema "${INDEXER_SCHEMA_FILE}"
  doctor_check_file compose "${COMPOSE_FILE}"
  if [[ -x "${VENV_DIR}/bin/python" ]]; then
    printf 'ok   venv python %s\n' "${VENV_DIR}/bin/python"
  else
    printf 'miss venv python %s\n' "${VENV_DIR}/bin/python"
  fi
  doctor_check_service "$(worker_template_unit)"
  doctor_check_service "$(reaper_template_unit)"
  printf 'configured workers=%s
' "${WORKER_COUNT}"
  printf 'configured reapers=%s
' "${REAPER_COUNT}"
  doctor_next_steps
}

doctor_next_steps() {
  printf '\nNext steps:\n'

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    printf '  - Create config: ./feed_opensearch_ctl.sh init-config or ./feed_opensearch_ctl.sh configure\n'
  fi

  if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    printf '  - Create Python venv: ./feed_opensearch_ctl.sh setup-venv\n'
  fi

  if ! command_exists docker; then
    printf '  - Docker is optional unless using bundled local OpenSearch. For production, external OpenSearch can be configured later.\n'
  fi

  if ! command_exists "${MYSQL_BIN}"; then
    printf '  - MySQL is external to this installer; install/provide mysql client before running DB commands.\n'
  fi

  if [[ -z "${MYSQL_PASSWORD}" ]]; then
    printf '  - Set MYSQL_PASSWORD before db:install creates/updates the runtime MySQL user.\n'
  fi

  if command_exists systemctl; then
    if ! systemctl list-unit-files "$(worker_template_unit)" >/dev/null 2>&1 \
      || ! systemctl list-unit-files "$(reaper_template_unit)" >/dev/null 2>&1; then
      printf '  - Install services after config/venv: ./feed_opensearch_ctl.sh install-systemd\n'
    fi
  fi
}

main() {
  local command="${1:-help}"

  case "${command}" in
    help|-h|--help)
      usage
      ;;
    doctor)
      doctor
      ;;
    install-deps)
      install_deps
      ;;
    setup-venv)
      setup_venv
      ;;
    init-config)
      init_config
      ;;
    configure)
      configure
      ;;
    install-service-user)
      install_service_user
      ;;
    fix-permissions)
      fix_permissions
      ;;
    db:install)
      db_install
      ;;
    db:uninstall)
      db_uninstall
      ;;
    db:schema)
      db_schema
      ;;
    db:status)
      db_status
      ;;
    show-db-sql)
      show_db_sql
      ;;
    install-systemd)
      install_systemd
      ;;
    uninstall)
      uninstall_all
      ;;
    uninstall-systemd)
      uninstall_systemd
      ;;
    show-systemd)
      show_systemd
      ;;
    install-logrotate)
      install_logrotate
      ;;
    uninstall-logrotate)
      uninstall_logrotate
      ;;
    show-logrotate)
      show_logrotate
      ;;
    config)
      print_config
      ;;
    opensearch:start)
      require_compose_file
      compose up -d
      ;;
    opensearch:stop)
      require_compose_file
      compose stop
      ;;
    opensearch:restart)
      require_compose_file
      compose restart
      ;;
    opensearch:status)
      require_compose_file
      compose ps
      ;;
    opensearch:logs)
      require_compose_file
      compose logs -f
      ;;
    worker:run)
      ensure_log_dir
      "${PYTHON_BIN}" -m app.daemon
      ;;
    reaper:run)
      ensure_log_dir
      "${PYTHON_BIN}" -m app.reaper
      ;;
    worker:start)
      require_systemctl
      for_worker_instances systemctl_start_unit
      ;;
    worker:stop)
      require_systemctl
      for_worker_instances systemctl_stop_unit
      ;;
    worker:restart)
      require_systemctl
      for_worker_instances systemctl_restart_unit
      ;;
    worker:status)
      require_systemctl
      for_worker_instances systemctl_status_unit
      ;;
    worker:logs)
      require_systemctl
      for_worker_instances journal_unit_action
      ;;
    reaper:start)
      require_systemctl
      for_reaper_instances systemctl_start_unit
      ;;
    reaper:stop)
      require_systemctl
      for_reaper_instances systemctl_stop_unit
      ;;
    reaper:restart)
      require_systemctl
      for_reaper_instances systemctl_restart_unit
      ;;
    reaper:status)
      require_systemctl
      for_reaper_instances systemctl_status_unit
      ;;
    reaper:logs)
      require_systemctl
      for_reaper_instances journal_unit_action
      ;;
    services:start)
      require_systemctl
      for_worker_instances systemctl_start_unit
      for_reaper_instances systemctl_start_unit
      ;;
    services:stop)
      require_systemctl
      for_worker_instances systemctl_stop_unit
      for_reaper_instances systemctl_stop_unit
      ;;
    services:restart)
      require_systemctl
      for_worker_instances systemctl_restart_unit
      for_reaper_instances systemctl_restart_unit
      ;;
    services:status)
      require_systemctl
      for_worker_instances systemctl_status_unit
      for_reaper_instances systemctl_status_unit
      ;;
    services:logs)
      require_systemctl
      for_worker_instances journal_unit_action
      for_reaper_instances journal_unit_action
      ;;
    *)
      log_error "Unknown command: ${command}"
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
