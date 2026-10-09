# BUILD — FlyNoclip-VAULT 1.0.0

Built on the box 2026-10-09 (Europe/Istanbul). **Not deployed. Kasa not read or written.**

## Why a part, not /fly chat commands
`sm.game.bindChatCommand` only works from the game script (`SurvivalGame.lua`). Hooking it means shipping a full `SurvivalGame.lua` overlay — forbidden (structure-adjacent, breaks on game updates, and the user asked not to touch Survival scripts). No package on the box injects into the game script either (ClearRain is particle JSON only). So fallback: placeable scripted part, vanilla Survival beacon mesh (proven placeable in MapViewer 1.0.1).

## Mechanism (API-verified against public Survival sources)
- Flight: `character:setSwimming(true)` + `character:setDiving(true)` outside water = free 3D swim along camera. Same as MT-Fast-Logic `FlightController.lua` (swimPermadive) and Super Sunshakes Fly Mod.
- Speed: `character.publicData.waterMovementSpeedFraction`; vanilla `BaseCharacter.lua` copies it into `character.movementSpeedFraction` (host). Non-host clients get `clientPublicData` via `cl_speed`.
- Re-asserted every server tick only while someone is flying (WaterManager resets swim on exiting water). Setters only called on change.
- Off: Ctrl double-tap (`character:isCrouching()` rising edges ≤ 0.5 s; WaterManager reads isCrouching while swimming so it is exposed), E on part, carrying auto-off, part destroy/unload cleanup. Restores swimming/diving false + speed 1.0 (vanilla WaterManager default).
- Noclip: no character-collision toggle exists in the Lua API. Implemented as blink: sprinting + pushing (velocity < 0.6) into a solid ray-hit within 1.2 m for 8 ticks → scan 1–8 m along view for a free spot (ray back toward the wall must hit its far face = not inside the solid; 6 axis rays clear) → `sm.character.createCharacter` + `player:setCharacter` (SurvivalGame `/goto` / recreate pattern). pcall; on error `phaseBroken` and flight continues.

## Box tests
- `luac5.1 -p` and `luajit -bl`: FlyNoclipVault.lua OK. JSON files parse.
- Mocked `sm` run: off → nothing touched; fly on (swim+dive, speed 3.5); Shift → 7.0; noclip blinks through a 1 m wall to first free spot; Ctrl x2 → off and restored; speed cycle; onDestroy cleanup; createCharacter error → phaseBroken, flight stays; carry → auto-off.
- Patcher on a sim game dir (box ItemPump-VAULT copy + desk ItemFilter.lua): abort when unique files missing; add → 4 one-line diffs, JSON valid, RecipeManager parses (BOM preserved); 2nd add SKIP; remove → all files byte-identical (MD5) to before.

## Not tested
Anything in the real game. See README "Bilinen sınırlar".

## 1.0.1 (2026-10-09, after Kutay's in-game test)
- In game: beacon appears and flight works; Ctrl double-tap did NOT turn flight off; speed too slow.
- SPEEDS x2.75 (5.5/9.5/16.5/27.5), default level 2, sprint multiplier 2 unchanged.
- Off gestures: look-nod (direction only, always replicated), Shift tap-tap (holding Shift to boost does not count), Ctrl tap-tap kept as backup, E on part.
- Checked: `sm.interactable.actions` / `client_onAction` only reach an interactable the character is locked to (seat-style). The Survival player script only exposes `client_onInteract`/`client_onCancel`. No overlay-safe global key hook exists without editing SurvivalPlayer.lua, so none is used.
- Debug: sprint/crouch state changes printed to the game console while flying.
- `tools/mock_test.lua` (luajit) covers: speeds, hold-Shift not off, Shift x2 off, Ctrl x2 off, nod off, half/slow nod stays on, phase, phase failure, carry off, destroy cleanup.
