# rclone-mount-manager

Manage one or more `rclone mount` processes with systemd.

This project is for Linux systems where rclone mounts should start
automatically, restart after failures, and unmount cleanly during logout or
shutdown.

Each configured mount is supervised independently. A mount failure is cleaned
up and retried without restarting healthy mounts.

## Requirements

- Linux with systemd
- Bash 4+
- `rclone`
- `mountpoint`
- One unmount tool: `fusermount3`, `fusermount`, or `umount`
- GNU `timeout` when remote checks are enabled

Make sure your rclone remote works first:

```bash
rclone lsd RemoteName:
```

## Quick Start

Install for the current user:

```bash
./install.sh --user --enable
```

Edit the config:

```bash
$EDITOR ~/.config/rclone-mount-manager/config
```

Add at least one mount:

```bash
MOUNTS=(
  PersonalDrive
)

REMOTES=(
  [PersonalDrive]="personal:"
)
```

Start the service:

```bash
systemctl --user start rclone-mount-manager.service
```

Check it:

```bash
rclone-mount status
journalctl --user -u rclone-mount-manager.service -f
```

The default user mount path is:

```text
~/mnt/rclone/<mount-name>
```

## Common Commands

```bash
rclone-mount start
rclone-mount stop
rclone-mount restart
rclone-mount status
rclone-mount doctor
rclone-mount print-config
```

## More Documentation

- [Docs index](docs/README.md)
- [Setup](docs/setup.md)
- [Configuration](docs/configuration.md)
- [Commands](docs/commands.md)
- [Service behavior](docs/service-behavior.md)
- [Security](docs/security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Development](docs/development.md)

## Development

```bash
make test
```

## License

This project is licensed under the MIT License.
