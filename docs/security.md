# Security

The manager config file is Bash. It is sourced by the manager process, so treat
it like a script.

Only put trusted content in these files:

- `~/.config/rclone-mount-manager/config`
- `/etc/rclone-mount-manager/config`

## File Permissions

The installer writes config files with owner-only permissions:

```text
0600
```

This matters because configs may contain secrets, such as:

```bash
export RCLONE_CONFIG="/etc/rclone/rclone.conf"
export RCLONE_CONFIG_PASS="your-password"
```

Do not make the config world-readable.

## Encrypted Rclone Configs

If an rclone config is encrypted, the service needs a way to unlock it.

For user mode, your login environment may already handle this.

For system mode, you may need to set `RCLONE_CONFIG_PASS` or use another
systemd-supported secret mechanism.

## Shared Mounts

Use `--allow-other` only when other users should see the mounted files.

For `--allow-other` to work, `/etc/fuse.conf` must contain:

```text
user_allow_other
```

Before enabling it, check the permissions of the mounted remote and the local
mount point. The manager can make a mount visible, but rclone and the remote
still control what data is available.

## System Mode

System mode runs as root through the system systemd service.

Prefer user mode unless you need a shared global mount. User mode keeps files,
credentials, logs, and runtime state inside the user account.
