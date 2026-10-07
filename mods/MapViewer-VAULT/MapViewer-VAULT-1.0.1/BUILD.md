# BUILD — Map Viewer VAULT 1.0.1

## BUGFIX 1.0.1 (2026-10-04, Europe/Istanbul)

Not deployed. Shapeset only.

Root cause of blank icon, empty hand, and no place preview: `obj_interactive_radio.rend` is a Creative pose-anim mesh that expects a built-in `radio` component. MapViewer attached `scripted` MapViewerVault and did not add `radio`. The part failed to become a placeable shape. `restrictions.usable` is not the blocker (ItemPump places with the same flag). File existence of radio.rend was not the bug.

1.0.1 copies Survival beacon placement fields and renderable. No `radio` block. UUID `13c7d07c-9b83-4a53-aabd-9a36bf1e886a` and `MapViewerVault.lua` unchanged. ItemPump/ItemFilter not touched. ItemPump.lua MD5 `9171e16adb9e5cfd8a119cf93e47caa4`.

shapeset MD5 `41051c20ae1853c13693da5010ef74fe`
lua MD5 `755f0ea9d8b4cdbbaeb7490d8a994c8c`

Vanilla beacon.rend confirmed on Kasa at `Survival\Objects\Renderable\interactive\obj_interactive_beacon.rend`. Box/sticky/rotationSet match `beacon.shapeset` (box 3x8x4, sticky `-Y+X-X-Z+Z`, rotationSet `PropY`). Extra vs vanilla beacon: `showInInventory` and `restrictions.usable` (same pattern as ItemPump, which places).

E while held does nothing. After place, E calls `client_onInteract`.


Date: 2026-10-04 (Europe/Istanbul). Built on the box. **Not deployed.**

## Why this shape

Official Nexus 52 streams terrain by handlers Mod Manager inserts into `Overworld.lua` (`sv_e_mapViewerLoadCells` and friends). That path was refused. A Vortex folder of the official payload cannot open cells by itself.

This package is a new interactable (`MapViewerVault`, uuid `13c7d07c-9b83-4a53-aabd-9a36bf1e886a`). Press E. No handheld tool, no camera takeover, no cell streaming.

Official zip under `extracted-mapviewer/` was read only for feature limits (bird's-eye, markers, fullscreen). No png, dae, rend, tga, or layout from that zip was copied. 1.0.0 mesh was the vanilla radio renderable (replaced in 1.0.1).

## Kimi

Runner: `/workspace/moonshot/kimi_swarm.py`.

| Call | Model | Result |
| --- | --- | --- |
| `kimi_mapviewer_job.jsonl` | `kimi-k2.6`, reasoning low, timeout 120s, 2 tries | **TimeoutError** both tries. No review text. `kimi_mapviewer_out.jsonl`. |
| `kimi_mapviewer_job2.jsonl` | `kimi-k3`, reasoning low, timeout 180s | **OK** (content exactly `OK`). 2561 prompt tokens, 409 reasoning tokens. `kimi_mapviewer_out2.jsonl`. |

Before the second call the script was adjusted locally: do not rebuild the GUI on refresh if it exists; `sendToServer` always sends a table; reassign `self.storage.waypoints` after add/remove so the save table is written. Kimi did not request further edits. No terrain or Overworld code was added from either call.

## Overlays that are full files

These four are supersets of the box copy of `ItemPump-VAULT-1.0.0` (pump + sorter lines kept). The ItemPump folder was not written. ItemPump.lua MD5 still `9171e16adb9e5cfd8a119cf93e47caa4`.

- `Survival/Objects/Database/shapesets.json` — plus `mapviewer_vault.shapeset`
- `Survival/Scripts/game/managers/RecipeManager.lua` — plus this uuid in the default unlock list
- `Survival/CraftingRecipes/craftbot/craftbot_small_pipes.json` — plus 5x `8aedf6c2-…` and 1x circuit board `f152e4df-…`
- `Survival/Gui/Language/English/inventoryDescriptions.json` — plus the Map Viewer title

If Vortex lets ItemPump win those paths, the terminal will not be in the shape list or the craft list. Enable this mod so it wins, or merge the one new line back.

Not in the package: `terrain_overworld.lua`, `Overworld.lua`, `SurvivalGame.lua`, `SurvivalPlayer.lua`, Foliage Eraser, Mod Manager, installers.
