# Setup

Use user mode for personal desktop mounts. Use system mode only when the mounts
must be managed globally.

## Before Installing

Install and configure `rclone` first.

Check that your remote works:

```bash
rclone listremotes
rclone lsd RemoteName:
```

The manager uses the same remote names that `rclone` shows.

## User Mode

Install:

```bash
./install.sh --user --enable
```

Edit the config:

```bash
$EDITOR ~/.config/rclone-mount-manager/config
```

Start:

```bash
systemctl --user start rclone-mount-manager.service
```

Check:

```bash
rclone-mount status
systemctl --user status rclone-mount-manager.service
journalctl --user -u rclone-mount-manager.service -f
```

Installed files:

- Binary: `~/.local/bin/rclone-mount-manager`
- Short command: `~/.local/bin/rclone-mount`
- Config: `~/.config/rclone-mount-manager/config`
- Unit: `~/.config/systemd/user/rclone-mount-manager.service`

Default mount path:

```text
~/mnt/rclone/<mount-name>
```

## System Mode

Install as root:

```bash
sudo ./install.sh --system --enable
```

Edit the config:

```bash
sudoedit /etc/rclone-mount-manager/config
```

Start:

```bash
sudo systemctl start rclone-mount-manager.service
```

Check:

```bash
sudo rclone-mount status
systemctl status rclone-mount-manager.service
journalctl -u rclone-mount-manager.service -f
```

Installed files:

- Binary: `/usr/local/bin/rclone-mount-manager`
- Short command: `/usr/local/bin/rclone-mount`
- Config: `/etc/rclone-mount-manager/config`
- Unit: `/etc/systemd/system/rclone-mount-manager.service`

Default mount path:

```text
/mnt/rclone/<mount-name>
```

System services often need an explicit rclone config path. Add this to
`/etc/rclone-mount-manager/config` if the service cannot see your remotes:

```bash
export RCLONE_CONFIG="/etc/rclone/rclone.conf"
```

To share mounted files with non-root users, add `--allow-other` to
`DEFAULT_OPTIONS` and make sure `/etc/fuse.conf` contains:

```text
user_allow_other
```

## Installer Options

```bash
./install.sh --user --enable
./install.sh --user --start
sudo ./install.sh --system --enable
sudo ./install.sh --system --start
./install.sh --user --dry-run
./install.sh --user --force
./install.sh --user --force --force-config
./install.sh --user --no-alias
./install.sh --user --gnome-extension
./install.sh --user --no-gnome-extension
```

Options:

- `--enable` enables the systemd service.
- `--start` enables and starts the service.
- `--force` overwrites the binary and unit while keeping the existing config.
  If the service is currently active, it is restarted so the updated manager
  code takes effect immediately.
- `--force-config` also overwrites the config and requires `--force`.
- `--no-alias` skips the `rclone-mount` short command.
- `--gnome-extension` installs the GNOME top-bar indicator for the current user.
- `--no-gnome-extension` skips it. Without either option, user-mode installation
  includes it when a supported active GNOME desktop is detected.
- `--dry-run` prints the planned actions.

The GNOME extension currently controls user-mode services only. A newly
installed extension may require logging out and back in before GNOME Shell can
enable it. See [GNOME indicator](gnome-extension.md).

## Updating

Run the installer again after pulling new code.

User mode:

```bash
./install.sh --user --force --enable
```

System mode:

```bash
sudo ./install.sh --system --force --enable
```

Existing config files are kept during updates. Add `--force-config` only when
you explicitly intend to replace the config with the example file.

## Uninstalling

User mode:

```bash
./uninstall.sh --user
```

System mode:

```bash
sudo ./uninstall.sh --system
```

Keep config files by default. Remove them with:

```bash
./uninstall.sh --user --remove-config
sudo ./uninstall.sh --system --remove-config
```

Preview uninstall actions with `--dry-run`.
