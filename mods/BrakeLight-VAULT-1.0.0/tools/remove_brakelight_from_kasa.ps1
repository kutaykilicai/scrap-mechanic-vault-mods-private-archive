# BrakeLight-VAULT 1.0.0 — remove from Kasa (DRAFT, game fully closed)
# Pick up placed Brake Relays from vehicles BEFORE running this; otherwise they vanish from the creation on next load.
$ErrorActionPreference = 'Stop'
$Desktop    = 'C:\Users\Kutay\Desktop'
$Game       = 'F:\Steam_Library\steamapps\common\Scrap Mechanic'
$VortexMods = 'C:\Users\Kutay\AppData\Roaming\Vortex\scrapmechanic\mods'
$Name       = 'BrakeLight-VAULT-1.0.0'
$sm = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Scrap.?Mechanic|ScrapMechanic' }
if ($sm) { throw "Scrap Mechanic still running: $($sm.ProcessName -join ',')" }
$py = Join-Path $Desktop "$Name\tools\brakelight_patch.py"
if (-not (Test-Path $py)) { throw "Missing $py (expand the zip to Desktop first)" }

# 1) take the 4 single lines out FIRST (so the game never lists a missing shapeset)
python $py remove --game $Game
if ($LASTEXITCODE -ne 0) { throw 'patch remove aborted; nothing deleted' }
# 2) then delete the 2 unique files
foreach ($rel in @('Survival\Objects\Database\ShapeSets\brakelight_vault.shapeset','Survival\Scripts\game\interactables\BrakeLightVault.lua')) {
  $p = Join-Path $Game $rel
  if (Test-Path $p) { Remove-Item $p -Force; Write-Host "DELETED $rel" } else { Write-Host "MISS $rel" }
}
# 3) Vortex staging
$vs = Join-Path $VortexMods $Name
if (Test-Path $vs) { Remove-Item $vs -Recurse -Force; Write-Host "REMOVED $vs" }
python $py check --game $Game
Write-Host 'REMOVE BRAKELIGHT COMPLETE'
