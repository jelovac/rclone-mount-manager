#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
BIN="$PROJECT_DIR/bin/rclone-mount-manager"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

wait_for_file_state() {
  local path="$1"
  local expected="$2"
  local attempt

  for ((attempt = 0; attempt < 30; attempt++)); do
    if [[ "$expected" == "present" && -e "$path" ]]; then
      return 0
    fi
    if [[ "$expected" == "absent" && ! -e "$path" ]]; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

wait_for_line_count() {
  local path="$1"
  local minimum="$2"
  local attempt
  local count

  for ((attempt = 0; attempt < 30; attempt++)); do
    count=0
    [[ ! -f "$path" ]] || count="$(wc -l <"$path")"
    ((count >= minimum)) && return 0
    sleep 0.2
  done

  return 1
}

make_temp_config() {
  local dir="$1"
  local config_file="$dir/config"

  cat >"$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$dir/root"
LOG_DIR="$dir/logs"
STATE_DIR="$dir/state"
PERSISTENT_STATE_DIR="$dir/persistent-state"
CONNECTIVITY_CHECK=off
START_TIMEOUT_SECONDS=3
STOP_TIMEOUT_SECONDS=1
MOUNTS=(DemoDrive)
REMOTES=([DemoDrive]="DemoDrive:")
MOUNT_POINTS=()
MOUNT_OPTIONS=([DemoDrive]="--vfs-read-chunk-size 1M")
EOF

  printf '%s\n' "$config_file"
}

test_help() {
  local output
  output="$("$BIN" --help)"
  assert_contains "$output" "rclone-mount-manager"
  assert_contains "$output" "doctor"
}

test_gnome_indicator_registers_gobject_type() {
  local extension_file="$PROJECT_DIR/gnome-extension/rclone-mount-manager@jelovac.net/extension.js"
  local source

  source="$(<"$extension_file")"
  assert_contains "$source" "import GObject from 'gi://GObject';"
  assert_contains "$source" "const RcloneIndicator = GObject.registerClass("
  assert_contains "$source" "const [stdout, stderr] = await process.communicate_utf8_async"
  assert_not_contains "$source" "const [, stdout, stderr]"
  assert_contains "$source" "text: 'RMM'"
  assert_contains "$source" "[this.binary, 'doctor', '--wait']"
  assert_contains "$source" "_('About RMM')"
  assert_contains "$source" "© 2026 Vladimir Jelovac"
  assert_contains "$source" "MIT License"
  assert_contains "$source" "https://github.com/jelovac/rclone-mount-manager"
}

test_doctor_waits_for_confirmation() {
  local temp_dir
  local config_file
  local output

  temp_dir="$(mktemp -d)"
  config_file="$(make_temp_config "$temp_dir")"
  output="$(printf '\n' | RMM_CONFIG_FILE="$config_file" "$BIN" doctor --wait 2>&1 || true)"

  assert_contains "$output" "Checks:"
  assert_contains "$output" "Press Enter to close diagnostics"

  rm -rf "$temp_dir"
}

test_print_config_with_temp_config() {
  local temp_dir
  local config_file
  local output

  temp_dir="$(mktemp -d)"
  config_file="$(make_temp_config "$temp_dir")"
  output="$(RMM_CONFIG_FILE="$config_file" "$BIN" print-config)"

  assert_contains "$output" "CONFIG_FILE=$config_file"
  assert_contains "$output" "ROOT_DIR_PATH=$temp_dir/root"
  assert_contains "$output" "MOUNTS=DemoDrive"

  rm -rf "$temp_dir"
}

test_status_with_mock_mountpoint() {
  local temp_dir
  local mock_bin
  local config_file
  local output

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/mountpoint"

  config_file="$(make_temp_config "$temp_dir")"
  output="$(PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" status)"

  assert_contains "$output" "DemoDrive"
  assert_contains "$output" "not mounted"

  rm -rf "$temp_dir"
}

test_json_status_and_mount_control_requests() {
  local temp_dir
  local mock_bin
  local config_file
  local output

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/mountpoint"

  config_file="$(make_temp_config "$temp_dir")"
  mkdir -p "$temp_dir/state"
  cat >"$temp_dir/state/DemoDrive.status" <<'EOF'
status=retrying
failures=2
next_retry=4102444800
last_error=remote "offline"\path
EOF

  output="$(PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" status --json)"
  assert_contains "$output" '"name":"DemoDrive"'
  assert_contains "$output" '"status":"retrying"'
  assert_contains "$output" '"failures":2'
  assert_contains "$output" 'remote \"offline\"\\path'

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<<"$output"
  fi

  PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount pause DemoDrive >/dev/null
  [[ -f "$temp_dir/persistent-state/paused/DemoDrive" ]] || fail "pause marker was not created"
  assert_contains "$(<"$temp_dir/state/control/DemoDrive.command")" "pause"

  if PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount restart DemoDrive >/dev/null 2>&1; then
    fail "restart should reject a paused mount"
  fi

  PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount resume DemoDrive >/dev/null
  [[ ! -e "$temp_dir/persistent-state/paused/DemoDrive" ]] || fail "resume did not remove pause marker"
  assert_contains "$(<"$temp_dir/state/control/DemoDrive.command")" "resume"

  rm -rf "$temp_dir"
}

test_install_dry_run() {
  local temp_dir
  local output

  temp_dir="$(mktemp -d)"
  output="$(HOME="$temp_dir/home" XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome PATH="/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --dry-run --enable)"
  assert_contains "$output" "dry-run:"
  assert_contains "$output" "systemctl"
  assert_contains "$output" "install alias"
  assert_contains "$output" "GNOME extension"

  rm -rf "$temp_dir"
}

test_install_force_keeps_config_unless_explicitly_replaced() {
  local temp_dir
  local home_dir
  local mock_bin
  local config_file
  local output

  temp_dir="$(mktemp -d)"
  home_dir="$temp_dir/home"
  mock_bin="$temp_dir/bin"
  config_file="$home_dir/.config/rclone-mount-manager/config"
  mkdir -p "$mock_bin" "$(dirname -- "$config_file")"

  cat >"$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${RMM_SYSTEMCTL_CALLS:-}" ]]; then
  printf '%s\n' "$*" >> "$RMM_SYSTEMCTL_CALLS"
fi
exit 0
EOF
  chmod +x "$mock_bin/systemctl"
  printf 'preserve-me\n' >"$config_file"

  output="$(HOME="$home_dir" XDG_CURRENT_DESKTOP='' XDG_SESSION_DESKTOP='' RMM_SYSTEMCTL_CALLS="$temp_dir/systemctl-calls" PATH="$mock_bin:/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --no-alias)"
  assert_contains "$output" "Keeping existing config"
  assert_contains "$(<"$config_file")" "preserve-me"
  assert_contains "$(<"$temp_dir/systemctl-calls")" "--user try-restart rclone-mount-manager.service"

  HOME="$home_dir" XDG_CURRENT_DESKTOP='' XDG_SESSION_DESKTOP='' RMM_SYSTEMCTL_CALLS="$temp_dir/systemctl-calls" PATH="$mock_bin:/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --force-config --no-alias >/dev/null
  assert_contains "$(<"$config_file")" "MODE=user"

  rm -rf "$temp_dir"
}

test_user_install_rejects_sudo() {
  local output

  if output="$(bash -c '
    source "$1"
    MODE=user
    DRY_RUN=false
    validate_install_context 0
  ' bash "$PROJECT_DIR/install.sh" 2>&1)"; then
    fail "user install should reject sudo/root execution"
  fi
  assert_contains "$output" "without sudo"
}

test_unwritable_extension_stops_before_installation_non_interactively() {
  local temp_dir
  local home_dir
  local extension_root
  local output

  temp_dir="$(mktemp -d)"
  home_dir="$temp_dir/home"
  extension_root="$home_dir/.local/share/gnome-shell/extensions"
  mkdir -p "$extension_root"
  chmod 0555 "$extension_root"

  if output="$(HOME="$home_dir" PATH="/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --no-alias --gnome-extension </dev/null 2>&1)"; then
    fail "non-interactive installation should stop when extension-only sudo approval is required"
  fi
  assert_contains "$output" "privileged extension-only copy"
  [[ ! -e "$home_dir/.local/bin/rclone-mount-manager" ]] || fail "installation changed files before privileged-copy approval"

  chmod u+w "$extension_root"
  rm -rf "$temp_dir"
}

test_privileged_extension_copy_is_scoped_and_user_owned() {
  local temp_dir
  local mock_bin
  local extension_root
  local target_dir
  local calls
  local file

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  extension_root="$temp_dir/extensions"
  target_dir="$extension_root/rclone-mount-manager@jelovac.net"
  mkdir -p "$mock_bin" "$extension_root"
  chmod 0555 "$extension_root"

  cat >"$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$RMM_SUDO_CALLS"
printf '\n' >>"$RMM_SUDO_CALLS"
chmod u+w "$RMM_EXTENSION_ROOT"
"$@"
EOF
  chmod +x "$mock_bin/sudo"

  PATH="$mock_bin:/usr/bin:/bin" RMM_SUDO_CALLS="$temp_dir/sudo-calls" RMM_EXTENSION_ROOT="$extension_root" bash -c '
    source "$1"
    DRY_RUN=false
    run_privileged_extension_install "$2" "$3"
  ' bash "$PROJECT_DIR/install.sh" "$PROJECT_DIR/gnome-extension/rclone-mount-manager@jelovac.net" "$target_dir"

  calls="$(<"$temp_dir/sudo-calls")"
  assert_not_contains "$calls" "chown"
  assert_contains "$calls" "$target_dir"
  [[ "$(wc -l <"$temp_dir/sudo-calls")" == "4" ]] || fail "privileged extension copy issued unexpected commands"
  [[ "$(stat -c '%u' -- "$target_dir")" == "$EUID" ]] || fail "extension directory is not owned by the current user"
  for file in extension.js metadata.json stylesheet.css; do
    [[ "$(stat -c '%u' -- "$target_dir/$file")" == "$EUID" ]] || fail "$file is not owned by the current user"
  done

  chmod u+w "$extension_root"
  rm -rf "$temp_dir"
}

test_privileged_extension_copy_is_visible_in_dry_run() {
  local temp_dir
  local home_dir
  local extension_root
  local target_dir
  local output

  temp_dir="$(mktemp -d)"
  home_dir="$temp_dir/home"
  extension_root="$home_dir/.local/share/gnome-shell/extensions"
  target_dir="$extension_root/rclone-mount-manager@jelovac.net"
  mkdir -p "$extension_root"

  output="$(bash -c '
    source "$1"
    can_write_extension_target() {
      return 1
    }
    HOME="$2"
    main --user --force --no-alias --gnome-extension --dry-run
  ' bash "$PROJECT_DIR/install.sh" "$home_dir")"
  assert_contains "$output" "would ask to install the GNOME extension with sudo"
  assert_contains "$output" "$target_dir"
  assert_contains "$output" "sudo"
  assert_not_contains "$output" "chown"

  rm -rf "$temp_dir"
}

test_extension_target_directory_symlink_is_supported() {
  local temp_dir
  local home_dir
  local mock_bin
  local extension_root
  local external_target

  temp_dir="$(mktemp -d)"
  home_dir="$temp_dir/home"
  mock_bin="$temp_dir/bin"
  extension_root="$home_dir/.local/share/gnome-shell/extensions"
  external_target="$temp_dir/external-extension"
  mkdir -p "$mock_bin" "$extension_root" "$external_target"
  ln -s "$external_target" "$extension_root/rclone-mount-manager@jelovac.net"

  cat >"$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"$mock_bin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin/systemctl" "$mock_bin/gnome-extensions"

  HOME="$home_dir" PATH="$mock_bin:/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --no-alias --gnome-extension >/dev/null
  [[ -L "$extension_root/rclone-mount-manager@jelovac.net" ]] || fail "extension directory symlink was replaced"
  [[ -f "$external_target/extension.js" ]] || fail "extension was not installed through the directory symlink"

  rm -rf "$temp_dir"
}

test_uninstall_dry_run() {
  local temp_dir
  local output

  temp_dir="$(mktemp -d)"
  output="$(HOME="$temp_dir/home" PATH="/usr/bin:/bin" "$PROJECT_DIR/uninstall.sh" --user --dry-run --remove-config)"
  assert_contains "$output" "dry-run:"
  assert_contains "$output" "rm -rf"

  rm -rf "$temp_dir"
}

test_uninstall_removes_owned_alias_only() {
  local temp_dir
  local fake_systemctl
  local home_dir

  temp_dir="$(mktemp -d)"
  fake_systemctl="$temp_dir/bin/systemctl"
  home_dir="$temp_dir/home"

  mkdir -p "$temp_dir/bin" "$home_dir/.local/bin"
  cat >"$fake_systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_systemctl"
  cat >"$temp_dir/bin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$temp_dir/bin/gnome-extensions"

  touch "$home_dir/.local/bin/rclone-mount-manager"
  ln -s rclone-mount-manager "$home_dir/.local/bin/rclone-mount"
  mkdir -p "$home_dir/.local/share/gnome-shell/extensions/rclone-mount-manager@jelovac.net"
  touch "$home_dir/.local/share/gnome-shell/extensions/rclone-mount-manager@jelovac.net/extension.js"

  HOME="$home_dir" PATH="$temp_dir/bin:$PATH" "$PROJECT_DIR/uninstall.sh" --user

  [[ ! -e "$home_dir/.local/bin/rclone-mount" ]] || fail "owned alias should be removed"
  [[ ! -e "$home_dir/.local/share/gnome-shell/extensions/rclone-mount-manager@jelovac.net" ]] || fail "GNOME extension should be removed"

  rm -rf "$temp_dir"
}

test_uninstall_keeps_unowned_alias() {
  local temp_dir
  local fake_systemctl
  local home_dir
  local output

  temp_dir="$(mktemp -d)"
  fake_systemctl="$temp_dir/bin/systemctl"
  home_dir="$temp_dir/home"

  mkdir -p "$temp_dir/bin" "$home_dir/.local/bin"
  cat >"$fake_systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_systemctl"

  touch "$home_dir/.local/bin/other-tool"
  ln -s other-tool "$home_dir/.local/bin/rclone-mount"

  output="$(HOME="$home_dir" PATH="$temp_dir/bin:$PATH" "$PROJECT_DIR/uninstall.sh" --user)"

  [[ -L "$home_dir/.local/bin/rclone-mount" ]] || fail "unowned alias should be kept"
  assert_contains "$output" "Keeping alias not owned"

  rm -rf "$temp_dir"
}

test_supervised_mount_controls() {
  local temp_dir
  local mock_bin
  local config_file
  local manager_pid
  local manager_stopped=false

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/rclone" <<'EOF'
#!/usr/bin/env bash
printf 'start\n' >> "$RMM_STARTS"
touch "$RMM_MARKER"
trap 'rm -f "$RMM_MARKER"; exit 0' INT TERM
while true; do sleep 1; done
EOF
  chmod +x "$mock_bin/rclone"

  cat >"$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
[[ -e "$RMM_MARKER" ]]
EOF
  chmod +x "$mock_bin/mountpoint"

  cat >"$mock_bin/fusermount3" <<'EOF'
#!/usr/bin/env bash
rm -f "$RMM_MARKER"
EOF
  chmod +x "$mock_bin/fusermount3"

  config_file="$temp_dir/config"
  cat >"$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$temp_dir/root"
LOG_DIR="$temp_dir/logs"
STATE_DIR="$temp_dir/state"
PERSISTENT_STATE_DIR="$temp_dir/persistent-state"
CONNECTIVITY_CHECK=off
START_TIMEOUT_SECONDS=2
STOP_TIMEOUT_SECONDS=1
HEALTH_CHECK_INTERVAL_SECONDS=1
RETRY_DELAYS_SECONDS=(2)
RETRY_RESET_SECONDS=30
MOUNTS=(DemoDrive)
REMOTES=([DemoDrive]="DemoDrive:")
MOUNT_POINTS=()
MOUNT_OPTIONS=()
EOF

  PATH="$mock_bin:$PATH" \
    RMM_CONFIG_FILE="$config_file" \
    RMM_MARKER="$temp_dir/mounted" \
    RMM_STARTS="$temp_dir/starts" \
    "$BIN" run >"$temp_dir/output" 2>&1 &
  manager_pid="$!"

  if ! wait_for_file_state "$temp_dir/mounted" present; then
    manager_stopped=true
  fi

  if [[ "$manager_stopped" == "false" ]]; then
    PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount pause DemoDrive >/dev/null
    wait_for_file_state "$temp_dir/mounted" absent || manager_stopped=true
  fi

  if [[ "$manager_stopped" == "false" ]]; then
    assert_contains "$(PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" status --json)" '"status":"paused"'
    PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount resume DemoDrive >/dev/null
    wait_for_file_state "$temp_dir/mounted" present || manager_stopped=true
    wait_for_line_count "$temp_dir/starts" 2 || manager_stopped=true
  fi

  if [[ "$manager_stopped" == "false" ]]; then
    PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" mount restart DemoDrive >/dev/null
    wait_for_line_count "$temp_dir/starts" 3 || manager_stopped=true
  fi

  kill -TERM "$manager_pid" >/dev/null 2>&1 || true
  wait "$manager_pid" || true

  if [[ "$manager_stopped" == "true" ]]; then
    output="$(<"$temp_dir/output")"
    rm -rf "$temp_dir"
    fail "supervised mount control did not complete: $output"
  fi

  rm -rf "$temp_dir"
}

test_run_isolates_runtime_mount_failure() {
  local temp_dir
  local mock_bin
  local config_file
  local output
  local good_starts
  local bad_starts

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/rclone" <<'EOF'
#!/usr/bin/env bash
remote="${2:-}"

case "$remote" in
  GoodDrive:)
    printf 'start\n' >> "$RMM_GOOD_STARTS"
    touch "$RMM_GOOD_MARKER"
    trap 'rm -f "$RMM_GOOD_MARKER"; exit 0' INT TERM
    while true; do sleep 1; done
    ;;
  BadDrive:)
    printf 'start\n' >> "$RMM_BAD_STARTS"
    touch "$RMM_BAD_MARKER"
    sleep 2
    rm -f "$RMM_BAD_MARKER"
    exit 1
    ;;
esac
EOF
  chmod +x "$mock_bin/rclone"

  cat >"$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
mount_point="${2:-$1}"
case "$mount_point" in
  */GoodDrive) [[ -e "$RMM_GOOD_MARKER" ]] ;;
  */BadDrive) [[ -e "$RMM_BAD_MARKER" ]] ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$mock_bin/mountpoint"

  cat >"$mock_bin/fusermount3" <<'EOF'
#!/usr/bin/env bash
mount_point="${2:-}"
case "$mount_point" in
  */GoodDrive) rm -f "$RMM_GOOD_MARKER" ;;
  */BadDrive) rm -f "$RMM_BAD_MARKER" ;;
esac
EOF
  chmod +x "$mock_bin/fusermount3"

  config_file="$temp_dir/config"
  cat >"$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$temp_dir/root"
LOG_DIR="$temp_dir/logs"
STATE_DIR="$temp_dir/state"
PERSISTENT_STATE_DIR="$temp_dir/persistent-state"
CONNECTIVITY_CHECK=off
START_TIMEOUT_SECONDS=2
STOP_TIMEOUT_SECONDS=1
HEALTH_CHECK_INTERVAL_SECONDS=1
RETRY_DELAYS_SECONDS=(1 2)
RETRY_RESET_SECONDS=30
MOUNTS=(GoodDrive BadDrive)
REMOTES=([GoodDrive]="GoodDrive:" [BadDrive]="BadDrive:")
MOUNT_POINTS=()
MOUNT_OPTIONS=()
EOF

  output="$(
    PATH="$mock_bin:$PATH" \
      RMM_CONFIG_FILE="$config_file" \
      RMM_GOOD_MARKER="$temp_dir/good-mounted" \
      RMM_BAD_MARKER="$temp_dir/bad-mounted" \
      RMM_GOOD_STARTS="$temp_dir/good-starts" \
      RMM_BAD_STARTS="$temp_dir/bad-starts" \
      timeout -s TERM 7 "$BIN" run 2>&1 || true
  )"

  assert_contains "$output" "Mounted GoodDrive"
  assert_contains "$output" "Mounted BadDrive"
  assert_contains "$output" "BadDrive failed:"
  assert_contains "$output" "cleaning up only this mount"
  assert_contains "$output" "BadDrive will retry"
  assert_not_contains "$output" "GoodDrive failed:"
  assert_not_contains "$output" "stopping remaining mounts"

  good_starts="$(wc -l <"$temp_dir/good-starts")"
  bad_starts="$(wc -l <"$temp_dir/bad-starts")"
  [[ "$good_starts" == "1" ]] || fail "healthy mount restarted $good_starts times"
  ((bad_starts >= 2)) || fail "failed mount was not retried"

  rm -rf "$temp_dir"
}

test_run_stays_alive_when_all_mounts_fail() {
  local temp_dir
  local mock_bin
  local config_file
  local manager_pid
  local status_output

  temp_dir="$(mktemp -d)"
  mock_bin="$temp_dir/bin"
  mkdir -p "$mock_bin"

  cat >"$mock_bin/rclone" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/rclone"

  cat >"$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/mountpoint"

  config_file="$temp_dir/config"
  cat >"$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$temp_dir/root"
LOG_DIR="$temp_dir/logs"
STATE_DIR="$temp_dir/state"
PERSISTENT_STATE_DIR="$temp_dir/persistent-state"
CONNECTIVITY_CHECK=off
START_TIMEOUT_SECONDS=1
STOP_TIMEOUT_SECONDS=1
HEALTH_CHECK_INTERVAL_SECONDS=1
RETRY_DELAYS_SECONDS=(5)
RETRY_RESET_SECONDS=30
MOUNTS=(BadDrive)
REMOTES=([BadDrive]="BadDrive:")
MOUNT_POINTS=()
MOUNT_OPTIONS=()
EOF

  PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" run >"$temp_dir/output" 2>&1 &
  manager_pid="$!"
  sleep 2

  kill -0 "$manager_pid" >/dev/null 2>&1 || fail "manager exited when every mount failed"
  status_output="$(PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" status)"
  assert_contains "$status_output" "BadDrive"
  assert_contains "$status_output" "retrying"

  kill -TERM "$manager_pid"
  wait "$manager_pid" || true
  rm -rf "$temp_dir"
}

main() {
  test_help
  test_gnome_indicator_registers_gobject_type
  test_doctor_waits_for_confirmation
  test_print_config_with_temp_config
  test_status_with_mock_mountpoint
  test_json_status_and_mount_control_requests
  test_install_dry_run
  test_install_force_keeps_config_unless_explicitly_replaced
  test_user_install_rejects_sudo
  test_unwritable_extension_stops_before_installation_non_interactively
  test_privileged_extension_copy_is_scoped_and_user_owned
  test_privileged_extension_copy_is_visible_in_dry_run
  test_extension_target_directory_symlink_is_supported
  test_uninstall_dry_run
  test_uninstall_removes_owned_alias_only
  test_uninstall_keeps_unowned_alias
  test_supervised_mount_controls
  test_run_isolates_runtime_mount_failure
  test_run_stays_alive_when_all_mounts_fail

  printf 'All tests passed.\n'
}

main "$@"
