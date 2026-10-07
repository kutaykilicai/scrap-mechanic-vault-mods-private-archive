# BUILD — BrakeLight-VAULT 1.0.0

Built on the box 2026-10-05 (Europe/Istanbul). **Not deployed. Kasa not read or written.**

## Design
Brake Relay = new scripted part, uuid `da5a8854-9644-4b8c-98e7-2efdf3c8cb64`, class `BrakeLightVault`.
- `connectionInput = power` (the Driver's Seat's engine output type), `maxParentCount = 1`.
- `connectionOutput = logic` (what vanilla lights accept), `maxChildCount = 255`.
- `server_onFixedUpdate`: `parent:getSteeringPower()` (fallback `getPower()`); `< -0.05` (S) → `setActive(true)`, `setPower(1)`; else off. Writes only on change.
- Client: vanilla logic-gate screen frame 1/7 (OR off/on) + pose weight 0/1 for the lit look. Visual only.
- No storage, no GUI layout, no global hooks, no `dofile`, no world/game script events.

Prior art (same API pattern, Survival-based): Raft Mechanic `WASDConverter.lua` (power in from seat, `getSteeringPower()`, logic out) and TechnologicNick WASD-Converter (`S_Converter` = inverted `getSteeringPower`).

Mesh: vanilla `$GAME_DATA/Objects/Renderable/Interactive/obj_interactive_logicgate.rend` with vanilla logic-gate placement fields (box 1x1x1, `rotationSet PropYZ`). Same renderable+scripted combination is used by many public mods (SMLogicToolsMod, ScrapComputers template). No custom mesh/texture. No Nexus art. Not the radio/beacon path that broke MapViewer.

## Why 4 shared files still get one line each
Survival has no mod loader: a part must be in `shapesets.json`; Crafter only reads fixed recipe files (craftbot_core/manmade/small_pipes/...); a recipe is craftable only if unlocked in `RecipeManager.lua` (DefaultUnlockedItems) or research. All three (+ inventoryDescriptions for the name) are already owned by ItemPump-VAULT. So no full overlay is shipped. `tools/brakelight_patch.py` inserts ONE marked line into the live file at deploy time and can remove exactly that line.

| File | Inserted line (anchor) |
| --- | --- |
| shapesets.json | `"$SURVIVAL_DATA/Objects/Database/ShapeSets/brakelight_vault.shapeset",` after itempump line (else before first entry) |
| RecipeManager.lua | `sm.uuid.new( "da5a8854-…" ), -- obj_interactive_brakelight_vault (BrakeLight-VAULT)` after ItemPump uuid inside DefaultUnlockedItems (else first line of the table) |
| craftbot_small_pipes.json | one-line recipe object after `[` |
| inventoryDescriptions.json | one-line `"da5a8854-…": {"title": "Brake Relay", …},` after `{` |

Patcher guarantees: aborts before writing anything if ItemPump.lua ≠ `9171e16adb9e5cfd8a119cf93e47caa4` or ItemFilter.lua ≠ `b8e2e2db683dfcb05da08ca50b8927b7` or the 2 unique files are not in the game dir yet; verifies each result parses and equals old + exactly our element; keeps BOM and CRLF/LF; writes in place (keeps hardlinks); one-time `.bak-brakelight-1.0.0` backups; idempotent add/remove.

## Box tests (all passed)
- `luajit -bl` syntax OK for BrakeLightVault.lua and for patched RecipeManager.lua.
- Mocked `sm` run: no parent / idle / W → off; S → active, power 1, uv 7, pose 1; release → off; `getSteeringPower` error → `getPower` fallback works.
- Sim game dir from box ItemPump-VAULT copy: add → 4 one-line diffs; 2nd add = SKIP; remove → all 4 files byte-identical to original (MD5); 2nd remove = SKIP; hardlinked twin also got the line (in-place write).
- CRLF variant (live/ snapshot files): CRLF kept, round-trip byte-identical.
- itempump line last without comma + no ItemPump uuid in RecipeManager: fallback anchors, valid JSON, round-trip identical.
- Guard MD5 mismatch → ABORT, nothing written. Missing unique file → ABORT, nothing written.

## Not in the package
Any full `shapesets.json` / `RecipeManager.lua` / `craftbot_small_pipes.json` / `inventoryDescriptions.json` / `IconMapSurvival.xml`, ItemPump/ItemFilter files, terrain, Overworld, SurvivalGame, Mod Manager. No icon entry (IconMapSurvival.xml is ItemPump-owned) → icon may show blank.
