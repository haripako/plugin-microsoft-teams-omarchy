-- Append to the END of ~/.config/hypr/hyprland.lua
-- (after the hyprmoncfg dofile, so nothing overrides it)

-- Teams vive siempre en el workspace 1 del portatil.
-- La primera regla ancla el workspace 1 a eDP-1: sin ella Hyprland lo coloca
-- en el monitor donde se abriera primero, que varia entre arranques.
-- Va al final del fichero, despues del dofile de hyprmoncfg, para que nada
-- lo sobrescriba.
hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
o.window("^chrome-teams", { workspace = "1" })
