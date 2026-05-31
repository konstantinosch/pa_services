#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${FEED_RAM_CONFIG:-${SERVICE_DIR}/config.env}"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

DB_NAME="${DB_NAME:-deedspot}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQL_ARGS="${MYSQL_ARGS:-}"
FEED_RAM_LOG_DIR="${FEED_RAM_LOG_DIR:-logs}"

FEED_RAM_CAMPAIGN_ACTIONS_RECENT_DAYS="${FEED_RAM_CAMPAIGN_ACTIONS_RECENT_DAYS:-200}"
FEED_RAM_CAMPAIGN_ACTIONS_TARGET_BYTES="${FEED_RAM_CAMPAIGN_ACTIONS_TARGET_BYTES:-134217728}"
FEED_RAM_CAMPAIGN_ACTIONS_SAFETY_PCT="${FEED_RAM_CAMPAIGN_ACTIONS_SAFETY_PCT:-90}"
FEED_RAM_CAMPAIGN_ACTIONS_ESTIMATED_BYTES_PER_ROW="${FEED_RAM_CAMPAIGN_ACTIONS_ESTIMATED_BYTES_PER_ROW:-150}"
FEED_RAM_CAMPAIGN_ACTIONS_CRON="${FEED_RAM_CAMPAIGN_ACTIONS_CRON:-*/5 * * * *}"

FEED_RAM_HYDRATED_ACTIONS_RECENT_DAYS="${FEED_RAM_HYDRATED_ACTIONS_RECENT_DAYS:-30}"
FEED_RAM_HYDRATED_ACTIONS_TARGET_BYTES="${FEED_RAM_HYDRATED_ACTIONS_TARGET_BYTES:-268435456}"
FEED_RAM_HYDRATED_ACTIONS_SAFETY_PCT="${FEED_RAM_HYDRATED_ACTIONS_SAFETY_PCT:-90}"
FEED_RAM_HYDRATED_ACTIONS_ESTIMATED_BYTES_PER_ROW="${FEED_RAM_HYDRATED_ACTIONS_ESTIMATED_BYTES_PER_ROW:-1200}"
FEED_RAM_HYDRATED_ACTIONS_CRON="${FEED_RAM_HYDRATED_ACTIONS_CRON:-*/5 * * * *}"

MARKER_PREFIX="praxi_agapis_feed"
MARKER_CAMPAIGN_ACTIONS="# ${MARKER_PREFIX}:campaign_actions"
MARKER_HYDRATED_ACTIONS="# ${MARKER_PREFIX}:hydrated_actions"

log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_timestamp)" "$*"
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_timestamp)" "$*" >&2
}

print_usage() {
  cat <<'USAGE'
Usage:
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh help
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh init-ram-state
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh campaign_actions|hydrated_actions|all
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh status campaign_actions|hydrated_actions|ram_state|all
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh config
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh drop campaign_actions|hydrated_actions|ram_state|all
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh install-cron campaign_actions|hydrated_actions|all
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh uninstall-cron campaign_actions|hydrated_actions|all
  /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh show-cron

Configuration:
  Edit config.env in the service directory.
  Set FEED_RAM_CONFIG=/path/to/config.env to load a different config file.

Cron markers live on the managed cron line:
  # praxi_agapis_feed:campaign_actions
  # praxi_agapis_feed:hydrated_actions
USAGE
}

run_mysql_file() {
  local sql_file="$1"

  if [[ ! -f "${sql_file}" ]]; then
    log_error "Missing SQL file: ${sql_file}"
    exit 1
  fi

  # MYSQL_ARGS is intentionally word-split so config can provide simple flags.
  # shellcheck disable=SC2086
  "${MYSQL_BIN}" ${MYSQL_ARGS} "${DB_NAME}" < "${sql_file}"
}

run_mysql_file_with_model_config() {
  local model="$1"
  local sql_file="$2"

  if [[ ! -f "${sql_file}" ]]; then
    log_error "Missing SQL file: ${sql_file}"
    exit 1
  fi

  {
    printf 'SET @recent_days = %s;\n' "$(model_recent_days "${model}")"
    printf 'SET @ram_heap_target_bytes = %s;\n' "$(model_target_bytes "${model}")"
    printf 'SET @ram_heap_safety_pct = %s;\n' "$(model_safety_pct "${model}")"
    printf 'SET @ram_estimated_bytes_per_row = %s;\n' "$(model_estimated_bytes_per_row "${model}")"
    cat "${sql_file}"
  } | {
    # MYSQL_ARGS is intentionally word-split so config can provide simple flags.
    # shellcheck disable=SC2086
    "${MYSQL_BIN}" ${MYSQL_ARGS} "${DB_NAME}"
  }
}

run_mysql_statement() {
  local statement="$1"

  # MYSQL_ARGS is intentionally word-split so config can provide simple flags.
  # shellcheck disable=SC2086
  "${MYSQL_BIN}" ${MYSQL_ARGS} "${DB_NAME}" -e "${statement}"
}

run_mysql_scalar() {
  local statement="$1"

  # MYSQL_ARGS is intentionally word-split so config can provide simple flags.
  # shellcheck disable=SC2086
  "${MYSQL_BIN}" ${MYSQL_ARGS} --batch --skip-column-names "${DB_NAME}" -e "${statement}"
}

init_ram_state() {
  validate_config
  log_info "Recreating ram_state."
  run_mysql_file "${SERVICE_DIR}/sql/ram_state.sql"
  log_info "Recreated ram_state."
}

ensure_ram_state() {
  validate_config
  run_mysql_file "${SERVICE_DIR}/sql/ensure_ram_state.sql"
}

ram_table_for_model() {
  local model="$1"

  case "${model}" in
    ram_state)
      printf '%s\n' "ram_state"
      ;;
    campaign_actions)
      printf '%s\n' "ram_campaign_actions"
      ;;
    hydrated_actions)
      printf '%s\n' "ram_hydrated_actions"
      ;;
    *)
      log_error "Unknown RAM model: ${model}"
      exit 1
      ;;
  esac
}

state_name_for_model() {
  local model="$1"

  case "${model}" in
    ram_state)
      printf '%s\n' ""
      ;;
    campaign_actions)
      printf '%s\n' "campaign_actions"
      ;;
    hydrated_actions)
      printf '%s\n' "hydrated_actions"
      ;;
    *)
      log_error "Unknown RAM model: ${model}"
      exit 1
      ;;
  esac
}

drop_ram_model() {
  validate_config
  local model="$1"
  local table_name
  local state_name

  log_info "Drop requested for ${model}."

  table_name="$(ram_table_for_model "${model}")"
  state_name="$(state_name_for_model "${model}")"

  if [[ "${model}" == "ram_state" ]]; then
    run_mysql_statement "DROP TABLE IF EXISTS ram_state;"
    log_info "Dropped RAM state table ram_state."
    return
  fi

  ensure_ram_state
  run_mysql_statement "DROP TABLE IF EXISTS ${table_name}; DELETE FROM ram_state WHERE name = '${state_name}';"
  log_info "Dropped RAM table ${table_name} and cleared ram_state:${state_name}."
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

validate_pct() {
  local name="$1"
  local value="$2"

  if ! positive_int "${value}" || (( value < 1 || value > 100 )); then
    log_error "Invalid ${name}: expected integer from 1 to 100, got '${value}'."
    exit 1
  fi
}

validate_nonempty() {
  local name="$1"
  local value="$2"

  if [[ -z "${value}" ]]; then
    log_error "Invalid ${name}: value cannot be empty."
    exit 1
  fi
}

model_recent_days() {
  case "$1" in
    campaign_actions) printf '%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_RECENT_DAYS}" ;;
    hydrated_actions) printf '%s\n' "${FEED_RAM_HYDRATED_ACTIONS_RECENT_DAYS}" ;;
    *) log_error "Unknown config model: $1"; exit 1 ;;
  esac
}

model_target_bytes() {
  case "$1" in
    campaign_actions) printf '%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_TARGET_BYTES}" ;;
    hydrated_actions) printf '%s\n' "${FEED_RAM_HYDRATED_ACTIONS_TARGET_BYTES}" ;;
    *) log_error "Unknown config model: $1"; exit 1 ;;
  esac
}

model_safety_pct() {
  case "$1" in
    campaign_actions) printf '%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_SAFETY_PCT}" ;;
    hydrated_actions) printf '%s\n' "${FEED_RAM_HYDRATED_ACTIONS_SAFETY_PCT}" ;;
    *) log_error "Unknown config model: $1"; exit 1 ;;
  esac
}

model_estimated_bytes_per_row() {
  case "$1" in
    campaign_actions) printf '%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_ESTIMATED_BYTES_PER_ROW}" ;;
    hydrated_actions) printf '%s\n' "${FEED_RAM_HYDRATED_ACTIONS_ESTIMATED_BYTES_PER_ROW}" ;;
    *) log_error "Unknown config model: $1"; exit 1 ;;
  esac
}

model_row_cap() {
  local model="$1"
  local target_bytes
  local safety_pct
  local estimated_bytes_per_row

  target_bytes="$(model_target_bytes "${model}")"
  safety_pct="$(model_safety_pct "${model}")"
  estimated_bytes_per_row="$(model_estimated_bytes_per_row "${model}")"
  printf '%s\n' "$(( target_bytes * safety_pct / 100 / estimated_bytes_per_row ))"
}

validate_config_model() {
  local model="$1"

  validate_positive_int "${model}.recent_days" "$(model_recent_days "${model}")"
  validate_positive_int "${model}.target_bytes" "$(model_target_bytes "${model}")"
  validate_pct "${model}.safety_pct" "$(model_safety_pct "${model}")"
  validate_positive_int "${model}.estimated_bytes_per_row" "$(model_estimated_bytes_per_row "${model}")"
  validate_positive_int "${model}.row_cap" "$(model_row_cap "${model}")"
}

validate_config() {
  validate_nonempty "DB_NAME" "${DB_NAME}"
  validate_nonempty "MYSQL_BIN" "${MYSQL_BIN}"
  validate_nonempty "FEED_RAM_LOG_DIR" "${FEED_RAM_LOG_DIR}"
  validate_nonempty "FEED_RAM_CAMPAIGN_ACTIONS_CRON" "${FEED_RAM_CAMPAIGN_ACTIONS_CRON:-}"
  validate_nonempty "FEED_RAM_HYDRATED_ACTIONS_CRON" "${FEED_RAM_HYDRATED_ACTIONS_CRON:-}"
  validate_config_model campaign_actions
  validate_config_model hydrated_actions
}

print_model_config() {
  local model="$1"

  printf '%s\n' "${model}:"
  printf '  table=%s\n' "$(ram_table_for_model "${model}")"
  printf '  state_name=%s\n' "$(state_name_for_model "${model}")"
  printf '  recent_days=%s\n' "$(model_recent_days "${model}")"
  printf '  target_bytes=%s\n' "$(model_target_bytes "${model}")"
  printf '  safety_pct=%s\n' "$(model_safety_pct "${model}")"
  printf '  estimated_bytes_per_row=%s\n' "$(model_estimated_bytes_per_row "${model}")"
  printf '  row_cap=%s\n' "$(model_row_cap "${model}")"
}

print_config() {
  validate_config
  printf 'config_file=%s\n' "${CONFIG_FILE}"
  printf 'db_name=%s\n' "${DB_NAME}"
  printf 'mysql_bin=%s\n' "${MYSQL_BIN}"
  printf 'mysql_args=%s\n' "${MYSQL_ARGS}"
  printf 'log_dir=%s\n' "$(service_log_dir)"
  printf 'campaign_actions_cron=%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_CRON}"
  printf 'hydrated_actions_cron=%s\n' "${FEED_RAM_HYDRATED_ACTIONS_CRON}"
  print_model_config campaign_actions
  print_model_config hydrated_actions
}

ensure_log_dir() {
  mkdir -p "$(service_log_dir)"
}

table_exists() {
  local table_name="$1"

  [[ "$(run_mysql_scalar "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${table_name}';")" == "1" ]]
}

status_model() {
  local model="$1"
  local table_name
  local state_name

  table_name="$(ram_table_for_model "${model}")"
  state_name="$(state_name_for_model "${model}")"

  printf '%s\n' "${model}:"
  run_mysql_statement "SELECT TABLE_NAME AS table_name, ENGINE AS engine, TABLE_ROWS AS approx_rows, DATA_LENGTH AS data_bytes, INDEX_LENGTH AS index_bytes, CREATE_TIME AS created_at, UPDATE_TIME AS updated_at FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${table_name}';"

  if [[ "${model}" != "ram_state" ]] && table_exists ram_state; then
    run_mysql_statement "SELECT name, refreshed_at, recent_days, rows_count, min_created_at, max_created_at, ram_heap_target_bytes, ram_row_cap FROM ram_state WHERE name = '${state_name}';"
  fi
}

status_models() {
  local model="${1:-all}"
  validate_config
  for_each_ram_model status_model "${model}"
}


lock_name_for_model() {
  local model="$1"

  case "${model}" in
    campaign_actions)
      printf '%s\n' "praxi_agapis_feed:ram_campaign_actions"
      ;;
    hydrated_actions)
      printf '%s\n' "praxi_agapis_feed:ram_hydrated_actions"
      ;;
    *)
      log_error "Unknown lock model: ${model}"
      exit 1
      ;;
  esac
}

run_refresh_file_with_lock() {
  local model="$1"
  local sql_file="$2"
  local lock_name
  local got_lock
  local rc

  lock_name="$(lock_name_for_model "${model}")"
  log_info "Refresh requested for ${model}; waiting for advisory lock ${lock_name}."
  got_lock="$(run_mysql_scalar "SELECT GET_LOCK('${lock_name}', 30);")"

  if [[ "${got_lock}" != "1" ]]; then
    log_error "Could not acquire advisory lock: ${lock_name}"
    exit 1
  fi

  log_info "Acquired advisory lock ${lock_name}; running ${sql_file}."
  set +e
  run_mysql_file_with_model_config "${model}" "${sql_file}"
  rc=$?
  if run_mysql_scalar "SELECT RELEASE_LOCK('${lock_name}');" >/dev/null; then
    log_info "Released advisory lock ${lock_name}."
  else
    log_error "Failed to release advisory lock ${lock_name}."
  fi
  set -e

  if (( rc != 0 )); then
    log_error "Refresh failed for ${model}."
    exit "${rc}"
  fi

  log_info "Refresh completed for ${model}."
}

refresh_campaign_actions() {
  ensure_ram_state
  run_refresh_file_with_lock campaign_actions "${SERVICE_DIR}/sql/refresh_campaign_actions.sql"
}

refresh_hydrated_actions() {
  ensure_ram_state
  run_refresh_file_with_lock hydrated_actions "${SERVICE_DIR}/sql/refresh_hydrated_actions.sql"
}

refresh_model() {
  validate_config
  local model="$1"

  case "${model}" in
    campaign_actions)
      refresh_campaign_actions
      ;;
    hydrated_actions)
      refresh_hydrated_actions
      ;;
    all)
      refresh_campaign_actions
      refresh_hydrated_actions
      ;;
    *)
      log_error "Unknown refresh model: ${model}"
      print_usage >&2
      exit 1
      ;;
  esac
}

cron_marker_for_model() {
  local model="$1"

  case "${model}" in
    campaign_actions)
      printf '%s\n' "${MARKER_CAMPAIGN_ACTIONS}"
      ;;
    hydrated_actions)
      printf '%s\n' "${MARKER_HYDRATED_ACTIONS}"
      ;;
    *)
      log_error "Unknown cron model: ${model}"
      exit 1
      ;;
  esac
}

cron_schedule_for_model() {
  local model="$1"

  case "${model}" in
    campaign_actions)
      printf '%s\n' "${FEED_RAM_CAMPAIGN_ACTIONS_CRON:-*/5 * * * *}"
      ;;
    hydrated_actions)
      printf '%s\n' "${FEED_RAM_HYDRATED_ACTIONS_CRON:-*/5 * * * *}"
      ;;
    *)
      log_error "Unknown cron model: ${model}"
      exit 1
      ;;
  esac
}

service_log_dir() {
  case "${FEED_RAM_LOG_DIR}" in
    /*)
      printf '%s\n' "${FEED_RAM_LOG_DIR}"
      ;;
    *)
      printf '%s\n' "${SERVICE_DIR}/${FEED_RAM_LOG_DIR}"
      ;;
  esac
}

cron_log_for_model() {
  local model="$1"

  case "${model}" in
    campaign_actions)
      printf '%s\n' "$(service_log_dir)/pa_campaign_actions.log"
      ;;
    hydrated_actions)
      printf '%s\n' "$(service_log_dir)/pa_hydrated_actions.log"
      ;;
    *)
      log_error "Unknown cron model: ${model}"
      exit 1
      ;;
  esac
}

cron_command_for_model() {
  local model="$1"
  local log_file
  local marker

  log_file="$(cron_log_for_model "${model}")"
  marker="$(cron_marker_for_model "${model}")"
  printf '%s %s refresh %s >> %s 2>&1 %s\n' \
    "$(cron_schedule_for_model "${model}")" \
    "${SERVICE_DIR}/feed_ram_ctl.sh" \
    "${model}" \
    "${log_file}" \
    "${marker}"
}

current_cron() {
  crontab -l 2>/dev/null || true
}

remove_model_cron_from_stream() {
  local model="$1"
  local marker

  marker="$(cron_marker_for_model "${model}")"
  grep -Fv "${marker}" || true
}

install_cron_model() {
  validate_config
  ensure_log_dir
  local model="$1"
  local command
  local updated

  command="$(cron_command_for_model "${model}")"
  log_info "Installing cron for ${model}: ${command}"
  updated="$(current_cron | remove_model_cron_from_stream "${model}")"
  {
    printf '%s\n' "${updated}"
    printf '%s\n' "${command}"
  } | sed '/^$/N;/^\n$/D' | crontab -
}

uninstall_cron_model() {
  validate_config
  local model="$1"

  log_info "Uninstalling cron for ${model}."
  current_cron | remove_model_cron_from_stream "${model}" | crontab -
}

for_each_ram_model() {
  local action="$1"
  local model="$2"

  case "${model}" in
    campaign_actions|hydrated_actions|ram_state)
      "${action}" "${model}"
      ;;
    all)
      "${action}" campaign_actions
      "${action}" hydrated_actions
      "${action}" ram_state
      ;;
    *)
      log_error "Unknown RAM model: ${model}"
      print_usage >&2
      exit 1
      ;;
  esac
}

for_each_cron_model() {
  local action="$1"
  local model="$2"

  case "${model}" in
    campaign_actions|hydrated_actions)
      "${action}" "${model}"
      ;;
    all)
      "${action}" campaign_actions
      "${action}" hydrated_actions
      ;;
    *)
      log_error "Unknown cron model: ${model}"
      print_usage >&2
      exit 1
      ;;
  esac
}

show_cron() {
  current_cron | grep -F "# ${MARKER_PREFIX}:" || true
}

main() {
  local command="${1:-help}"
  local model="${2:-}"

  case "${command}" in
    help|-h|--help)
      print_usage
      ;;
    init-ram-state)
      init_ram_state
      ;;
    refresh)
      [[ -n "${model}" ]] || { print_usage >&2; exit 1; }
      refresh_model "${model}"
      ;;
    status)
      status_models "${model:-all}"
      ;;
    config)
      print_config
      ;;
    drop)
      [[ -n "${model}" ]] || { print_usage >&2; exit 1; }
      for_each_ram_model drop_ram_model "${model}"
      ;;
    install-cron)
      [[ -n "${model}" ]] || { print_usage >&2; exit 1; }
      for_each_cron_model install_cron_model "${model}"
      ;;
    uninstall-cron)
      [[ -n "${model}" ]] || { print_usage >&2; exit 1; }
      for_each_cron_model uninstall_cron_model "${model}"
      ;;
    show-cron)
      show_cron
      ;;
    *)
      log_error "Unknown command: ${command}"
      print_usage >&2
      exit 1
      ;;
  esac
}

main "$@"
