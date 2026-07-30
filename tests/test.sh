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

make_temp_config() {
  local dir="$1"
  local config_file="$dir/config"

  cat > "$config_file" <<EOF
MODE=user
ROOT_DIR_PATH="$dir/root"
LOG_DIR="$dir/logs"
STATE_DIR="$dir/state"
CONNECTIVITY_CHECK=off
START_TIMEOUT_SECONDS=1
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
  local output

  output="$(HOME=/tmp/rmm-test-home "$PROJECT_DIR/install.sh" --user --dry-run --enable)"
  assert_contains "$output" "dry-run:"
  assert_contains "$output" "systemctl"
}

test_uninstall_dry_run() {
  local output

  output="$(HOME=/tmp/rmm-test-home "$PROJECT_DIR/uninstall.sh" --user --dry-run --remove-config)"
  assert_contains "$output" "dry-run:"
  assert_contains "$output" "rm -rf"
}

main() {
  test_help
  test_print_config_with_temp_config
  test_status_with_mock_mountpoint
  test_install_dry_run
  test_uninstall_dry_run

  printf 'All tests passed.\n'
}

main "$@"
