# GNOME Indicator

The optional GNOME Shell extension adds an Rclone Mount Manager indicator to
the right side of the top bar. It supports GNOME Shell 45 through 50 and
controls the current user's systemd service.

## Installation

User-mode installation automatically includes the extension when the current
desktop identifies itself as GNOME, the detected Shell version is supported,
and `gnome-extensions` is available:

```bash
./install.sh --user --enable
```

Override detection explicitly:

```bash
./install.sh --user --enable --gnome-extension
./install.sh --user --enable --no-gnome-extension
```

Run these commands without `sudo`. If the extension target is not writable, the
installer asks whether it may use `sudo` for an extension-only copy. It does not
change the surrounding GNOME extensions directory; only this extension's
directory and three files are installed, with ownership assigned to the desktop
user. Declining stops before any installation files are changed.

The extension is installed under:

```text
~/.local/share/gnome-shell/extensions/rclone-mount-manager@jelovac.net
```

GNOME Shell may not discover a new local extension until the next login. If the
installer reports that it could not enable the extension, log out and back in,
then run:

```bash
gnome-extensions enable rclone-mount-manager@jelovac.net
```

## Indicator States

- Hidden: the unit is missing, or it is both disabled and inactive.
- Normal: the manager is active and every non-paused mount is mounted.
- Yellow warning: some expected mounts are healthy and others are unavailable.
- Red error: the service failed, status cannot be read, or no expected mounts
  are healthy.
- Gray paused/stopped: all mounts are paused, or an enabled manager is stopped.
- Synchronizing: the service or every expected mount is starting.

An active service remains visible even if it is disabled at login, because
systemd activation and enablement are separate states.

## Menu Actions

Each mount submenu shows its current state and provides:

- Open Mount
- View Log
- Restart or Retry Now
- Pause or Resume

The global menu provides manager Start, Stop, and Restart actions, an Enable at
Login toggle, configuration and log-folder shortcuts, a live journal view, and
the built-in diagnostics command.

Commands run asynchronously and use fixed argument arrays; the extension does
not evaluate configuration content or construct shell command strings.

## System Mode

The indicator deliberately supports only user-mode services. System mode runs
as root and its private configuration and runtime state must not be exposed to
the GNOME Shell process. Supporting it safely requires a separate sanitized
status API and narrowly scoped PolicyKit authorization.

## Troubleshooting

Check whether GNOME loaded the extension:

```bash
gnome-extensions info rclone-mount-manager@jelovac.net
journalctl --user -b -o cat | grep rclone-mount-manager@jelovac.net
```

Verify the backend independently:

```bash
rclone-mount status --json
systemctl --user show rclone-mount-manager.service \
  -p LoadState -p ActiveState -p SubState -p UnitFileState
```

On a Wayland session, log out and back in after installing or updating the
extension when GNOME Shell has not reloaded it.
