# rclone-mount-manager

`rclone-mount-manager` manages multiple `rclone mount` processes on Linux.

It is designed for two scenarios:

- Per-user desktop mounts that start after login and unmount on logout/shutdown.
- Global system mounts shared by multiple users.

The project intentionally uses systemd for lifecycle management. The script handles rclone-specific logic; systemd handles startup, retry, and shutdown ordering.

## Requirements

- Linux with systemd
- Bash 4+
- rclone
- FUSE unmount tool: `fusermount3`, `fusermount`, or `umount`
- `timeout` from GNU coreutils when remote availability checks are enabled

## Quick start: per-user mode

Install:

```bash
./install.sh --user --enable
```

Edit:

```bash
$EDITOR ~/.config/rclone-mount-manager/config
```

Add mounts:

```bash
MOUNTS=(
  PersonalDrive
  WorkDrive
)

REMOTES=(
  [PersonalDrive]="PersonalDrive:"
  [WorkDrive]="WorkDrive:"
)
```

Start:

```bash
systemctl --user start rclone-mount-manager.service
```

Check:

```bash
systemctl --user status rclone-mount-manager.service
journalctl --user -u rclone-mount-manager.service -f
rclone-mount status
```

Default user mount root:

```text
~/mnt/rclone/<mount-name>
```

Override it in config:

```bash
ROOT_DIR_PATH="$HOME/mnt/rclone"
```

Override one mount only:

```bash
MOUNT_POINTS=(
  [WorkDrive]="$HOME/Work Cloud"
)
```

## Quick start: system/global mode

Install as root:

```bash
sudo ./install.sh --system --enable
```

Edit:

```bash
sudoedit /etc/rclone-mount-manager/config
```

Start:

```bash
sudo systemctl start rclone-mount-manager.service
```

Check:

```bash
systemctl status rclone-mount-manager.service
journalctl -u rclone-mount-manager.service -f
```

Default system mount root:

```text
/mnt/rclone/<mount-name>
```

If mounts should be visible to all users, add `--allow-other` to `DEFAULT_OPTIONS` and ensure `/etc/fuse.conf` contains:

```text
user_allow_other
```

System services often need an explicit rclone config path:

```bash
export RCLONE_CONFIG="/etc/rclone/rclone.conf"
```

Put that in `/etc/rclone-mount-manager/config`.

## Commands

The installer creates `rclone-mount` as a convenience command unless `--no-alias` is used. The full command remains available.

```bash
rclone-mount start
rclone-mount stop
rclone-mount restart
rclone-mount status
rclone-mount doctor
rclone-mount print-config
```

Use `rclone-mount-manager run` only from systemd. It keeps the manager in the foreground, supervises mounts, and traps termination signals so shutdown/logout can unmount cleanly.

## Connectivity behavior

Before mounting, the manager can check the actual rclone remote:

```bash
rclone lsf Remote: --max-depth 1
```

This is better than pinging a generic host because it checks DNS, internet access, rclone config, authentication, and the specific provider.

Default behavior:

```bash
CONNECTIVITY_CHECK=remote
CONNECTIVITY_RETRIES=12
CONNECTIVITY_INTERVAL_SECONDS=5
CONNECTIVITY_TIMEOUT_SECONDS=15
```

If the remote is unavailable after retries, the script exits non-zero. The systemd unit uses `Restart=on-failure`, so the service can retry when the network becomes available later.

Disable the check:

```bash
CONNECTIVITY_CHECK=off
```

## Safety behavior

By default, the manager refuses to mount over a non-empty directory:

```bash
REQUIRE_EMPTY_MOUNTPOINT=true
```

If startup fails partway through, previously mounted remotes are unmounted:

```bash
ROLLBACK_ON_START_FAILURE=true
```

Shutdown uses normal unmount first, then lazy FUSE unmount as a fallback.

## Security notes

Configuration files are executable Bash and must be trusted.

The installer writes configs with owner-only file permissions because users may add environment variables such as `RCLONE_CONFIG`, `RCLONE_CONFIG_PASS`, or provider-specific credentials.

This project is licensed under the MIT License.

## Troubleshooting

Run:

```bash
rclone-mount doctor
```

Common issues:

- Remote name typo in `REMOTES`.
- rclone config is encrypted and no password is available under systemd.
- Wi-Fi is not ready yet at login.
- OAuth token refresh failed.
- Mount point is non-empty.
- `--allow-other` is enabled but `/etc/fuse.conf` does not contain `user_allow_other`.
- System service cannot find the intended rclone config.

## Development

Run tests:

```bash
make test
```

Optional linting:

```bash
make lint
make format-check
```
