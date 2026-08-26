-- Append to ~/.config/hypr/bindings.lua

-- Open or focus Teams. Follows Omarchy's SUPER+SHIFT+<letter> convention for
-- applications. The pattern "chrome-teams" matches the window class
-- chrome-teams.microsoft.com__-Default; note that omarchy-launch-or-focus
-- builds word-boundary regexes, so "teams.microsoft.com" would NOT match --
-- there is no word boundary between "com" and "_".
o.bind("SUPER + SHIFT + T", "Teams", "omarchy-launch-or-focus-webapp chrome-teams https://teams.microsoft.com")

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
-- ~/.local/bin.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "omarchy-teams-close")
