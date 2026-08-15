import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(
    Gio.Subprocess.prototype,
    'communicate_utf8_async',
    'communicate_utf8_finish'
);

const APP_NAME = 'rclone-mount-manager';
const UNIT_NAME = `${APP_NAME}.service`;
const REFRESH_SECONDS = 10;

async function runCapture(argv, cancellable = null) {
    const process = Gio.Subprocess.new(
        argv,
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
    );
    const [stdout, stderr] = await process.communicate_utf8_async(null, cancellable);

    return {
        ok: process.get_successful(),
        stdout: stdout ?? '',
        stderr: stderr ?? '',
    };
}

function parseSystemdProperties(output) {
    const properties = {};

    for (const line of output.split('\n')) {
        const separator = line.indexOf('=');
        if (separator > 0)
            properties[line.slice(0, separator)] = line.slice(separator + 1);
    }

    return {
        loadState: properties.LoadState ?? 'not-found',
        activeState: properties.ActiveState ?? 'inactive',
        subState: properties.SubState ?? 'dead',
        unitFileState: properties.UnitFileState ?? 'disabled',
    };
}

function isUnitEnabled(unitFileState) {
    return unitFileState === 'enabled' || unitFileState === 'enabled-runtime';
}

function shouldShowIndicator(service) {
    const loaded = service.loadState === 'loaded';
    const enabled = isUnitEnabled(service.unitFileState);
    const active = service.activeState !== 'inactive';

    return loaded && (enabled || active);
}

function statusLabel(mount) {
    switch (mount.status) {
    case 'mounted':
        return _('Mounted');
    case 'starting':
        return _('Starting');
    case 'retrying': {
        const remaining = Math.max(0, mount.next_retry - Math.floor(Date.now() / 1000));
        return remaining > 0 ? _('Retrying in %d seconds').format(remaining) : _('Retrying');
    }
    case 'failed':
        return _('Failed');
    case 'paused':
        return _('Paused');
    case 'pausing':
        return _('Pausing');
    case 'stopped':
        return _('Stopped');
    default:
        return _('Not mounted');
    }
}

function mountAppearance(mount) {
    if (mount.paused || mount.status === 'paused' || mount.status === 'pausing')
        return ['media-playback-pause-symbolic', 'rmm-mount-paused'];
    if (mount.mounted)
        return ['folder-remote-symbolic', ''];
    if (mount.status === 'starting')
        return ['emblem-synchronizing-symbolic', ''];
    if (mount.status === 'retrying')
        return ['dialog-warning-symbolic', 'rmm-mount-warning'];
    return ['dialog-error-symbolic', 'rmm-mount-error'];
}

const RcloneIndicator = GObject.registerClass(
class RcloneIndicator extends PanelMenu.Button {
    constructor(extension) {
        super(0.0, _('Rclone Mount Manager'));

        this._extension = extension;
        this._box = new St.BoxLayout({
            style_class: 'panel-status-menu-box',
        });
        this._icon = new St.Icon({
            icon_name: 'folder-remote-symbolic',
            style_class: 'system-status-icon',
        });
        this._label = new St.Label({
            text: 'RMM',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'rmm-indicator-label',
        });
        this._box.add_child(this._icon);
        this._box.add_child(this._label);
        this.add_child(this._box);
        this.visible = false;
        this._pendingMenuData = null;
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open || !this._pendingMenuData)
                return;

            const {service, managerStatus, statusError} = this._pendingMenuData;
            this._pendingMenuData = null;
            this._rebuildMenu(service, managerStatus, statusError);
        });
    }

    update(service, managerStatus, statusError) {
        this.visible = shouldShowIndicator(service);
        if (!this.visible) {
            this._pendingMenuData = null;
            return;
        }

        const appearance = this._aggregateAppearance(service, managerStatus, statusError);
        this._setAppearance(appearance);
        if (this.menu.isOpen) {
            this._pendingMenuData = {service, managerStatus, statusError};
        } else {
            this._pendingMenuData = null;
            this._rebuildMenu(service, managerStatus, statusError);
        }
    }

    _aggregateAppearance(service, managerStatus, statusError) {
        if (service.activeState === 'failed')
            return ['network-error-symbolic', 'rmm-indicator-error'];

        if (service.activeState !== 'active') {
            if (service.activeState === 'activating' || service.activeState === 'deactivating')
                return ['emblem-synchronizing-symbolic', ''];
            return ['folder-remote-symbolic', 'rmm-indicator-stopped'];
        }

        if (statusError || !managerStatus)
            return ['network-error-symbolic', 'rmm-indicator-error'];

        const expected = managerStatus.mounts.filter(mount => !mount.paused);
        if (expected.length === 0)
            return ['media-playback-pause-symbolic', 'rmm-indicator-stopped'];

        const mounted = expected.filter(mount => mount.mounted).length;
        if (mounted === expected.length)
            return ['folder-remote-symbolic', ''];
        if (expected.every(mount => mount.status === 'starting'))
            return ['emblem-synchronizing-symbolic', ''];
        if (mounted > 0)
            return ['dialog-warning-symbolic', 'rmm-indicator-warning'];
        return ['network-error-symbolic', 'rmm-indicator-error'];
    }

    _setAppearance([iconName, styleClass]) {
        this._icon.icon_name = iconName;
        for (const name of ['rmm-indicator-warning', 'rmm-indicator-error', 'rmm-indicator-stopped'])
            this._icon.remove_style_class_name(name);
        if (styleClass)
            this._icon.add_style_class_name(styleClass);
    }

    _rebuildMenu(service, managerStatus, statusError) {
        this.menu.removeAll();

        const mounts = managerStatus?.mounts ?? [];
        const mounted = mounts.filter(mount => mount.mounted).length;
        const paused = mounts.filter(mount => mount.paused).length;
        let summary;

        if (service.activeState === 'failed')
            summary = _('Manager service failed');
        else if (service.activeState !== 'active')
            summary = _('Manager is %s').format(service.activeState);
        else if (statusError)
            summary = _('Mount status unavailable');
        else
            summary = _('%d of %d mounted').format(mounted, mounts.length);

        if (paused > 0)
            summary += _(' · %d paused').format(paused);

        this.menu.addMenuItem(new PopupMenu.PopupMenuItem(summary, {
            reactive: false,
            can_focus: false,
        }));

        for (const mount of mounts)
            this._addMountMenu(mount, service.activeState === 'active');

        if (mounts.length > 0)
            this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._addServiceActions(service);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._addFileActions(managerStatus);

        const refreshItem = new PopupMenu.PopupMenuItem(_('Refresh'));
        refreshItem.connect('activate', () => this._extension.refresh());
        this.menu.addMenuItem(refreshItem);
    }

    _addMountMenu(mount, serviceActive) {
        const item = new PopupMenu.PopupSubMenuMenuItem(
            `${mount.name} — ${statusLabel(mount)}`,
            true
        );
        const [iconName, styleClass] = mountAppearance(mount);
        if (item.icon) {
            item.icon.icon_name = iconName;
            if (styleClass)
                item.icon.add_style_class_name(styleClass);
        }

        const openMount = new PopupMenu.PopupMenuItem(_('Open Mount'));
        openMount.connect('activate', () => this._extension.openPath(mount.mount_point));
        item.menu.addMenuItem(openMount);

        const viewLog = new PopupMenu.PopupMenuItem(_('View Log'));
        viewLog.connect('activate', () => this._extension.openPath(mount.log_file));
        item.menu.addMenuItem(viewLog);

        if (serviceActive) {
            item.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

            if (mount.paused) {
                const resume = new PopupMenu.PopupMenuItem(_('Resume'));
                resume.connect('activate', () => this._extension.mountAction('resume', mount.name));
                item.menu.addMenuItem(resume);
            } else {
                const action = mount.mounted ? 'restart' : 'retry';
                const actionItem = new PopupMenu.PopupMenuItem(
                    mount.mounted ? _('Restart') : _('Retry Now')
                );
                actionItem.connect('activate', () => this._extension.mountAction(action, mount.name));
                item.menu.addMenuItem(actionItem);

                const pause = new PopupMenu.PopupMenuItem(_('Pause'));
                pause.connect('activate', () => this._extension.mountAction('pause', mount.name));
                item.menu.addMenuItem(pause);
            }
        }

        if (mount.last_error) {
            item.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            item.menu.addMenuItem(new PopupMenu.PopupMenuItem(mount.last_error, {
                reactive: false,
                can_focus: false,
            }));
        }

        this.menu.addMenuItem(item);
    }

    _addServiceActions(service) {
        if (service.activeState === 'active' || service.activeState === 'activating') {
            const stop = new PopupMenu.PopupMenuItem(_('Stop Manager'));
            stop.connect('activate', () => this._extension.serviceAction('stop'));
            this.menu.addMenuItem(stop);

            const restart = new PopupMenu.PopupMenuItem(_('Restart Manager'));
            restart.connect('activate', () => this._extension.serviceAction('restart'));
            this.menu.addMenuItem(restart);
        } else {
            const start = new PopupMenu.PopupMenuItem(_('Start Manager'));
            start.connect('activate', () => this._extension.serviceAction('start'));
            this.menu.addMenuItem(start);
        }

        const enabled = new PopupMenu.PopupSwitchMenuItem(
            _('Enable at Login'),
            isUnitEnabled(service.unitFileState)
        );
        enabled.connect('toggled', (_item, state) =>
            this._extension.serviceAction(state ? 'enable' : 'disable'));
        this.menu.addMenuItem(enabled);
    }

    _addFileActions(managerStatus) {
        const configFile = managerStatus?.config_file || this._extension.defaultConfigFile;
        const logDir = managerStatus?.log_dir || this._extension.defaultLogDir;

        const config = new PopupMenu.PopupMenuItem(_('Open Configuration'));
        config.connect('activate', () => this._extension.openPath(configFile));
        this.menu.addMenuItem(config);

        const logs = new PopupMenu.PopupMenuItem(_('Open Logs Folder'));
        logs.connect('activate', () => this._extension.openPath(logDir));
        this.menu.addMenuItem(logs);

        const journal = new PopupMenu.PopupMenuItem(_('View Service Journal'));
        journal.connect('activate', () => this._extension.openJournal());
        this.menu.addMenuItem(journal);

        const diagnostics = new PopupMenu.PopupMenuItem(_('Run Diagnostics'));
        diagnostics.connect('activate', () => this._extension.openDiagnostics());
        this.menu.addMenuItem(diagnostics);
    }
});

export default class RcloneMountManagerExtension extends Extension {
    enable() {
        this._enabled = true;
        this._refreshing = false;
        this._actionSources = new Set();
        this._cancellable = new Gio.Cancellable();
        this.binary = GLib.build_filenamev([
            GLib.get_home_dir(),
            '.local',
            'bin',
            APP_NAME,
        ]);
        this.defaultConfigFile = GLib.build_filenamev([
            GLib.get_user_config_dir(),
            APP_NAME,
            'config',
        ]);
        this.defaultLogDir = GLib.build_filenamev([
            GLib.get_user_state_dir(),
            APP_NAME,
            'logs',
        ]);

        this._indicator = new RcloneIndicator(this);
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');
        this.refresh();
        this._refreshSource = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            REFRESH_SECONDS,
            () => {
                this.refresh();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    disable() {
        this._enabled = false;
        if (this._refreshSource) {
            GLib.Source.remove(this._refreshSource);
            this._refreshSource = 0;
        }
        for (const sourceId of this._actionSources)
            GLib.Source.remove(sourceId);
        this._actionSources.clear();
        this._cancellable?.cancel();
        this._cancellable = null;
        this._indicator?.destroy();
        this._indicator = null;
    }

    async refresh() {
        if (!this._enabled || this._refreshing)
            return;

        this._refreshing = true;
        try {
            const serviceResult = await runCapture([
                'systemctl', '--user', 'show', UNIT_NAME,
                '--property=LoadState',
                '--property=ActiveState',
                '--property=SubState',
                '--property=UnitFileState',
                '--no-pager',
            ], this._cancellable);

            if (!this._enabled)
                return;

            const service = parseSystemdProperties(serviceResult.stdout);
            if (!shouldShowIndicator(service)) {
                this._indicator.update(service, null, '');
                return;
            }

            const statusResult = await runCapture(
                [this.binary, 'status', '--json'],
                this._cancellable
            );
            if (!this._enabled)
                return;

            let managerStatus = null;
            let statusError = '';
            if (statusResult.ok) {
                try {
                    managerStatus = JSON.parse(statusResult.stdout);
                } catch (error) {
                    statusError = error.message;
                }
            } else {
                statusError = statusResult.stderr.trim() || _('Status command failed');
            }

            this._indicator.update(service, managerStatus, statusError);
        } catch (error) {
            if (this._enabled && !error.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED)) {
                const service = {
                    loadState: 'loaded',
                    activeState: 'failed',
                    subState: 'failed',
                    unitFileState: 'disabled',
                };
                this._indicator.update(service, null, error.message);
            }
        } finally {
            this._refreshing = false;
        }
    }

    mountAction(action, mountName) {
        this._runAction([this.binary, 'mount', action, mountName],
            _('%s request failed').format(action));
    }

    serviceAction(action) {
        this._runAction(['systemctl', '--user', action, UNIT_NAME],
            _('Service action failed'));
    }

    async _runAction(argv, failureTitle) {
        try {
            const result = await runCapture(argv, this._cancellable);
            if (!result.ok) {
                Main.notify(failureTitle, result.stderr.trim() || result.stdout.trim());
                return;
            }
            const sourceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
                this._actionSources.delete(sourceId);
                this.refresh();
                return GLib.SOURCE_REMOVE;
            });
            this._actionSources.add(sourceId);
        } catch (error) {
            if (this._enabled)
                Main.notify(failureTitle, error.message);
        }
    }

    openPath(path) {
        if (!path)
            return;
        this._runAction(['gio', 'open', path], _('Could not open path'));
    }

    openJournal() {
        this._openTerminal(['journalctl', '--user', '-u', UNIT_NAME, '-f']);
    }

    openDiagnostics() {
        this._openTerminal([this.binary, 'doctor', '--wait']);
    }

    _openTerminal(command) {
        let argv;
        if (GLib.find_program_in_path('kgx'))
            argv = ['kgx', '--', ...command];
        else if (GLib.find_program_in_path('gnome-terminal'))
            argv = ['gnome-terminal', '--', ...command];
        else if (GLib.find_program_in_path('x-terminal-emulator'))
            argv = ['x-terminal-emulator', '-e', ...command];
        else {
            Main.notify(_('No terminal found'), command.join(' '));
            return;
        }

        try {
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        } catch (error) {
            Main.notify(_('Could not open terminal'), error.message);
        }
    }
}
