#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="rclone-mount-manager"
SHORT_NAME="rclone-mount"
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"

MODE=""
ENABLE_SERVICE=false
START_SERVICE=false
FORCE=false
FORCE_CONFIG=false
DRY_RUN=false
INSTALL_SHORT_ALIAS=true
GNOME_EXTENSION_MODE=auto
GNOME_EXTENSION_UUID="rclone-mount-manager@jelovac.net"
GNOME_EXTENSION_USE_SUDO=false

usage() {
  cat <<EOF
Usage: ./install.sh --user|--system [options]

Options:
  --user       Install for the current user using systemd --user.
  --system     Install globally using system systemd.
  --enable     Enable the systemd service after installing.
  --start      Start the systemd service after installing. Implies --enable.
  --force      Overwrite the existing binary and unit; keep the config.
  --force-config
               Also overwrite the existing config. Requires --force.
  --no-alias   Do not install the rclone-mount convenience command.
  --gnome-extension
               Install the GNOME Shell indicator for the current user.
  --no-gnome-extension
               Do not install the GNOME Shell indicator. By default it is
               installed for user mode when an active GNOME desktop is detected.
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

validate_install_context() {
  local effective_uid="$1"

  if [[ "$MODE" == "user" && "$effective_uid" == "0" && "$DRY_RUN" != "true" ]]; then
    die "--user must be run as the desktop user, without sudo. Use --system for a root-managed installation."
  fi
}

extension_target_dir() {
  printf '%s/gnome-shell/extensions/%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}" "$GNOME_EXTENSION_UUID"
}

can_write_extension_target() {
  local target_dir="$1"
  local existing="$target_dir"

  if [[ -d "$target_dir" ]]; then
    [[ -w "$target_dir" && -x "$target_dir" ]]
    return
  fi

  [[ ! -e "$target_dir" && ! -L "$target_dir" ]] || return 1

  while [[ ! -e "$existing" && ! -L "$existing" ]]; do
    [[ "$existing" != "/" ]] || return 1
    existing="$(dirname -- "$existing")"
  done

  [[ -d "$existing" && -w "$existing" && -x "$existing" ]]
}

confirm_privileged_extension_install() {
  local target_dir="$1"
  local response

  if [[ "$DRY_RUN" == "true" ]]; then
    log "dry-run: $target_dir is not writable; would ask to install the GNOME extension with sudo"
    return 0
  fi

  [[ -t 0 ]] || die "GNOME extension target is not writable: $target_dir. Rerun interactively to approve a privileged extension-only copy, or use --no-gnome-extension."

  printf 'GNOME extension target is not writable: %s\n' "$target_dir"
  if ! IFS= read -r -p "Install only the GNOME extension files with sudo? [y/N] " response; then
    die "GNOME extension installation cancelled before any files were changed."
  fi

  case "${response,,}" in
    y | yes) return 0 ;;
    *) die "GNOME extension installation cancelled before any files were changed." ;;
  esac
}

prepare_gnome_extension_install() {
  local target_dir
  local extension_root

  should_install_gnome_extension || return 0
  target_dir="$(extension_target_dir)"
  extension_root="$(dirname -- "$target_dir")"

  if [[ (-e "$target_dir" || -L "$target_dir") && ! -d "$target_dir" ]]; then
    die "GNOME extension target does not resolve to a directory: $target_dir"
  fi
  can_write_extension_target "$target_dir" && return 0
  [[ -d "$extension_root" ]] || die "GNOME extensions directory cannot be created without modifying its parent: $extension_root"

  confirm_privileged_extension_install "$target_dir"
  GNOME_EXTENSION_USE_SUDO=true
}

run_privileged_extension_install() {
  local source_dir="$1"
  local target_dir="$2"
  local sudo_bin
  local install_bin
  local group_id
  local file
  local extension_root

  sudo_bin="$(command -v sudo)" || die "sudo is unavailable; cannot perform the approved GNOME extension copy."
  install_bin="$(command -v install)" || die "install is unavailable; cannot copy the GNOME extension."
  group_id="$(id -g)"
  extension_root="$(dirname -- "$target_dir")"
  [[ -d "$extension_root" ]] || die "Refusing to modify the parent of the GNOME extensions directory: $extension_root"

  if [[ ! -L "$target_dir" ]]; then
    run "$sudo_bin" "$install_bin" -d -o "$EUID" -g "$group_id" -m 0755 "$target_dir"
  fi
  for file in extension.js metadata.json stylesheet.css; do
    run "$sudo_bin" "$install_bin" -o "$EUID" -g "$group_id" -m 0644 "$source_dir/$file" "$target_dir/$file"
  done

  if [[ "$DRY_RUN" != "true" ]]; then
    if [[ ! -L "$target_dir" && "$(stat -c '%u' -- "$target_dir")" != "$EUID" ]]; then
      die "Privileged copy completed, but the extension directory has the wrong owner: $target_dir"
    fi
    for file in extension.js metadata.json stylesheet.css; do
      [[ "$(stat -c '%u' -- "$target_dir/$file")" == "$EUID" ]] || die "Privileged copy completed, but $target_dir/$file has the wrong owner."
    done
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
    "$template" >"$target"
}

install_config() {
  local source="$1"
  local target="$2"
  local mode="$3"

  if [[ -e "$target" && "$FORCE_CONFIG" != "true" ]]; then
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

gnome_extension_supported() {
  local desktop="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}"
  local shell_version

  [[ "${desktop,,}" == *gnome* ]] || return 1
  command -v gnome-shell >/dev/null 2>&1 || return 1
  command -v gnome-extensions >/dev/null 2>&1 || return 1

  shell_version="$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)"
  [[ "$shell_version" =~ ^(45|46|47|48|49|50)$ ]]
}

should_install_gnome_extension() {
  [[ "$MODE" == "user" ]] || return 1

  case "$GNOME_EXTENSION_MODE" in
    yes) return 0 ;;
    no) return 1 ;;
    auto) gnome_extension_supported ;;
  esac
}

install_gnome_extension() {
  local source_dir="$PROJECT_DIR/gnome-extension/$GNOME_EXTENSION_UUID"
  local extension_root="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
  local target_dir="$extension_root/$GNOME_EXTENSION_UUID"
  local file

  [[ -d "$source_dir" ]] || die "GNOME extension source is missing: $source_dir"

  if [[ "$GNOME_EXTENSION_USE_SUDO" == "true" ]]; then
    run_privileged_extension_install "$source_dir" "$target_dir"
  else
    run mkdir -p "$target_dir"
    for file in extension.js metadata.json stylesheet.css; do
      run install -m 0644 "$source_dir/$file" "$target_dir/$file"
    done
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "dry-run: enable GNOME extension $GNOME_EXTENSION_UUID"
  elif command -v gnome-extensions >/dev/null 2>&1; then
    if ! gnome-extensions enable "$GNOME_EXTENSION_UUID" >/dev/null 2>&1; then
      log "GNOME extension installed. Log out and back in, then enable $GNOME_EXTENSION_UUID."
    fi
  else
    log "GNOME extension installed. Log out and back in, then enable $GNOME_EXTENSION_UUID."
  fi

  log "GNOME extension: $target_dir"
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
      --force-config)
        FORCE_CONFIG=true
        ;;
      --no-alias)
        INSTALL_SHORT_ALIAS=false
        ;;
      --gnome-extension)
        GNOME_EXTENSION_MODE=yes
        ;;
      --no-gnome-extension)
        GNOME_EXTENSION_MODE=no
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h | --help)
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
  [[ "$FORCE_CONFIG" != "true" || "$FORCE" == "true" ]] || die "--force-config requires --force."
  [[ "$MODE" != "system" || "$GNOME_EXTENSION_MODE" != "yes" ]] || die "--gnome-extension currently supports --user mode only."
}

install_user() {
  local bin_dir="${HOME}/.local/bin"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
  local systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local bin_path="$bin_dir/$APP_NAME"
  local config_file="$config_dir/config"
  local unit_file="$systemd_dir/$APP_NAME.service"

  prepare_gnome_extension_install
  run mkdir -p "$bin_dir" "$config_dir" "$systemd_dir"
  run chmod 0700 "$config_dir"
  run install -m 0755 "$PROJECT_DIR/bin/$APP_NAME" "$bin_path"
  install_short_alias "$bin_dir" "$bin_path"
  install_config "$PROJECT_DIR/config/user.conf.example" "$config_file" 0600
  write_unit "$PROJECT_DIR/systemd/user/$APP_NAME.service" "$unit_file" "$bin_path" "$config_file"
  if should_install_gnome_extension; then
    install_gnome_extension
  fi
  run systemctl --user daemon-reload

  if [[ "$ENABLE_SERVICE" == "true" ]]; then
    run systemctl --user enable "$APP_NAME.service"
  fi

  if [[ "$FORCE" == "true" ]]; then
    run systemctl --user try-restart "$APP_NAME.service"
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

  if [[ "$FORCE" == "true" ]]; then
    run systemctl try-restart "$APP_NAME.service"
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
  validate_install_context "$EUID"

  case "$MODE" in
    user) install_user ;;
    system) install_system ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
