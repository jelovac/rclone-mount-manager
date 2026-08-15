# Commands

The installed binary is `rclone-mount-manager`.

The installer also creates `rclone-mount` as a short command unless
`--no-alias` is used.

## Service Commands

User service:

```bash
systemctl --user start rclone-mount-manager.service
systemctl --user stop rclone-mount-manager.service
systemctl --user restart rclone-mount-manager.service
systemctl --user status rclone-mount-manager.service
```

System service:

```bash
sudo systemctl start rclone-mount-manager.service
sudo systemctl stop rclone-mount-manager.service
sudo systemctl restart rclone-mount-manager.service
systemctl status rclone-mount-manager.service
```

## Manager Commands

Start configured mounts in daemon mode:

```bash
rclone-mount start
```

Stop configured mounts:

```bash
rclone-mount stop
```

Restart configured mounts:

```bash
rclone-mount restart
```

Show mount status:

```bash
rclone-mount status
```

Return the same status as machine-readable JSON:

```bash
rclone-mount status --json
```

The JSON output includes mount names, resolved mount and log paths, current
state, failure count, next retry time, last error, and whether a mount is
paused. It intentionally excludes remotes and configuration contents.

## Per-Mount Controls

Per-mount controls are intended for supervised `run` mode:

```bash
rclone-mount mount pause PersonalDrive
rclone-mount mount resume PersonalDrive
rclone-mount mount restart PersonalDrive
rclone-mount mount retry PersonalDrive
```

`pause` stops the mount and suppresses automatic recovery. The paused state is
persistent, so it survives a service restart and reboot. `resume` allows the
supervisor to start it again. `restart` performs a clean unmount and immediate
start. `retry` is an equivalent immediate restart intended for a mount already
waiting in retry backoff.

Requests are processed on the next manager health-check cycle. Use global
`start`, `stop`, and `restart` only when the systemd service is not supervising
the mounts.

Run checks:

```bash
rclone-mount doctor
```

Print resolved settings:

```bash
rclone-mount print-config
```

Show help:

```bash
rclone-mount help
```

## System Mode Status

For system mode, run manager commands as root:

```bash
sudo rclone-mount status
```

The system config is installed with owner-only permissions, and system mode uses
root-owned paths such as `/mnt/rclone`, `/var/log/rclone-mount-manager`, and
`/run/rclone-mount-manager`.

## The run Command

`run` is meant for systemd:

```bash
rclone-mount-manager run
```

It keeps the manager in the foreground, starts rclone mount processes, watches
each one with an independent supervisor, and retries only the mount that fails.
Healthy mounts are not restarted when another mount is unavailable.

Use `systemctl` for normal service management.
