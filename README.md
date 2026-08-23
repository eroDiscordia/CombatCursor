# CombatCursor

**Version 2.2.3** — for Project Ascension (Conquest of Azeroth), WotLK 3.3.5 client.

Highlights your mouse cursor with a bright, customizable ring so it's never lost
in the middle of a fight. Fully configurable in-game, either through a settings
panel or the `/ccursor` command line.

## Installation

1. Unzip the `CombatCursor` folder.
2. Drop it into `<Ascension client folder>\Interface\AddOns\`.
3. Restart the client (or `/reload`) and make sure it's enabled at the
   character-select AddOns list.

## Opening the settings

- **In-game menu:** Escape → Interface → AddOns → **CombatCursor**
- **Command line:** `/ccursor config`

## Settings

The panel is laid out in two columns and scrolls if it overflows the window.

| Setting | Description |
|---|---|
| Enable cursor enhancement | Master on/off switch for the whole addon. |
| Preview cursor enhancement | Shows the cursor highlight live while checked, without needing to be in combat. Automatically unchecks when the panel closes. |
| Show only in combat | When checked, the highlight only appears in combat. When unchecked, it's always visible. |
| Cursor Color | Opens the color picker for the highlight's color. |
| Cursor Size | Overall diameter of the highlight. |
| Cursor Opacity | Overall transparency of the highlight. |
| Outline Size | Ring thickness, 1 (thin) to 5 (thick). |
| Outline Opacity | Transparency of the ring specifically. |
| Pulse Amount | How much the highlight grows during its pulse animation. |
| Enable click effect | Shows a ring that briefly expands and fades from your cursor on left-click. |
| Enable cursor pulse | Makes the highlight gently grow and shrink on a loop. |
| Enable cursor trail | Leaves a short fading trail of ghost copies behind the cursor as it moves. |
| Enable center dot | Adds a solid dot in the middle of the highlight (same color/opacity as the cursor). Combined with a thick outline, this can make the highlight look like one solid filled circle — that's expected. |

## Command line (`/ccursor`)

All settings can also be changed without opening the GUI:

| Command | Effect |
|---|---|
| `/ccursor config` | Opens the settings GUI (also `options` or `gui`). |
| `/ccursor size <number>` | Sets cursor size. |
| `/ccursor color <r> <g> <b>` | Sets cursor color, each value 0–1. |
| `/ccursor always` | Toggles combat-only vs. always-on. |
| `/ccursor enable` | Turns the addon on. |
| `/ccursor disable` | Turns the addon off. |
| `/ccursor test` | Toggles a live preview on/off. |
| `/ccursor status` | Prints all current settings and state. |
| `/ccursor debug` | Toggles debug event logging in chat. |

Running `/ccursor` with no arguments (or an unrecognized one) prints this list in-game.

## Notes

- Settings are saved per-character via `CombatCursorDB` and persist across
  sessions (written to disk on `/reload` or logout).
- Built entirely on assets bundled with the addon (`Textures/`) rather than
  the client's built-in art, and avoids the `Animation` "Alpha" type — both
  needed to work reliably on Ascension's custom client. See
  `ASCENSION_CLIENT_NOTES.md` in the `AddonGUITemplate` reference package if
  you're building other addons for this client and want the full list of
  known quirks.

## Version history

- **2.2.1** — Right column pulled in from the panel edge; Pulse Amount moved
  to its own row under Outline Opacity.
- **2.2.0** — Redesigned settings panel to a two-column layout; Center Dot
  moved into the Effects list.
- **2.1.1** — Added scroll frame so settings no longer overflow the panel.
- **2.1.0** — Added Preview Cursor toggle, Pulse Amount slider, tooltips,
  Outline sub-heading; fixed a cursor-trail indexing bug and made the click
  effect more visible.
- **2.0.0 – 2.0.3** — Added the full settings GUI; fixed load-order/frame-
  naming/animation-API issues specific to this client.
- **1.0.1** — Switched to a bundled ring texture after discovering the
  client doesn't ship some standard Blizzard texture paths.
- **1.0.0** — Initial release: combat-only pulsing cursor ring via
  `/ccursor` commands only.
