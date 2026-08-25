-- Append to ~/.config/hypr/bindings.lua

-- Microsoft Teams (web app). Sigue la convencion SUPER+SHIFT+<letra> de las apps
-- de Omarchy. El patron "chrome-teams" hace match con la clase de ventana
-- chrome-teams.microsoft.com__-Default y enfoca la ventana si ya esta abierta.
o.bind("SUPER + SHIFT + T", "Teams", "omarchy-launch-or-focus-webapp chrome-teams https://teams.microsoft.com")

-- Ocultar/mostrar Teams sin cerrarlo, equivalente a Cmd+H en macOS.
-- Delega en el plugin fvargas.teams, que aparca la ventana en un workspace
-- especial y la devuelve al workspace activo al restaurarla.
o.bind("SUPER + H", "Hide/show Teams", "omarchy-shell -q fvargas.teams toggle")

-- SUPER+W deja Teams en segundo plano en vez de cerrarlo, como en macOS: la
-- ventana se aparca y el icono de la barra sigue vivo. El resto de ventanas se
-- cierran igual que siempre. Para cerrar Teams de verdad: clic derecho en el
-- icono de la barra.
--
-- SUPER+W ya venia enlazado a "Close window", asi que hay que desenlazarlo
-- antes; si no, Hyprland ejecutaria las dos acciones (ocultar Y cerrar).
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "omarchy-teams-close")
