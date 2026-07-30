#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="rclone-mount-manager"

MODE=""
REMOVE_CONFIG=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: ./uninstall.sh --user|--system [options]

Options:
  --user            Remove current-user installation.
  --system          Remove global system installation.
  --remove-config   Also remove configuration files.
  --dry-run         Print planned actions without writing.
  -h, --help        Show this help.
EOF
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

run_optional() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@" || true
  fi
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
      --remove-config)
        REMOVE_CONFIG=true
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

uninstall_user() {
  local bin_path="${HOME}/.local/bin/$APP_NAME"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
  local unit_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$APP_NAME.service"

  run_optional systemctl --user disable --now "$APP_NAME.service"
  run rm -f "$unit_file" "$bin_path"
  run_optional systemctl --user daemon-reload

  if [[ "$REMOVE_CONFIG" == "true" ]]; then
    run rm -rf "$config_dir"
  fi
}

uninstall_system() {
  local bin_path="/usr/local/bin/$APP_NAME"
  local config_dir="/etc/$APP_NAME"
  local unit_file="/etc/systemd/system/$APP_NAME.service"

  if [[ "$(id -u)" != "0" && "$DRY_RUN" != "true" ]]; then
    die "--system uninstall must be run as root."
  fi

  run_optional systemctl disable --now "$APP_NAME.service"
  run rm -f "$unit_file" "$bin_path"
  run_optional systemctl daemon-reload

  if [[ "$REMOVE_CONFIG" == "true" ]]; then
    run rm -rf "$config_dir"
  fi
}

main() {
  parse_args "$@"

  case "$MODE" in
    user) uninstall_user ;;
    system) uninstall_system ;;
  esac
}

main "$@"
