## Herdr
If `$HC_TERMINAL_ID` is set, this session runs inside Herdr, as terminal `$HC_TERMINAL_ID`.
- Run `hc --skill` before starting, reading or messaging other terminals or agents.
  For delegated agents use `hc run --bg`, and have them report back with `hc send $HC_TERMINAL_ID`.
- Run `herdr-app --skill` and read `~/.config/herdr-app/AGENTS.md` before changing the
  window, layouts, keys or mods. Don't edit AGENTS.md or the .d.ts files; the app rewrites them.
- Remote machines: `hc machine ls` (pi.local is connected).
