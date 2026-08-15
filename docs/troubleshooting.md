# Troubleshooting

Start with the built-in checks:

```bash
rclone-mount doctor
rclone-mount print-config
```

For system mode:

```bash
sudo rclone-mount doctor
sudo rclone-mount print-config
```

## Logs

User service logs:

```bash
journalctl --user -u rclone-mount-manager.service -f
```

System service logs:

```bash
journalctl -u rclone-mount-manager.service -f
```

Each rclone mount also writes its own log:

```text
<LOG_DIR>/<mount-name>-rclone-mount.log
```

Find `LOG_DIR` with:

```bash
rclone-mount print-config
```

## One Mount Keeps Failing

Check the per-mount state:

```bash
rclone-mount status
```

A failing mount is shown as `retrying` with its next attempt time and last
failure. Other mounts should remain `mounted`; their rclone processes are not
restarted.

The retry sequence is controlled by `RETRY_DELAYS_SECONDS`. Inspect the failed
mount's rclone log before shortening the delays. Repeated fast retries can add
load without resolving remote, credential, or network failures.

## Remote Not Found

Check the remote name:

```bash
rclone listremotes
```

The value in `REMOTES` must match an rclone remote or remote path:

```bash
REMOTES=(
  [PersonalDrive]="personal:"
)
```

## System Service Uses The Wrong Rclone Config

System services do not always see the same rclone config as your shell.

Add this to `/etc/rclone-mount-manager/config`:

```bash
export RCLONE_CONFIG="/etc/rclone/rclone.conf"
```

Then restart:

```bash
sudo systemctl restart rclone-mount-manager.service
```

## Encrypted Rclone Config

If your rclone config is encrypted, systemd needs a way to unlock it.

One option is to export `RCLONE_CONFIG_PASS` in the manager config:

```bash
export RCLONE_CONFIG_PASS="your-password"
```

Keep the config file private. The installer creates it with owner-only
permissions.

## Mount Point Is Not Empty

By default, startup fails if a mount point already contains files:

```bash
REQUIRE_EMPTY_MOUNTPOINT=true
```

Move the files away or use a different mount point.

Only disable this check if you understand the risk:

```bash
REQUIRE_EMPTY_MOUNTPOINT=false
```

## allow-other Fails

If `DEFAULT_OPTIONS` includes `--allow-other`, `/etc/fuse.conf` must contain:

```text
user_allow_other
```

Then restart the service.

## Network Or Login Timing

The manager checks the remote before mounting. Defaults:

```bash
CONNECTIVITY_RETRIES=12
CONNECTIVITY_INTERVAL_SECONDS=5
CONNECTIVITY_TIMEOUT_SECONDS=15
```

If the network is slow at login, increase retries or interval.

You can also disable the remote check:

```bash
CONNECTIVITY_CHECK=off
```

## Useful Checks

Check systemd state:

```bash
systemctl --user status rclone-mount-manager.service
systemctl status rclone-mount-manager.service
```

Check whether a path is mounted:

```bash
mountpoint ~/mnt/rclone/PersonalDrive
```

Test the same remote check the manager uses:

```bash
rclone lsf personal: --max-depth 1
```
