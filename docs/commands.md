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
them, and stops remaining mounts if one disappears.

Use `systemctl` for normal service management.
