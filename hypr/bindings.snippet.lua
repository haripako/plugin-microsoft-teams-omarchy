-- Append to ~/.config/hypr/bindings.lua

-- Microsoft Teams (web app). Sigue la convencion SUPER+SHIFT+<letra> de las apps
-- de Omarchy. El patron "chrome-teams" hace match con la clase de ventana
-- chrome-teams.microsoft.com__-Default y enfoca la ventana si ya esta abierta.
o.bind("SUPER + SHIFT + T", "Teams", "omarchy-launch-or-focus-webapp chrome-teams https://teams.microsoft.com")

-- Ocultar/mostrar Teams sin cerrarlo, equivalente a Cmd+H en macOS.
-- Delega en el plugin fvargas.teams, que aparca la ventana en un workspace
-- especial y la devuelve al workspace activo al restaurarla.
o.bind("SUPER + H", "Hide/show Teams", "omarchy-shell -q fvargas.teams toggle")
