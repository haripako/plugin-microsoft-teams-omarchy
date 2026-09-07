-- Append to ~/.config/hypr/bindings.lua

-- Open or focus Teams. Follows Omarchy's SUPER+SHIFT+<letter> convention for
-- applications.
--
-- This delegates to the widget instead of naming a launch command, so the
-- binding works the same whether Teams is the web app or a native client: the
-- widget already knows how to start it (`launchCommand`) and how to find its
-- window (`matchClass`). Duplicating the launch command here is what makes a
-- switch to a native client half-work -- the icon drives the native client
-- while the keybinding keeps opening the web app.
--
-- `show` launches Teams when it is not running, and otherwise brings the
-- existing window to the front, which is what a launch-or-focus binding is
-- for.
o.bind("SUPER + SHIFT + T", "Teams", "omarchy-shell -q teams show")

-- If you would rather not route the keybinding through the widget, the web-app
-- equivalent is below. Note that omarchy-launch-or-focus builds word-boundary
-- regexes, so "teams.microsoft.com" would NOT match -- there is no word
-- boundary between "com" and "_". For a native client the pattern is its
-- window class and the command is its binary, e.g.
-- `omarchy-launch-or-focus teams-for-linux`.
--
-- o.bind("SUPER + SHIFT + T", "Teams", "omarchy-launch-or-focus-webapp chrome-teams https://teams.microsoft.com")

-- Hide/show Teams without quitting it, the equivalent of Cmd+H on macOS.
-- Delegates to the plugin, which parks the window on a special workspace.
o.bind("SUPER + H", "Hide/show Teams", "omarchy-shell -q teams toggle")

-- SUPER+W leaves Teams running in the background instead of closing it: the
-- window is parked and the bar icon stays live. Every other window closes as
-- usual. To actually quit Teams, use the bar icon's menu (right-click).
--
-- The unbind is required, not optional. SUPER+W already carries Omarchy's
-- "Close window" binding, and binding a key twice does not replace the old
-- binding -- it STACKS. Without this line Hyprland runs both, so Teams would
-- be hidden and then closed.
--
-- Requires bin/omarchy-teams-close on your PATH; install.sh puts it in
-- ~/.local/bin. It reads the widget's `matchClass` from shell.json, so it
-- needs no editing when you point the widget at a native client.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "omarchy-teams-close")
