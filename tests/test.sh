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

make_temp_config() {
  local dir="$1"
  local config_file="$dir/config"

  cat > "$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$dir/root"
LOG_DIR="$dir/logs"
STATE_DIR="$dir/state"
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
  cat > "$mock_bin/mountpoint" <<'EOF'
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

test_install_dry_run() {
  local temp_dir
  local output

  temp_dir="$(mktemp -d)"
  output="$(HOME="$temp_dir/home" PATH="/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --dry-run --enable)"
  assert_contains "$output" "dry-run:"
  assert_contains "$output" "systemctl"
  assert_contains "$output" "install alias"

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

  cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin/systemctl"
  printf 'preserve-me\n' > "$config_file"

  output="$(HOME="$home_dir" PATH="$mock_bin:/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --no-alias)"
  assert_contains "$output" "Keeping existing config"
  assert_contains "$(<"$config_file")" "preserve-me"

  HOME="$home_dir" PATH="$mock_bin:/usr/bin:/bin" "$PROJECT_DIR/install.sh" --user --force --force-config --no-alias >/dev/null
  assert_contains "$(<"$config_file")" "MODE=user"

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
  cat > "$fake_systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_systemctl"

  touch "$home_dir/.local/bin/rclone-mount-manager"
  ln -s rclone-mount-manager "$home_dir/.local/bin/rclone-mount"

  HOME="$home_dir" PATH="$temp_dir/bin:$PATH" "$PROJECT_DIR/uninstall.sh" --user

  [[ ! -e "$home_dir/.local/bin/rclone-mount" ]] || fail "owned alias should be removed"

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
  cat > "$fake_systemctl" <<'EOF'
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

  cat > "$mock_bin/rclone" <<'EOF'
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

  cat > "$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
mount_point="${2:-$1}"
case "$mount_point" in
  */GoodDrive) [[ -e "$RMM_GOOD_MARKER" ]] ;;
  */BadDrive) [[ -e "$RMM_BAD_MARKER" ]] ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$mock_bin/mountpoint"

  cat > "$mock_bin/fusermount3" <<'EOF'
#!/usr/bin/env bash
mount_point="${2:-}"
case "$mount_point" in
  */GoodDrive) rm -f "$RMM_GOOD_MARKER" ;;
  */BadDrive) rm -f "$RMM_BAD_MARKER" ;;
esac
EOF
  chmod +x "$mock_bin/fusermount3"

  config_file="$temp_dir/config"
  cat > "$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$temp_dir/root"
LOG_DIR="$temp_dir/logs"
STATE_DIR="$temp_dir/state"
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

  good_starts="$(wc -l < "$temp_dir/good-starts")"
  bad_starts="$(wc -l < "$temp_dir/bad-starts")"
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

  cat > "$mock_bin/rclone" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/rclone"

  cat > "$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$mock_bin/mountpoint"

  config_file="$temp_dir/config"
  cat > "$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$temp_dir/root"
LOG_DIR="$temp_dir/logs"
STATE_DIR="$temp_dir/state"
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

  PATH="$mock_bin:$PATH" RMM_CONFIG_FILE="$config_file" "$BIN" run > "$temp_dir/output" 2>&1 &
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
  test_print_config_with_temp_config
  test_status_with_mock_mountpoint
  test_install_dry_run
  test_install_force_keeps_config_unless_explicitly_replaced
  test_uninstall_dry_run
  test_uninstall_removes_owned_alias_only
  test_uninstall_keeps_unowned_alias
  test_run_isolates_runtime_mount_failure
  test_run_stays_alive_when_all_mounts_fail

  printf 'All tests passed.\n'
}

main "$@"
