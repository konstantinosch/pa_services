#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FEED_OPENSEARCH_CONFIG:-${SERVICE_DIR}/config.env}"
COMPOSE_FILE="${SERVICE_DIR}/docker/opensearch/docker-compose.yml"
VENV_DIR="${FEED_OPENSEARCH_VENV:-${SERVICE_DIR}/venv}"
REQUIREMENTS_FILE="${SERVICE_DIR}/requirements.txt"
INDEXER_SCHEMA_FILE="${SERVICE_DIR}/sql/indexer/schema_mysql.sql"
OPENSEARCH_INDEX_FILE="${SERVICE_DIR}/opensearch/campaign_actions_feed.index.json"
OPENSEARCH_DISCOVERY_QUERY_FILE="${SERVICE_DIR}/opensearch/query_stage_d_unrelated_discovery.json"
OPENSEARCH_FULL_INDEX_SQL_FILE="${SERVICE_DIR}/sql/opensearch/campaign_actions_feed_full_index.sql"
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

BASH_BIN="${BASH_BIN:-/usr/bin/bash}"
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
DOCKER_BIN="${DOCKER_BIN:-docker}"
SOURCE_MYSQL_HOST="${SOURCE_MYSQL_HOST:-localhost}"
SOURCE_MYSQL_PORT="${SOURCE_MYSQL_PORT:-3306}"
SOURCE_MYSQL_USER="${SOURCE_MYSQL_USER:-}"
SOURCE_MYSQL_PASSWORD="${SOURCE_MYSQL_PASSWORD:-}"
SOURCE_MYSQL_DATABASE="${SOURCE_MYSQL_DATABASE:-deedspot}"
SOURCE_MYSQL_BIN="${SOURCE_MYSQL_BIN:-${MYSQL_BIN}}"
SOURCE_MYSQL_SUDO="${SOURCE_MYSQL_SUDO:-1}"
SERVICE_USER="${SERVICE_USER:-pa_indexer}"
SERVICE_GROUP="${SERVICE_GROUP:-${SERVICE_USER}}"
OPENSEARCH_URL="${OPENSEARCH_URL:-http://localhost:9200}"
OPENSEARCH_INDEX="${OPENSEARCH_INDEX:-campaign_actions_feed}"
OPENSEARCH_USERNAME="${OPENSEARCH_USERNAME:-}"
OPENSEARCH_PASSWORD="${OPENSEARCH_PASSWORD:-}"
OPENSEARCH_TIMEOUT_SECONDS="${OPENSEARCH_TIMEOUT_SECONDS:-10}"
OPENSEARCH_WAIT_SECONDS="${OPENSEARCH_WAIT_SECONDS:-90}"
OPENSEARCH_INITIAL_ADMIN_PASSWORD="${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-Pa_OpenSearch_2026!ChangeMe}"
OPENSEARCH_LOADER_PAGE_SIZE="${OPENSEARCH_LOADER_PAGE_SIZE:-10000}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-logs/pa_opensearch_indexer.log}"
WORKER_BATCH_SIZE="${WORKER_BATCH_SIZE:-100}"
WORKER_CLAIM_STRATEGY="${WORKER_CLAIM_STRATEGY:-simple}"
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
  doctor                       Check OS, commands, config, venv, Docker, and systemd units
  install-deps                 Install base OS dependencies on Ubuntu/Debian or CentOS/RHEL
  setup-venv                   Create/update Python venv and install requirements.txt
  init-config                  Create config.env from config.example.env if missing
  configure                    Interactively write config.env
  db:install                   Interactively create/reset MySQL database, user, grants, and schema
  db:uninstall                 Interactively drop MySQL schema, database, and/or user
  db:drop                      Non-interactively drop MySQL database and runtime user
  db:schema                    Interactively create/reset only indexer schema relations
  db:status                    Check app MySQL login and indexer schema visibility
  source:status                Check worker source MySQL read access for campaign actions
  show-db-sql                  Print admin SQL for database, user, and grants
  install-service-user         Create the dedicated Linux service user/group
  fix-permissions              Apply service-user ownership and private config permissions
  install-systemd              Install and enable worker/reaper systemd services
  uninstall                    Non-interactively remove managed install state
  uninstall-interactive        Interactively uninstall selected managed pieces
  uninstall-systemd            Disable and remove worker/reaper systemd services
  show-systemd                 Print generated systemd service files
  install-logrotate            Install logrotate rule for LOG_FILE directory
  uninstall-logrotate          Remove managed logrotate rule
  show-logrotate               Print active or generated logrotate rule

OpenSearch:
  opensearch:install           Start bundled local OpenSearch and wait for health
  opensearch:uninstall         Interactively stop/remove bundled local OpenSearch
  opensearch:start             Start the local OpenSearch Docker container
  opensearch:stop              Stop the local OpenSearch Docker container
  opensearch:restart           Restart the local OpenSearch Docker container
  opensearch:status            Show OpenSearch container status
  opensearch:logs              Follow OpenSearch logs
  opensearch:health            Check OpenSearch HTTP and cluster health
  opensearch:index:create      Create OPENSEARCH_INDEX if missing
  opensearch:index:reset       Delete and recreate OPENSEARCH_INDEX
  opensearch:index:delete      Delete OPENSEARCH_INDEX
  opensearch:index:show        Show OPENSEARCH_INDEX mapping/settings
  opensearch:load:dry-run      Read source DB pages without writing OpenSearch
  opensearch:load              Create index if missing, then bulk upsert source DB rows
  opensearch:rebuild           Delete/recreate index, then bulk upsert source DB rows

Indexer:
  worker:run                   Run the indexing worker in the foreground
  worker:check                 Check worker file, DB, source DB, and OpenSearch access
  reaper:run                   Run stale job ownership recovery in the foreground
  reaper:check                 Check reaper file and DB access
  worker:start                 Start worker systemd service
  worker:stop                  Stop worker systemd service
  worker:restart               Restart worker systemd service
  worker:status                Show configured worker systemd instance status
  worker:logs                  Show worker systemd journal logs
  worker:logs:follow           Follow worker systemd journal logs
  reaper:start                 Start reaper systemd service
  reaper:stop                  Stop reaper systemd service
  reaper:restart               Restart reaper systemd service
  reaper:status                Show configured reaper systemd instance status
  reaper:logs                  Show reaper systemd journal logs
  reaper:logs:follow           Follow reaper systemd journal logs
  services:start               Start worker and reaper services
  services:stop                Stop worker and reaper services
  services:restart             Restart worker and reaper services
  services:status              Show worker and reaper service status
  services:logs                Show worker and reaper systemd journal logs
  services:logs:follow         Follow worker and reaper systemd journal logs

Project:
  config                       Print resolved project paths and command settings
  help                         Show this help

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

source_mysql_worker_user() {
  if [[ -n "${SOURCE_MYSQL_USER}" ]]; then
    printf '%s\n' "${SOURCE_MYSQL_USER}"
  else
    printf '%s\n' "${MYSQL_USER}"
  fi
}

source_mysql_worker_password() {
  if [[ -n "${SOURCE_MYSQL_PASSWORD}" ]]; then
    printf '%s\n' "${SOURCE_MYSQL_PASSWORD}"
  else
    printf '%s\n' "${MYSQL_PASSWORD}"
  fi
}

source_mysql_worker() {
  MYSQL_PWD="$(source_mysql_worker_password)" "${SOURCE_MYSQL_BIN}" \
    -h "${SOURCE_MYSQL_HOST}" \
    -P "${SOURCE_MYSQL_PORT}" \
    -u "$(source_mysql_worker_user)" \
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
  local source_mysql_password
  local opensearch_password
  local opensearch_admin_password
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
  SOURCE_MYSQL_HOST="$(prompt_value SOURCE_MYSQL_HOST "${SOURCE_MYSQL_HOST}")"
  SOURCE_MYSQL_PORT="$(prompt_value SOURCE_MYSQL_PORT "${SOURCE_MYSQL_PORT}")"
  SOURCE_MYSQL_USER="$(prompt_value SOURCE_MYSQL_USER "${SOURCE_MYSQL_USER}")"
  SOURCE_MYSQL_DATABASE="$(prompt_value SOURCE_MYSQL_DATABASE "${SOURCE_MYSQL_DATABASE}")"
  SOURCE_MYSQL_BIN="$(prompt_value SOURCE_MYSQL_BIN "${SOURCE_MYSQL_BIN}")"
  SOURCE_MYSQL_SUDO="$(prompt_value SOURCE_MYSQL_SUDO "${SOURCE_MYSQL_SUDO}")"
  SERVICE_USER="$(prompt_value SERVICE_USER "${SERVICE_USER}")"
  SERVICE_GROUP="$(prompt_value SERVICE_GROUP "${SERVICE_GROUP}")"
  OPENSEARCH_URL="$(prompt_value OPENSEARCH_URL "${OPENSEARCH_URL}")"
  OPENSEARCH_INDEX="$(prompt_value OPENSEARCH_INDEX "${OPENSEARCH_INDEX}")"
  OPENSEARCH_USERNAME="$(prompt_value OPENSEARCH_USERNAME "${OPENSEARCH_USERNAME}")"
  OPENSEARCH_TIMEOUT_SECONDS="$(prompt_value OPENSEARCH_TIMEOUT_SECONDS "${OPENSEARCH_TIMEOUT_SECONDS}")"
  OPENSEARCH_WAIT_SECONDS="$(prompt_value OPENSEARCH_WAIT_SECONDS "${OPENSEARCH_WAIT_SECONDS}")"
  OPENSEARCH_LOADER_PAGE_SIZE="$(prompt_value OPENSEARCH_LOADER_PAGE_SIZE "${OPENSEARCH_LOADER_PAGE_SIZE}")"
  read -r -s -p "OPENSEARCH_PASSWORD [leave blank to keep current]: " opensearch_password
  printf '\n'
  if [[ -z "${opensearch_password}" ]]; then
    opensearch_password="${OPENSEARCH_PASSWORD}"
  fi
  read -r -s -p "OPENSEARCH_INITIAL_ADMIN_PASSWORD [leave blank to keep current]: " opensearch_admin_password
  printf '\n'
  if [[ -z "${opensearch_admin_password}" ]]; then
    opensearch_admin_password="${OPENSEARCH_INITIAL_ADMIN_PASSWORD}"
  fi
  read -r -s -p "MYSQL_PASSWORD [leave blank to keep current]: " mysql_password
  printf '\n'
  if [[ -z "${mysql_password}" ]]; then
    mysql_password="${MYSQL_PASSWORD}"
  fi
  read -r -s -p "SOURCE_MYSQL_PASSWORD [leave blank to keep current]: " source_mysql_password
  printf '\n'
  if [[ -z "${source_mysql_password}" ]]; then
    source_mysql_password="${SOURCE_MYSQL_PASSWORD}"
  fi
  log_file="$(prompt_value LOG_FILE "${LOG_FILE}")"
  python_bin="$(prompt_value PYTHON_BIN "${VENV_DIR}/bin/python")"
  WORKER_BATCH_SIZE="$(prompt_value WORKER_BATCH_SIZE "${WORKER_BATCH_SIZE}")"
  WORKER_CLAIM_STRATEGY="$(prompt_value WORKER_CLAIM_STRATEGY "${WORKER_CLAIM_STRATEGY}")"
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

SOURCE_MYSQL_HOST=$(shell_quote "${SOURCE_MYSQL_HOST}")
SOURCE_MYSQL_PORT=$(shell_quote "${SOURCE_MYSQL_PORT}")
SOURCE_MYSQL_USER=$(shell_quote "${SOURCE_MYSQL_USER}")
SOURCE_MYSQL_PASSWORD=$(shell_quote "${source_mysql_password}")
SOURCE_MYSQL_DATABASE=$(shell_quote "${SOURCE_MYSQL_DATABASE}")
SOURCE_MYSQL_BIN=$(shell_quote "${SOURCE_MYSQL_BIN}")
SOURCE_MYSQL_SUDO=$(shell_quote "${SOURCE_MYSQL_SUDO}")

SERVICE_USER=$(shell_quote "${SERVICE_USER}")
SERVICE_GROUP=$(shell_quote "${SERVICE_GROUP}")

OPENSEARCH_URL=$(shell_quote "${OPENSEARCH_URL}")
OPENSEARCH_INDEX=$(shell_quote "${OPENSEARCH_INDEX}")
OPENSEARCH_USERNAME=$(shell_quote "${OPENSEARCH_USERNAME}")
OPENSEARCH_PASSWORD=$(shell_quote "${opensearch_password}")
OPENSEARCH_TIMEOUT_SECONDS=${OPENSEARCH_TIMEOUT_SECONDS}
OPENSEARCH_WAIT_SECONDS=${OPENSEARCH_WAIT_SECONDS}
OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(shell_quote "${opensearch_admin_password}")
OPENSEARCH_LOADER_PAGE_SIZE=$(shell_quote "${OPENSEARCH_LOADER_PAGE_SIZE}")

PYTHON_BIN=$(shell_quote "${python_bin}")
LOG_LEVEL=$(shell_quote "${LOG_LEVEL}")
LOG_FILE=$(shell_quote "${log_file}")

WORKER_POLL_INTERVAL_SECONDS=2
WORKER_BATCH_DELAY_SECONDS=0
WORKER_BATCH_SIZE=${WORKER_BATCH_SIZE}
WORKER_CLAIM_STRATEGY=$(shell_quote "${WORKER_CLAIM_STRATEGY}")
WORKER_RETRY_DELAY_SECONDS=0

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
  local service_parent
  log_dir="$(service_log_dir)"
  service_parent="$(dirname "${SERVICE_DIR}")"

  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "${log_dir}"
    if [[ "${service_parent}" != "/" && "${service_parent}" != "." ]]; then
      chgrp "${SERVICE_GROUP}" "${service_parent}"
      chmod g+rx "${service_parent}"
    fi
    chgrp -R "${SERVICE_GROUP}" "${SERVICE_DIR}"
    chmod -R g+rX,o-rwx "${SERVICE_DIR}"
    chmod 750 "${SERVICE_DIR}"
    chmod 750 "${SERVICE_DIR}/feed_opensearch_ctl.sh"
    if [[ -f "${CONFIG_FILE}" ]]; then
      chgrp "${SERVICE_GROUP}" "${CONFIG_FILE}"
      chmod 640 "${CONFIG_FILE}"
    fi
    chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${log_dir}"
    chmod 750 "${log_dir}"
  else
    sudo mkdir -p "${log_dir}"
    if [[ "${service_parent}" != "/" && "${service_parent}" != "." ]]; then
      sudo chgrp "${SERVICE_GROUP}" "${service_parent}"
      sudo chmod g+rx "${service_parent}"
    fi
    sudo chgrp -R "${SERVICE_GROUP}" "${SERVICE_DIR}"
    sudo chmod -R g+rX,o-rwx "${SERVICE_DIR}"
    sudo chmod 750 "${SERVICE_DIR}"
    sudo chmod 750 "${SERVICE_DIR}/feed_opensearch_ctl.sh"
    if [[ -f "${CONFIG_FILE}" ]]; then
      sudo chgrp "${SERVICE_GROUP}" "${CONFIG_FILE}"
      sudo chmod 640 "${CONFIG_FILE}"
    fi
    sudo chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${log_dir}"
    sudo chmod 750 "${log_dir}"
  fi

  log_info "Applied service traverse permissions for ${SERVICE_GROUP} on ${service_parent}"
  log_info "Applied service read permissions for ${SERVICE_GROUP} under ${SERVICE_DIR}"
  log_info "Applied service write ownership for ${SERVICE_USER}:${SERVICE_GROUP} under ${log_dir}"
  if [[ "$(id -u)" -ne 0 ]] && ! id -nG | tr ' ' '\n' | grep -qx "${SERVICE_GROUP}"; then
    log_info "Current user $(id -un) is not in group ${SERVICE_GROUP}; future non-sudo control commands may get Permission denied."
    log_info "Run: sudo usermod -aG ${SERVICE_GROUP} $(id -un)"
    log_info "Then reconnect or run: newgrp ${SERVICE_GROUP}"
  fi
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
After=network-online.target mysql.service mysqld.service mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=${owner}
Group=${group}
WorkingDirectory=${SERVICE_DIR}
Environment=FEED_OPENSEARCH_CONFIG=${CONFIG_FILE}
Environment=FEED_OPENSEARCH_INSTANCE=%i
ExecStart=${BASH_BIN} ${SERVICE_DIR}/feed_opensearch_ctl.sh ${command_name}
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

journal_unit_follow() {
  if [[ "$(id -u)" -eq 0 ]]; then
    journalctl -u "$1" -n "${JOURNAL_LINES:-100}" -f
  else
    sudo journalctl -u "$1" -n "${JOURNAL_LINES:-100}" -f
  fi
}

journal_unit_action() {
  journal_unit "$1"
}

journal_unit_follow_action() {
  journal_unit_follow "$1"
}

journal_services_follow() {
  local args=()
  local i

  validate_instance_counts

  for (( i = 1; i <= WORKER_COUNT; i++ )); do
    args+=(-u "$(worker_instance_unit "${i}")")
  done

  for (( i = 1; i <= REAPER_COUNT; i++ )); do
    args+=(-u "$(reaper_instance_unit "${i}")")
  done

  if [[ "$(id -u)" -eq 0 ]]; then
    journalctl "${args[@]}" -n "${JOURNAL_LINES:-100}" -f
  else
    sudo journalctl "${args[@]}" -n "${JOURNAL_LINES:-100}" -f
  fi
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

docker_has_direct_access() {
  "${DOCKER_BIN}" info >/dev/null 2>&1
}

docker_has_sudo_access() {
  [[ "$(id -u)" -ne 0 ]] && command_exists sudo && sudo -n "${DOCKER_BIN}" info >/dev/null 2>&1
}

docker_run() {
  if docker_has_direct_access; then
    "${DOCKER_BIN}" "$@"
    return
  fi

  if [[ "$(id -u)" -ne 0 ]] && command_exists sudo; then
    sudo "${DOCKER_BIN}" "$@"
    return
  fi

  "${DOCKER_BIN}" "$@"
}

compose() {
  docker_run compose -f "${COMPOSE_FILE}" "$@"
}

require_docker() {
  if ! command_exists "${DOCKER_BIN}"; then
    log_error "docker is missing."
    log_error "Install Docker or configure OPENSEARCH_URL for an external OpenSearch service."
    exit 1
  fi
}

require_compose_file() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_error "Missing compose file: ${COMPOSE_FILE}"
    exit 1
  fi
}

require_opensearch_index_file() {
  if [[ ! -f "${OPENSEARCH_INDEX_FILE}" ]]; then
    log_error "Missing OpenSearch index file: ${OPENSEARCH_INDEX_FILE}"
    exit 1
  fi
}

opensearch_curl() {
  local method="$1"
  local path="$2"
  shift 2

  local args=(
    --silent
    --show-error
    --fail
    --connect-timeout "${OPENSEARCH_TIMEOUT_SECONDS}"
    --max-time "${OPENSEARCH_TIMEOUT_SECONDS}"
    -X "${method}"
  )

  if [[ -n "${OPENSEARCH_USERNAME}" ]]; then
    args+=(-u "${OPENSEARCH_USERNAME}:${OPENSEARCH_PASSWORD}")
  fi

  curl "${args[@]}" "${OPENSEARCH_URL%/}${path}" "$@"
}

opensearch_status_code() {
  local method="$1"
  local path="$2"
  local args=(
    --silent
    --output /dev/null
    --write-out '%{http_code}'
    --connect-timeout "${OPENSEARCH_TIMEOUT_SECONDS}"
    --max-time "${OPENSEARCH_TIMEOUT_SECONDS}"
    -X "${method}"
  )

  if [[ -n "${OPENSEARCH_USERNAME}" ]]; then
    args+=(-u "${OPENSEARCH_USERNAME}:${OPENSEARCH_PASSWORD}")
  fi

  curl "${args[@]}" "${OPENSEARCH_URL%/}${path}" || true
}

opensearch_index_exists() {
  [[ "$(opensearch_status_code HEAD "/${OPENSEARCH_INDEX}")" == "200" ]]
}

opensearch_wait() {
  local deadline
  deadline=$((SECONDS + OPENSEARCH_WAIT_SECONDS))

  log_info "Waiting up to ${OPENSEARCH_WAIT_SECONDS}s for OpenSearch at ${OPENSEARCH_URL}."
  while (( SECONDS < deadline )); do
    if opensearch_curl GET "/" >/dev/null 2>&1; then
      log_info "OpenSearch is reachable."
      return 0
    fi
    sleep 2
  done

  log_error "OpenSearch did not become reachable at ${OPENSEARCH_URL}."
  return 1
}

opensearch_install() {
  require_docker
  require_compose_file
  compose up -d
  opensearch_wait
  opensearch_health
}

opensearch_uninstall() {
  local action

  printf 'Bundled local OpenSearch uninstall\n'
  printf 'compose_file=%s\n' "${COMPOSE_FILE}"
  printf 'url=%s\n' "${OPENSEARCH_URL}"
  action="$(prompt_choice containers stop 'stop down down-volumes keep')"
  opensearch_apply_container_action "${action}"
}

opensearch_apply_container_action() {
  local action="$1"
  local require_confirmation="${2:-yes}"
  case "${action}" in
    stop)
      require_docker
      require_compose_file
      compose stop
      ;;
    down)
      require_docker
      require_compose_file
      compose down
      ;;
    down-volumes)
      if [[ "${require_confirmation}" == "yes" ]]; then
        confirm_exact "Type ${OPENSEARCH_INDEX} to remove OpenSearch containers and Docker volume data" "${OPENSEARCH_INDEX}"
      fi
      require_docker
      require_compose_file
      compose down -v
      ;;
    keep)
      log_info "Keeping bundled OpenSearch containers untouched."
      ;;
  esac
}

opensearch_health() {
  printf 'OpenSearch HTTP status\n'
  printf 'url=%s\n' "${OPENSEARCH_URL}"
  printf 'index=%s\n' "${OPENSEARCH_INDEX}"
  opensearch_curl GET "/" || return 1
  printf '\n\nOpenSearch cluster health\n'
  opensearch_curl GET "/_cluster/health?pretty"
  printf '\n'
}

opensearch_index_create() {
  require_opensearch_index_file

  if opensearch_index_exists; then
    log_info "OpenSearch index already exists: ${OPENSEARCH_INDEX}"
    return 0
  fi

  log_info "Creating OpenSearch index: ${OPENSEARCH_INDEX}"
  opensearch_curl PUT "/${OPENSEARCH_INDEX}" \
    -H 'Content-Type: application/json' \
    --data-binary "@${OPENSEARCH_INDEX_FILE}"
  printf '\n'
}

opensearch_index_delete() {
  if ! opensearch_index_exists; then
    log_info "OpenSearch index does not exist: ${OPENSEARCH_INDEX}"
    return 0
  fi

  confirm_exact "Type ${OPENSEARCH_INDEX} to DELETE OpenSearch index ${OPENSEARCH_INDEX}" "${OPENSEARCH_INDEX}"
  opensearch_curl DELETE "/${OPENSEARCH_INDEX}"
  printf '\n'
}

opensearch_index_delete_now() {
  if ! opensearch_index_exists; then
    log_info "OpenSearch index does not exist: ${OPENSEARCH_INDEX}"
    return 0
  fi

  opensearch_curl DELETE "/${OPENSEARCH_INDEX}"
  printf '\n'
}

opensearch_index_reset() {
  require_opensearch_index_file
  confirm_exact "Type ${OPENSEARCH_INDEX} to DELETE and recreate OpenSearch index ${OPENSEARCH_INDEX}" "${OPENSEARCH_INDEX}"

  if opensearch_index_exists; then
    opensearch_curl DELETE "/${OPENSEARCH_INDEX}"
    printf '\n'
  fi

  opensearch_index_create
}

opensearch_index_show() {
  opensearch_curl GET "/${OPENSEARCH_INDEX}?pretty"
  printf '\n'
}

run_opensearch_loader() {
  local args=(
    -m app.index_loader
    --sql-file "${OPENSEARCH_FULL_INDEX_SQL_FILE}"
    --index-file "${OPENSEARCH_INDEX_FILE}"
    --mysql-command "${SOURCE_MYSQL_BIN}"
    --mysql-host "${SOURCE_MYSQL_HOST}"
    --mysql-port "${SOURCE_MYSQL_PORT}"
    --mysql-user "${SOURCE_MYSQL_USER}"
    --mysql-password "${SOURCE_MYSQL_PASSWORD}"
    --mysql-database "${SOURCE_MYSQL_DATABASE}"
    --opensearch-url "${OPENSEARCH_URL}"
    --opensearch-username "${OPENSEARCH_USERNAME}"
    --opensearch-password "${OPENSEARCH_PASSWORD}"
    --index "${OPENSEARCH_INDEX}"
    --page-size "${OPENSEARCH_LOADER_PAGE_SIZE}"
  )

  if [[ "${SOURCE_MYSQL_SUDO}" == "1" || "${SOURCE_MYSQL_SUDO}" == "true" || "${SOURCE_MYSQL_SUDO}" == "yes" ]]; then
    args+=(--mysql-sudo)
  fi

  "${PYTHON_BIN}" "${args[@]}" "$@"
}

opensearch_load_dry_run() {
  run_opensearch_loader --dry-run
}

opensearch_load() {
  run_opensearch_loader --create-index
}

opensearch_rebuild() {
  confirm_exact "Type ${OPENSEARCH_INDEX} to DELETE and rebuild OpenSearch index ${OPENSEARCH_INDEX}" "${OPENSEARCH_INDEX}"
  run_opensearch_loader --reset-index
}

require_systemctl() {
  if ! command_exists systemctl; then
    log_error "systemctl is missing."
    exit 1
  fi
}

opensearch_destroy_containers_now() {
  if ! command_exists "${DOCKER_BIN}"; then
    log_info "Docker command missing; skipping bundled OpenSearch container cleanup."
    return
  fi

  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_info "Compose file missing; skipping bundled OpenSearch container cleanup."
    return
  fi

  opensearch_apply_container_action down-volumes no
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
  local job_table_ident='`search_index_jobs`'
  local state_table_ident='`search_index_state`'

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
      mysql_admin "${MYSQL_DATABASE}" -e "DROP TABLE IF EXISTS ${state_table_ident}; DROP TABLE IF EXISTS ${job_table_ident};"
      mysql_admin "${MYSQL_DATABASE}" < "${INDEXER_SCHEMA_FILE}"
      log_info "Schema recreated from ${INDEXER_SCHEMA_FILE}"
      ;;
  esac
}

drop_indexer_schema() {
  local job_table_ident='`search_index_jobs`'
  local state_table_ident='`search_index_state`'

  confirm_exact "Type ${MYSQL_DATABASE} to DROP indexer schema table(s) in ${MYSQL_DATABASE}" "${MYSQL_DATABASE}"
  mysql_admin "${MYSQL_DATABASE}" -e "DROP TABLE IF EXISTS ${state_table_ident}; DROP TABLE IF EXISTS ${job_table_ident};"
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

drop_database_now() {
  local db_ident

  db_ident="$(sql_ident "${MYSQL_DATABASE}")"
  mysql_admin -e "DROP DATABASE IF EXISTS ${db_ident};"
  log_info "Dropped database: ${MYSQL_DATABASE}"
}

drop_mysql_user_now() {
  local account

  account="$(mysql_account_sql)"
  mysql_admin -e "DROP USER IF EXISTS ${account}; FLUSH PRIVILEGES;"
  log_info "Dropped MySQL user: ${MYSQL_USER}@${MYSQL_APP_HOST}"
}

db_drop() {
  validate_mysql_bootstrap_settings

  printf 'MySQL admin command: %s %s\n' "${MYSQL_ADMIN_BIN}" "${MYSQL_ADMIN_ARGS}"
  printf 'Dropping database: %s\n' "${MYSQL_DATABASE}"
  printf 'Dropping runtime user: %s@%s\n' "${MYSQL_USER}" "${MYSQL_APP_HOST}"

  drop_database_now
  drop_mysql_user_now

  log_info "MySQL database/user drop finished."
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
  remove_logs_now
}

remove_logs_now() {
  local log_dir
  log_dir="$(service_log_dir)"

  if [[ "$(id -u)" -eq 0 ]]; then
    rm -rf "${log_dir}"
  else
    sudo rm -rf "${log_dir}"
  fi
  log_info "Removed log directory: ${log_dir}"
}

uninstall_destroy() {
  printf 'Feed OpenSearch Indexer uninstall\n'
  printf 'Removing managed install state without prompts.\n'
  printf 'Project files are kept in place: %s\n' "${SERVICE_DIR}"

  uninstall_systemd
  uninstall_logrotate
  opensearch_index_delete_now
  opensearch_destroy_containers_now
  db_drop
  uninstall_service_user
  remove_logs_now

  log_info "Uninstall flow finished. Project files were not removed."
}

uninstall_interactive() {
  local systemd_action
  local logrotate_action
  local opensearch_index_action
  local opensearch_container_action
  local db_action
  local service_user_action
  local logs_action

  printf 'Feed OpenSearch Indexer uninstall\n'
  printf 'Service directory: %s\n' "${SERVICE_DIR}"
  printf 'Database: %s\n' "${MYSQL_DATABASE}"
  printf 'MySQL user: %s@%s\n' "${MYSQL_USER}" "${MYSQL_APP_HOST}"
  printf 'OpenSearch URL: %s\n' "${OPENSEARCH_URL}"
  printf 'OpenSearch index: %s\n' "${OPENSEARCH_INDEX}"
  printf 'Linux service user: %s:%s\n' "${SERVICE_USER}" "${SERVICE_GROUP}"

  systemd_action="$(prompt_choice systemd remove 'remove keep')"
  logrotate_action="$(prompt_choice logrotate remove 'remove keep')"
  opensearch_index_action="$(prompt_choice opensearch-index keep 'keep remove')"
  opensearch_container_action="$(prompt_choice opensearch-containers keep 'keep stop down down-volumes')"
  db_action="$(prompt_choice mysql keep 'keep interactive-drop drop')"
  service_user_action="$(prompt_choice service-user keep 'keep remove')"
  logs_action="$(prompt_choice logs keep 'keep remove')"

  if [[ "${systemd_action}" == "remove" ]]; then
    uninstall_systemd
  fi

  if [[ "${logrotate_action}" == "remove" ]]; then
    uninstall_logrotate
  fi

  if [[ "${opensearch_index_action}" == "remove" ]]; then
    opensearch_index_delete
  fi

  if [[ "${opensearch_container_action}" != "keep" ]]; then
    opensearch_apply_container_action "${opensearch_container_action}"
  fi

  if [[ "${db_action}" == "interactive-drop" ]]; then
    db_uninstall
  fi

  if [[ "${db_action}" == "drop" ]]; then
    db_drop
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
  local jobs_table_count
  local state_table_count
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

  jobs_table_count="$(mysql_app "${MYSQL_DATABASE}" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'search_index_jobs';")"
  if [[ "${jobs_table_count}" == "1" ]]; then
    printf 'ok   table search_index_jobs exists\n'
    queue_count="$(mysql_app "${MYSQL_DATABASE}" -N -B -e 'SELECT COUNT(*) FROM search_index_jobs;')"
    printf 'ok   queue rows=%s\n' "${queue_count}"
  else
    printf 'miss table search_index_jobs\n'
    return 1
  fi

  state_table_count="$(mysql_app "${MYSQL_DATABASE}" -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'search_index_state';")"
  if [[ "${state_table_count}" == "1" ]]; then
    printf 'ok   table search_index_state exists\n'
  else
    printf 'miss table search_index_state\n'
    return 1
  fi
}

source_status() {
  local output
  local table_name
  local failed=0

  if ! command_exists "${SOURCE_MYSQL_BIN}"; then
    log_error "source mysql command is missing: ${SOURCE_MYSQL_BIN}"
    return 1
  fi
  sql_ident "${SOURCE_MYSQL_DATABASE}" >/dev/null

  printf 'Source MySQL worker-read status\n'
  printf 'host=%s\n' "${SOURCE_MYSQL_HOST}"
  printf 'port=%s\n' "${SOURCE_MYSQL_PORT}"
  printf 'user=%s\n' "$(source_mysql_worker_user)"
  printf 'database=%s\n' "${SOURCE_MYSQL_DATABASE}"
  printf 'password_set=%s\n' "$([[ -n "$(source_mysql_worker_password)" ]] && printf yes || printf no)"

  if ! output="$(source_mysql_worker "${SOURCE_MYSQL_DATABASE}" -N -B -e 'SELECT 1;' 2>&1)"; then
    printf 'fail source login/query: %s\n' "${output}"
    return 1
  fi
  printf 'ok   source login/query\n'

  for table_name in campaign_actions campaigns_tags campaign_tags; do
    if output="$(source_mysql_worker "${SOURCE_MYSQL_DATABASE}" -N -B -e "SELECT 1 FROM \`${table_name}\` LIMIT 1;" 2>&1)"; then
      printf 'ok   source SELECT %s\n' "${table_name}"
    else
      printf 'fail source SELECT %s: %s\n' "${table_name}" "${output}"
      failed=1
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    printf 'hint grant worker source reads, for local tests:\n'
    printf "     sudo mysql -e \"GRANT SELECT ON %s.* TO '%s'@'localhost'; FLUSH PRIVILEGES;\"\n" \
      "${SOURCE_MYSQL_DATABASE}" "$(source_mysql_worker_user)"
    return 1
  fi
}

run_as_service_user() {
  if ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    return 127
  fi

  if [[ "$(id -un)" == "${SERVICE_USER}" ]]; then
    "$@"
    return
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    if command_exists runuser; then
      runuser -u "${SERVICE_USER}" -- "$@"
    elif command_exists sudo; then
      sudo -u "${SERVICE_USER}" "$@"
    else
      return 127
    fi
    return
  fi

  if command_exists sudo; then
    sudo -n -u "${SERVICE_USER}" "$@"
    return
  fi

  return 127
}

service_user_check() {
  local description="$1"
  shift

  if output="$(run_as_service_user "$@" 2>&1)"; then
    printf 'ok   %s\n' "${description}"
    return 0
  fi

  printf 'fail %s: %s\n' "${description}" "${output:-unable to run as ${SERVICE_USER}}"
  return 1
}

service_user_in_group() {
  local group_name="$1"
  id -nG "${SERVICE_USER}" | tr ' ' '\n' | grep -qx "${group_name}"
}

service_user_has_single_permission() {
  local path="$1"
  local permission="$2"
  local mode owner group owner_digit group_digit other_digit bit

  [[ -e "${path}" ]] || return 1

  case "${permission}" in
    r) bit=4 ;;
    w) bit=2 ;;
    x) bit=1 ;;
    *)
      log_error "Unknown permission check: ${permission}"
      return 1
      ;;
  esac

  mode="$(stat -Lc '%a' "${path}")"
  owner="$(stat -Lc '%U' "${path}")"
  group="$(stat -Lc '%G' "${path}")"
  mode="${mode: -3}"
  owner_digit="${mode:0:1}"
  group_digit="${mode:1:1}"
  other_digit="${mode:2:1}"

  if [[ "${owner}" == "${SERVICE_USER}" ]] && (( owner_digit & bit )); then
    return 0
  fi

  if service_user_in_group "${group}" && (( group_digit & bit )); then
    return 0
  fi

  if (( other_digit & bit )); then
    return 0
  fi

  return 1
}

service_user_can_reach_path() {
  local path="$1"
  local dir

  dir="$(dirname "${path}")"

  while [[ "${dir}" != "/" && "${dir}" != "." ]]; do
    service_user_has_single_permission "${dir}" x || return 1
    dir="$(dirname "${dir}")"
  done

  return 0
}

service_user_path_check() {
  local description="$1"
  local path="$2"
  local permission="$3"

  if service_user_can_reach_path "${path}" && service_user_has_single_permission "${path}" "${permission}"; then
    printf 'ok   %s\n' "${description}"
    return 0
  fi

  printf 'fail %s: %s lacks %s access to %s\n' "${description}" "${SERVICE_USER}" "${permission}" "${path}"
  return 1
}

service_user_import_check() {
  local module_name="$1"
  local output

  if output="$(run_as_service_user "${PYTHON_BIN}" -c "import ${module_name}" 2>&1)"; then
    printf 'ok   service user can import %s\n' "${module_name}"
    return 0
  fi

  if [[ "${output}" == *"sudo: a password is required"* \
        || "${output}" == *"no new privileges"* \
        || "${output}" == *"unable to run as"* \
        || "${output}" == "" ]]; then
    if output="$("${PYTHON_BIN}" -c "import ${module_name}" 2>&1)"; then
      printf 'ok   Python can import %s\n' "${module_name}"
      printf 'info service-user import execution skipped; no passwordless sudo/runuser from this shell\n'
      return 0
    fi
  fi

  printf 'fail service user can import %s: %s\n' "${module_name}" "${output}"
  return 1
}

runtime_access_check() {
  local module_name="$1"
  local failed=0

  printf 'Runtime file/access preflight\n'
  printf 'service_user=%s\n' "${SERVICE_USER}"
  printf 'service_group=%s\n' "${SERVICE_GROUP}"
  printf 'service_dir=%s\n' "${SERVICE_DIR}"
  printf 'config_file=%s\n' "${CONFIG_FILE}"
  printf 'log_dir=%s\n' "$(service_log_dir)"
  printf 'python_bin=%s\n' "${PYTHON_BIN}"

  if ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    printf 'fail service user exists: %s\n' "${SERVICE_USER}"
    printf 'hint run: ./feed_opensearch_ctl.sh install-service-user\n'
    return 1
  fi
  printf 'ok   service user exists\n'

  service_user_path_check "service user can traverse parent directory" "$(dirname "${SERVICE_DIR}")" x || failed=1
  service_user_path_check "service user can traverse service directory" "${SERVICE_DIR}" x || failed=1
  service_user_path_check "service user can read control script" "${SERVICE_DIR}/feed_opensearch_ctl.sh" r || failed=1
  service_user_path_check "service user can read config" "${CONFIG_FILE}" r || failed=1
  service_user_path_check "service user can write logs" "$(service_log_dir)" w || failed=1
  service_user_path_check "service user can execute Python" "${PYTHON_BIN}" x || failed=1
  service_user_import_check "${module_name}" || failed=1

  if [[ "${failed}" -ne 0 ]]; then
    printf 'hint run: ./feed_opensearch_ctl.sh fix-permissions\n'
    return 1
  fi
}

indexer_db_worker_rights_check() {
  local output
  local sql

  sql="
START TRANSACTION;
SELECT COUNT(*) FROM search_index_jobs;
UPDATE search_index_jobs SET worker_id = worker_id WHERE 1 = 0;
INSERT INTO search_index_state
  (entity_type, entity_id, index_status, last_action, last_job_id, last_job_created_at, indexed_at)
VALUES
  ('__preflight__', '__worker__', 'checked', 'U', 0, NOW(), NOW())
ON DUPLICATE KEY UPDATE updated_at = updated_at;
DELETE FROM search_index_state
WHERE entity_type = '__preflight__' AND entity_id = '__worker__';
ROLLBACK;
"

  printf 'Indexer MySQL worker-rights preflight\n'
  printf 'host=%s\n' "${MYSQL_HOST}"
  printf 'port=%s\n' "${MYSQL_PORT}"
  printf 'user=%s\n' "${MYSQL_USER}"
  printf 'database=%s\n' "${MYSQL_DATABASE}"

  if output="$(mysql_app "${MYSQL_DATABASE}" -N -B -e "${sql}" 2>&1)"; then
    printf 'ok   worker can SELECT/UPDATE queue and INSERT/DELETE state rows\n'
    return 0
  fi

  printf 'fail worker indexer DB rights: %s\n' "${output}"
  return 1
}

indexer_db_reaper_rights_check() {
  local output
  local sql

  sql="
START TRANSACTION;
SELECT COUNT(*) FROM search_index_jobs;
UPDATE search_index_jobs SET claim_id = claim_id WHERE 1 = 0;
ROLLBACK;
"

  printf 'Indexer MySQL reaper-rights preflight\n'
  printf 'host=%s\n' "${MYSQL_HOST}"
  printf 'port=%s\n' "${MYSQL_PORT}"
  printf 'user=%s\n' "${MYSQL_USER}"
  printf 'database=%s\n' "${MYSQL_DATABASE}"

  if output="$(mysql_app "${MYSQL_DATABASE}" -N -B -e "${sql}" 2>&1)"; then
    printf 'ok   reaper can SELECT/UPDATE queue rows\n'
    return 0
  fi

  printf 'fail reaper indexer DB rights: %s\n' "${output}"
  return 1
}

worker_opensearch_check() {
  local root_code
  local index_code

  printf 'OpenSearch worker preflight\n'
  printf 'url=%s\n' "${OPENSEARCH_URL}"
  printf 'index=%s\n' "${OPENSEARCH_INDEX}"

  root_code="$(opensearch_status_code GET "/")"
  if [[ "${root_code}" == "200" ]]; then
    printf 'ok   OpenSearch endpoint reachable\n'
  else
    printf 'fail OpenSearch endpoint reachable: http_status=%s\n' "${root_code}"
    return 1
  fi

  index_code="$(opensearch_status_code HEAD "/${OPENSEARCH_INDEX}")"
  if [[ "${index_code}" == "200" ]]; then
    printf 'ok   OpenSearch index exists\n'
    return 0
  fi

  printf 'fail OpenSearch index exists: http_status=%s\n' "${index_code}"
  printf 'hint run: ./feed_opensearch_ctl.sh opensearch:index:create\n'
  return 1
}

worker_check() {
  local failed=0

  printf 'Feed OpenSearch worker preflight\n'
  runtime_access_check app.worker || failed=1
  printf '\n'
  indexer_db_worker_rights_check || failed=1
  printf '\n'
  source_status || failed=1
  printf '\n'
  worker_opensearch_check || failed=1

  if [[ "${failed}" -ne 0 ]]; then
    printf '\nWorker preflight failed.\n'
    return 1
  fi

  printf '\nWorker preflight passed.\n'
}

reaper_check() {
  local failed=0

  printf 'Feed OpenSearch reaper preflight\n'
  runtime_access_check app.reaper || failed=1
  printf '\n'
  indexer_db_reaper_rights_check || failed=1

  if [[ "${failed}" -ne 0 ]]; then
    printf '\nReaper preflight failed.\n'
    return 1
  fi

  printf '\nReaper preflight passed.\n'
}

print_config() {
  cat <<EOF
service_dir=${SERVICE_DIR}
config_file=${CONFIG_FILE}
compose_file=${COMPOSE_FILE}
venv_dir=${VENV_DIR}
requirements_file=${REQUIREMENTS_FILE}
python_bin=${PYTHON_BIN}
bash_bin=${BASH_BIN}
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
docker_bin=${DOCKER_BIN}
source_mysql_host=${SOURCE_MYSQL_HOST}
source_mysql_port=${SOURCE_MYSQL_PORT}
source_mysql_user=${SOURCE_MYSQL_USER}
source_mysql_password_set=$([[ -n "${SOURCE_MYSQL_PASSWORD}" ]] && printf yes || printf no)
source_mysql_database=${SOURCE_MYSQL_DATABASE}
source_mysql_bin=${SOURCE_MYSQL_BIN}
source_mysql_sudo=${SOURCE_MYSQL_SUDO}
service_user=${SERVICE_USER}
service_group=${SERVICE_GROUP}
opensearch_url=${OPENSEARCH_URL}
opensearch_index=${OPENSEARCH_INDEX}
opensearch_username_set=$([[ -n "${OPENSEARCH_USERNAME}" ]] && printf yes || printf no)
opensearch_password_set=$([[ -n "${OPENSEARCH_PASSWORD}" ]] && printf yes || printf no)
opensearch_timeout_seconds=${OPENSEARCH_TIMEOUT_SECONDS}
opensearch_wait_seconds=${OPENSEARCH_WAIT_SECONDS}
opensearch_loader_page_size=${OPENSEARCH_LOADER_PAGE_SIZE}
opensearch_index_file=${OPENSEARCH_INDEX_FILE}
opensearch_discovery_query_file=${OPENSEARCH_DISCOVERY_QUERY_FILE}
opensearch_full_index_sql_file=${OPENSEARCH_FULL_INDEX_SQL_FILE}
indexer_schema_file=${INDEXER_SCHEMA_FILE}
log_file=${LOG_FILE}
log_dir=$(service_log_dir)
worker_batch_size=${WORKER_BATCH_SIZE}
worker_claim_strategy=${WORKER_CLAIM_STRATEGY}
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

doctor_check_docker_access() {
  if ! command_exists "${DOCKER_BIN}"; then
    printf 'miss command %s\n' "${DOCKER_BIN}"
    return
  fi

  printf 'ok   command %s -> %s\n' "${DOCKER_BIN}" "$(command -v "${DOCKER_BIN}")"

  if docker_has_direct_access; then
    printf 'ok   docker API access for current user\n'
    return
  fi

  if docker_has_sudo_access; then
    printf 'ok   docker API access via sudo\n'
    return
  fi

  printf 'warn docker API access denied for current user\n'
  printf 'hint add user to docker group and reconnect, or allow sudo docker\n'
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

doctor_check_service_config_access() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    return
  fi

  if ! command_exists stat || ! command_exists id; then
    return
  fi

  if ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    return
  fi

  local mode owner group owner_digit group_digit other_digit
  mode="$(stat -c '%a' "${CONFIG_FILE}")"
  owner="$(stat -c '%U' "${CONFIG_FILE}")"
  group="$(stat -c '%G' "${CONFIG_FILE}")"
  mode="${mode: -3}"
  owner_digit="${mode:0:1}"
  group_digit="${mode:1:1}"
  other_digit="${mode:2:1}"

  if [[ "${owner}" == "${SERVICE_USER}" ]] && (( owner_digit & 4 )); then
    printf 'ok   config readable by service user %s\n' "${SERVICE_USER}"
    return
  fi

  if id -nG "${SERVICE_USER}" | tr ' ' '\n' | grep -qx "${group}" && (( group_digit & 4 )); then
    printf 'ok   config readable by service user %s via group %s\n' "${SERVICE_USER}" "${group}"
    return
  fi

  if (( other_digit & 4 )); then
    printf 'ok   config readable by service user %s via other-read\n' "${SERVICE_USER}"
    return
  fi

  printf 'miss config readable by service user %s\n' "${SERVICE_USER}"
  printf 'hint run: ./feed_opensearch_ctl.sh fix-permissions\n'
}

doctor_check_service_parent_access() {
  local service_parent mode owner group owner_digit group_digit other_digit
  service_parent="$(dirname "${SERVICE_DIR}")"

  if [[ "${service_parent}" == "/" || "${service_parent}" == "." ]]; then
    return
  fi

  if ! command_exists stat || ! command_exists id; then
    return
  fi

  if ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
    return
  fi

  mode="$(stat -c '%a' "${service_parent}")"
  owner="$(stat -c '%U' "${service_parent}")"
  group="$(stat -c '%G' "${service_parent}")"
  mode="${mode: -3}"
  owner_digit="${mode:0:1}"
  group_digit="${mode:1:1}"
  other_digit="${mode:2:1}"

  if [[ "${owner}" == "${SERVICE_USER}" ]] && (( owner_digit & 1 )); then
    printf 'ok   service user %s can traverse %s\n' "${SERVICE_USER}" "${service_parent}"
    return
  fi

  if id -nG "${SERVICE_USER}" | tr ' ' '\n' | grep -qx "${group}" && (( group_digit & 1 )); then
    printf 'ok   service user %s can traverse %s via group %s\n' "${SERVICE_USER}" "${service_parent}" "${group}"
    return
  fi

  if (( other_digit & 1 )); then
    printf 'ok   service user %s can traverse %s via other-execute\n' "${SERVICE_USER}" "${service_parent}"
    return
  fi

  printf 'miss service user %s can traverse %s\n' "${SERVICE_USER}" "${service_parent}"
  printf 'hint run: ./feed_opensearch_ctl.sh fix-permissions\n'
}

doctor_check_password() {
  if [[ -n "${MYSQL_PASSWORD}" ]]; then
    printf 'ok   MYSQL_PASSWORD is set\n'
  else
    printf 'warn MYSQL_PASSWORD is empty\n'
  fi

  if [[ "${SOURCE_MYSQL_SUDO}" == "1" || "${SOURCE_MYSQL_SUDO}" == "true" || "${SOURCE_MYSQL_SUDO}" == "yes" ]]; then
    printf 'ok   SOURCE_MYSQL_SUDO enabled for source DB reads\n'
  elif [[ -n "${SOURCE_MYSQL_USER}" ]]; then
    printf 'ok   SOURCE_MYSQL_USER is set\n'
  else
    printf 'warn SOURCE_MYSQL_USER is empty; loader requires SOURCE_MYSQL_USER or SOURCE_MYSQL_SUDO=1\n'
  fi
}

doctor_check_source_mysql_access() {
  local output

  DOCTOR_SOURCE_MYSQL_OK=0

  if ! command_exists "${SOURCE_MYSQL_BIN}"; then
    printf 'miss source mysql command %s\n' "${SOURCE_MYSQL_BIN}"
    return
  fi

  if [[ ! "${SOURCE_MYSQL_DATABASE}" =~ ^[A-Za-z0-9_]+$ ]]; then
    printf 'warn source database name is unsafe for preflight: %s\n' "${SOURCE_MYSQL_DATABASE}"
    return
  fi

  if output="$(source_mysql_worker "${SOURCE_MYSQL_DATABASE}" -N -B -e \
      'SELECT 1 FROM `campaign_actions` LIMIT 1; SELECT 1 FROM `campaigns_tags` LIMIT 1; SELECT 1 FROM `campaign_tags` LIMIT 1;' 2>&1)"; then
    printf 'ok   source worker read access for campaign action documents\n'
    DOCTOR_SOURCE_MYSQL_OK=1
  else
    printf 'warn source worker read access failed: %s\n' "${output}"
    printf 'hint run: ./feed_opensearch_ctl.sh source:status\n'
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

doctor_check_service_instances() {
  local unit
  local state
  local i
  local failed=0

  DOCTOR_SERVICE_INSTANCES_OK=1

  if ! command_exists systemctl; then
    DOCTOR_SERVICE_INSTANCES_OK=0
    return
  fi

  validate_instance_counts

  for (( i = 1; i <= WORKER_COUNT; i++ )); do
    unit="$(worker_instance_unit "${i}")"
    if systemctl is-active --quiet "${unit}"; then
      printf 'ok   systemd instance active %s\n' "${unit}"
    else
      state="$(systemctl is-active "${unit}" 2>/dev/null || true)"
      printf 'warn systemd instance not active %s state=%s\n' "${unit}" "${state:-unknown}"
      failed=1
    fi
  done

  for (( i = 1; i <= REAPER_COUNT; i++ )); do
    unit="$(reaper_instance_unit "${i}")"
    if systemctl is-active --quiet "${unit}"; then
      printf 'ok   systemd instance active %s\n' "${unit}"
    else
      state="$(systemctl is-active "${unit}" 2>/dev/null || true)"
      printf 'warn systemd instance not active %s state=%s\n' "${unit}" "${state:-unknown}"
      failed=1
    fi
  done

  if [[ "${failed}" -ne 0 ]]; then
    DOCTOR_SERVICE_INSTANCES_OK=0
  fi
}

doctor() {
  printf 'Feed OpenSearch Indexer doctor\n'
  DOCTOR_SERVICE_INSTANCES_OK=0
  DOCTOR_SOURCE_MYSQL_OK=0
  printf 'os_family=%s\n' "$(detect_os_family)"
  printf 'package_manager=%s\n' "$(package_manager)"
  doctor_check_command python3
  if command_exists python3; then
    doctor_check_python_venv_module
  fi
  doctor_check_command "${MYSQL_BIN}"
  if [[ "${SOURCE_MYSQL_BIN}" != "${MYSQL_BIN}" ]]; then
    doctor_check_command "${SOURCE_MYSQL_BIN}"
  fi
  if [[ "${MYSQL_ADMIN_BIN}" != "${MYSQL_BIN}" ]]; then
    doctor_check_command "${MYSQL_ADMIN_BIN}"
  fi
  doctor_check_command curl
  doctor_check_command systemctl
  doctor_check_command logrotate
  doctor_check_docker_access
  doctor_check_password
  doctor_check_source_mysql_access
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
  doctor_check_service_parent_access
  doctor_check_service_config_access
  doctor_check_file requirements "${REQUIREMENTS_FILE}"
  doctor_check_file indexer_schema "${INDEXER_SCHEMA_FILE}"
  doctor_check_file compose "${COMPOSE_FILE}"
  doctor_check_file opensearch_index "${OPENSEARCH_INDEX_FILE}"
  doctor_check_file opensearch_query "${OPENSEARCH_DISCOVERY_QUERY_FILE}"
  doctor_check_file opensearch_full_index_sql "${OPENSEARCH_FULL_INDEX_SQL_FILE}"
  if [[ -x "${VENV_DIR}/bin/python" ]]; then
    printf 'ok   venv python %s\n' "${VENV_DIR}/bin/python"
  else
    printf 'miss venv python %s\n' "${VENV_DIR}/bin/python"
  fi
  doctor_check_service "$(worker_template_unit)"
  doctor_check_service "$(reaper_template_unit)"
  doctor_check_service_instances
  printf 'configured workers=%s
' "${WORKER_COUNT}"
  printf 'configured reapers=%s
' "${REAPER_COUNT}"
  doctor_next_steps
}

doctor_next_steps() {
  local printed=0

  maybe_print_next_step() {
    if [[ "${printed}" -eq 0 ]]; then
      printf '\nNext steps:\n'
      printed=1
    fi
    printf '  - %s\n' "$1"
  }

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    maybe_print_next_step 'Create config: ./feed_opensearch_ctl.sh init-config or ./feed_opensearch_ctl.sh configure'
  fi

  if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    maybe_print_next_step 'Create Python venv: ./feed_opensearch_ctl.sh setup-venv'
  fi

  if command_exists docker && ! opensearch_index_exists; then
    maybe_print_next_step 'Optional local OpenSearch if using bundled Docker: ./feed_opensearch_ctl.sh opensearch:install && ./feed_opensearch_ctl.sh opensearch:index:create'
  fi

  if ! command_exists docker; then
    maybe_print_next_step 'Docker is optional unless using bundled local OpenSearch. For production, external OpenSearch can be configured later.'
  fi

  if ! command_exists "${MYSQL_BIN}"; then
    maybe_print_next_step 'MySQL is external to this installer; install/provide mysql client before running DB commands.'
  fi

  if [[ -z "${MYSQL_PASSWORD}" ]]; then
    maybe_print_next_step 'Set MYSQL_PASSWORD before db:install creates/updates the runtime MySQL user.'
  fi

  if command_exists systemctl; then
    if ! systemctl list-unit-files "$(worker_template_unit)" >/dev/null 2>&1 \
      || ! systemctl list-unit-files "$(reaper_template_unit)" >/dev/null 2>&1; then
      maybe_print_next_step 'Install services after config/venv: ./feed_opensearch_ctl.sh install-systemd'
    elif [[ "${DOCTOR_SERVICE_INSTANCES_OK:-0}" != "1" ]]; then
      maybe_print_next_step 'One or more service instances are not active: ./feed_opensearch_ctl.sh services:status && ./feed_opensearch_ctl.sh services:logs'
    fi
  fi

  if [[ "${DOCTOR_SOURCE_MYSQL_OK:-0}" != "1" ]]; then
    maybe_print_next_step 'Grant/check source DB reads for the worker: ./feed_opensearch_ctl.sh source:status'
  fi

  if [[ "${printed}" -eq 0 ]]; then
    printf '\nInstall checks look complete. No recommended next steps.\n'
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
    db:drop)
      db_drop
      ;;
    db:schema)
      db_schema
      ;;
    db:status)
      db_status
      ;;
    source:status)
      source_status
      ;;
    show-db-sql)
      show_db_sql
      ;;
    install-systemd)
      install_systemd
      ;;
    uninstall)
      uninstall_destroy
      ;;
    uninstall-interactive)
      uninstall_interactive
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
    opensearch:install)
      opensearch_install
      ;;
    opensearch:uninstall)
      opensearch_uninstall
      ;;
    opensearch:start)
      require_docker
      require_compose_file
      compose up -d
      ;;
    opensearch:stop)
      require_docker
      require_compose_file
      compose stop
      ;;
    opensearch:restart)
      require_docker
      require_compose_file
      compose restart
      ;;
    opensearch:status)
      require_docker
      require_compose_file
      compose ps
      ;;
    opensearch:logs)
      require_docker
      require_compose_file
      compose logs -f
      ;;
    opensearch:health)
      opensearch_health
      ;;
    opensearch:index:create)
      opensearch_index_create
      ;;
    opensearch:index:reset)
      opensearch_index_reset
      ;;
    opensearch:index:delete)
      opensearch_index_delete
      ;;
    opensearch:index:show)
      opensearch_index_show
      ;;
    opensearch:load:dry-run)
      opensearch_load_dry_run
      ;;
    opensearch:load)
      opensearch_load
      ;;
    opensearch:rebuild)
      opensearch_rebuild
      ;;
    worker:run)
      ensure_log_dir
      "${PYTHON_BIN}" -m app.worker
      ;;
    worker:check)
      worker_check
      ;;
    reaper:run)
      ensure_log_dir
      "${PYTHON_BIN}" -m app.reaper
      ;;
    reaper:check)
      reaper_check
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
    worker:logs:follow)
      require_systemctl
      for_worker_instances journal_unit_follow_action
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
    reaper:logs:follow)
      require_systemctl
      for_reaper_instances journal_unit_follow_action
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
    services:logs:follow)
      require_systemctl
      journal_services_follow
      ;;
    *)
      log_error "Unknown command: ${command}"
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
