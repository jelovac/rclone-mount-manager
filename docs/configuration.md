# Configuration

The config file is Bash. Keep it trusted and private.

Default paths:

- User mode: `~/.config/rclone-mount-manager/config`
- System mode: `/etc/rclone-mount-manager/config`

You can use a different readable config file with:

```bash
RMM_CONFIG_FILE=/path/to/config rclone-mount status
```

Systemd units installed by this project set `RMM_CONFIG_FILE` to the generated
config path.

## Minimal Config

```bash
MODE=user

MOUNTS=(
  PersonalDrive
)

REMOTES=(
  [PersonalDrive]="personal:"
)
```

`MOUNTS` contains local mount names. `REMOTES` maps each mount name to an rclone
remote.

Mount names must start with a letter or number and may contain letters, numbers,
dots, underscores, and dashes. Names and resolved mount paths must be unique.

The remote value must be a valid rclone remote path, such as:

```bash
[PersonalDrive]="personal:"
[Photos]="drive:Photos"
```

## Mount Paths

Mount paths are built from `ROOT_DIR_PATH` and the mount name.

User default:

```bash
ROOT_DIR_PATH="$HOME/mnt/rclone"
```

System default:

```bash
ROOT_DIR_PATH="/mnt/rclone"
```

For a custom path on one mount, use `MOUNT_POINTS`:

```bash
MOUNT_POINTS=(
  [PersonalDrive]="$HOME/Cloud"
)
```

## Rclone Options

`DEFAULT_OPTIONS` applies to every mount.

Default values:

```bash
DEFAULT_OPTIONS=(
  --vfs-cache-mode full
  --vfs-cache-max-size 10G
  --vfs-cache-max-age 12h
  --dir-cache-time 5m
  --poll-interval 1m
  --attr-timeout 1s
  --transfers 4
  --multi-thread-streams 4
)
```

Use `MOUNT_OPTIONS` for one mount:

```bash
MOUNT_OPTIONS=(
  [PersonalDrive]="--vfs-read-chunk-size 128M"
)
```

`MOUNT_OPTIONS` is a simple string. It is intended for normal rclone option
pairs. For complex shell quoting, prefer adding the option to `DEFAULT_OPTIONS`
or keep the value simple.

### Directory Cache Tuning

The default `5m` directory-cache lifetime is deliberately backend-neutral.
Changes made through a mount update its in-memory directory cache immediately.
Changes made through a provider's website or another client are detected within
`--poll-interval` only when that backend supports change notifications. On a
backend without that support, directory listings are refreshed only when
`--dir-cache-time` expires.

For a backend with change notifications, a long cache lifetime avoids repeated
remote listings while polling invalidates directories that change. For example,
OneDrive supports this combination:

```bash
MOUNT_OPTIONS=(
  [PersonalDrive]="--dir-cache-time 72h --poll-interval 1m"
)
```

OneDrive mounts at the drive root can also warm the complete directory cache in
the background at startup. Delta listing makes that recursive refresh much more
efficient:

```bash
MOUNT_OPTIONS=(
  [PersonalDrive]="--dir-cache-time 72h --poll-interval 1m --onedrive-delta --vfs-refresh"
)
```

Recursive refresh still consumes API requests and memory proportional to the
directory tree, so leave it off for very large mounts unless faster first access
is worth that cost. Do not use a multi-day directory-cache lifetime on a backend
without change notifications unless stale changes made outside the mount are
acceptable. For such backends, keep a finite lifetime and disable ineffective
polling explicitly, for example `--dir-cache-time 10m --poll-interval 0`.

## Connectivity Checks

By default, the manager checks each remote before mounting:

```bash
CONNECTIVITY_CHECK=remote
CONNECTIVITY_RETRIES=12
CONNECTIVITY_INTERVAL_SECONDS=5
CONNECTIVITY_TIMEOUT_SECONDS=15
```

The check runs:

```bash
rclone lsf Remote: --max-depth 1
```

Disable the check with:

```bash
CONNECTIVITY_CHECK=off
```

## Safety Settings

The manager refuses to mount over a non-empty directory by default:

```bash
REQUIRE_EMPTY_MOUNTPOINT=true
```

Allow non-empty mount points only if you know why:

```bash
REQUIRE_EMPTY_MOUNTPOINT=false
```

Manual `start` attempts every configured mount and leaves successful mounts
active by default:

```bash
ROLLBACK_ON_START_FAILURE=false
```

Set this to `true` only when manual batch startup must be transactional. The
systemd `run` mode always isolates failures and does not roll back healthy
mounts.

## Supervision And Retries

The systemd service checks every mount independently:

```bash
HEALTH_CHECK_INTERVAL_SECONDS=5
RETRY_DELAYS_SECONDS=(10 30 60 300)
RETRY_RESET_SECONDS=600
SUPERVISOR_RESTART_DELAY_SECONDS=30
```

`RETRY_DELAYS_SECONDS` is the backoff sequence for a mount that cannot start or
becomes unhealthy. Once the sequence is exhausted, the last value is reused.
After a mount stays healthy for `RETRY_RESET_SECONDS`, its next failure starts
again at the first delay.

`SUPERVISOR_RESTART_DELAY_SECONDS` applies only if an individual supervisor
subprocess exits unexpectedly. Normal rclone or mount failures remain inside
that supervisor's retry loop.

## Logs And State

User defaults:

```bash
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rclone-mount-manager/logs"
STATE_DIR="$XDG_RUNTIME_DIR/rclone-mount-manager"
PERSISTENT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rclone-mount-manager"
```

If `XDG_RUNTIME_DIR` is empty, user mode falls back to:

```text
/tmp/rclone-mount-manager-<uid>
```

System defaults:

```bash
LOG_DIR="/var/log/rclone-mount-manager"
STATE_DIR="/run/rclone-mount-manager"
PERSISTENT_STATE_DIR="/var/lib/rclone-mount-manager"
```

Each mount gets a rclone log file:

```text
<LOG_DIR>/<mount-name>-rclone-mount.log
```

Runtime status and control requests live under `STATE_DIR` and disappear at
logout or reboot. Persistent per-mount pause markers live under
`PERSISTENT_STATE_DIR/paused`. Both control locations are owner-only.

## Environment Variables

Most runtime settings can also be set with `RMM_` environment variables. The
manager reads these first, then sources the config file. Values in the config
file take precedence.

Examples:

```bash
RMM_MODE=system
RMM_ROOT_DIR_PATH=/srv/rclone
RMM_CONNECTIVITY_CHECK=off
```

The config file can also export rclone variables, such as:

```bash
export RCLONE_CONFIG="/etc/rclone/rclone.conf"
export RCLONE_CONFIG_PASS="your-password"
```

Config files are installed with owner-only permissions because they may contain
secrets.
