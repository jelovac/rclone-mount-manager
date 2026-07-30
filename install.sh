#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="rclone-mount-manager"
SHORT_NAME="rclone-mount"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

MODE=""
ENABLE_SERVICE=false
START_SERVICE=false
FORCE=false
DRY_RUN=false
INSTALL_SHORT_ALIAS=true

usage() {
  cat <<EOF
Usage: ./install.sh --user|--system [options]

Options:
  --user       Install for the current user using systemd --user.
  --system     Install globally using system systemd.
  --enable     Enable the systemd service after installing.
  --start      Start the systemd service after installing. Implies --enable.
  --force      Overwrite existing binary, unit, and config.
  --no-alias   Do not install the rclone-mount convenience command.
  --dry-run    Print planned actions without writing.
  -h, --help   Show this help.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

escape_sed_replacement() {
  printf '%s\n' "$1" | sed 's/[&/\\]/\\&/g'
}

write_unit() {
  local template="$1"
  local target="$2"
  local bin_path="$3"
  local config_file="$4"
  local escaped_bin_path
  local escaped_config_file

  if [[ -e "$target" && "$FORCE" != "true" ]]; then
    die "Service file exists: $target. Use --force to overwrite."
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "dry-run: render $template -> $target"
    return 0
  fi

  escaped_bin_path="$(escape_sed_replacement "$bin_path")"
  escaped_config_file="$(escape_sed_replacement "$config_file")"

  sed \
    -e "s|@BIN_PATH@|$escaped_bin_path|g" \
    -e "s|@CONFIG_FILE@|$escaped_config_file|g" \
    "$template" > "$target"
}

install_config() {
  local source="$1"
  local target="$2"
  local mode="$3"

  if [[ -e "$target" && "$FORCE" != "true" ]]; then
    log "Keeping existing config: $target"
    return 0
  fi

  run install -m "$mode" "$source" "$target"
}

install_short_alias() {
  local bin_dir="$1"
  local bin_path="$2"
  local alias_path="$bin_dir/$SHORT_NAME"
  local existing_command=""

  [[ "$INSTALL_SHORT_ALIAS" == "true" ]] || return 0

  existing_command="$(command -v "$SHORT_NAME" 2>/dev/null || true)"

  if [[ -n "$existing_command" && "$existing_command" != "$alias_path" && "$FORCE" != "true" ]]; then
    die "$SHORT_NAME already exists at $existing_command. Use --no-alias or --force."
  fi

  if [[ -e "$alias_path" && "$FORCE" != "true" ]]; then
    die "Alias path exists: $alias_path. Use --no-alias or --force."
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "dry-run: install alias $alias_path -> $bin_path"
    return 0
  fi

  rm -f "$alias_path"
  ln -s "$(basename -- "$bin_path")" "$alias_path"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --user)
        MODE=user
        ;;
      --system)
        MODE=system
        ;;
      --enable)
        ENABLE_SERVICE=true
        ;;
      --start)
        ENABLE_SERVICE=true
        START_SERVICE=true
        ;;
      --force)
        FORCE=true
        ;;
      --no-alias)
        INSTALL_SHORT_ALIAS=false
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  [[ -n "$MODE" ]] || die "Choose --user or --system."
}

install_user() {
  local bin_dir="${HOME}/.local/bin"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
  local systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local bin_path="$bin_dir/$APP_NAME"
  local config_file="$config_dir/config"
  local unit_file="$systemd_dir/$APP_NAME.service"

  run mkdir -p "$bin_dir" "$config_dir" "$systemd_dir"
  run chmod 0700 "$config_dir"
  run install -m 0755 "$PROJECT_DIR/bin/$APP_NAME" "$bin_path"
  install_short_alias "$bin_dir" "$bin_path"
  install_config "$PROJECT_DIR/config/user.conf.example" "$config_file" 0600
  write_unit "$PROJECT_DIR/systemd/user/$APP_NAME.service" "$unit_file" "$bin_path" "$config_file"
  run systemctl --user daemon-reload

  if [[ "$ENABLE_SERVICE" == "true" ]]; then
    run systemctl --user enable "$APP_NAME.service"
  fi

  if [[ "$START_SERVICE" == "true" ]]; then
    run systemctl --user start "$APP_NAME.service"
  fi

  log "Installed user mode."
  log "Command: $bin_path"
  if [[ "$INSTALL_SHORT_ALIAS" == "true" ]]; then
    log "Alias:   $bin_dir/$SHORT_NAME"
  fi
  log "Edit config: $config_file"
}

install_system() {
  local bin_dir="/usr/local/bin"
  local config_dir="/etc/$APP_NAME"
  local systemd_dir="/etc/systemd/system"
  local bin_path="$bin_dir/$APP_NAME"
  local config_file="$config_dir/config"
  local unit_file="$systemd_dir/$APP_NAME.service"

  if [[ "$(id -u)" != "0" && "$DRY_RUN" != "true" ]]; then
    die "--system install must be run as root."
  fi

  run mkdir -p "$bin_dir" "$config_dir" "$systemd_dir"
  run chmod 0755 "$config_dir"
  run install -m 0755 "$PROJECT_DIR/bin/$APP_NAME" "$bin_path"
  install_short_alias "$bin_dir" "$bin_path"
  install_config "$PROJECT_DIR/config/system.conf.example" "$config_file" 0600
  write_unit "$PROJECT_DIR/systemd/system/$APP_NAME.service" "$unit_file" "$bin_path" "$config_file"
  run systemctl daemon-reload

  if [[ "$ENABLE_SERVICE" == "true" ]]; then
    run systemctl enable "$APP_NAME.service"
  fi

  if [[ "$START_SERVICE" == "true" ]]; then
    run systemctl start "$APP_NAME.service"
  fi

  log "Installed system mode."
  log "Command: $bin_path"
  if [[ "$INSTALL_SHORT_ALIAS" == "true" ]]; then
    log "Alias:   $bin_dir/$SHORT_NAME"
  fi
  log "Edit config: $config_file"
}

main() {
  parse_args "$@"

  case "$MODE" in
    user) install_user ;;
    system) install_system ;;
  esac
}

main "$@"
