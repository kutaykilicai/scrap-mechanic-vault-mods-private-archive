# BrakeLight-VAULT 1.0.0 — deploy to Kasa (DRAFT, run only with game fully closed)
# Order: copy 2 unique files -> add 1 line to 4 shared files (python, verified) -> Vortex staging (unique files only).
# Never writes ItemPump.lua / ItemFilter.lua; aborts if their MD5 is not the expected one.
$ErrorActionPreference = 'Stop'
$Desktop    = 'C:\Users\Kutay\Desktop'
$Game       = 'F:\Steam_Library\steamapps\common\Scrap Mechanic'
$VortexMods = 'C:\Users\Kutay\AppData\Roaming\Vortex\scrapmechanic\mods'
$Name       = 'BrakeLight-VAULT-1.0.0'
$Zip        = Join-Path $Desktop "$Name.zip"
$Bak        = 'bak-brakelight-1.0.0'

$sm = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'Scrap.?Mechanic|ScrapMechanic' }
if ($sm) { throw "Scrap Mechanic still running: $($sm.ProcessName -join ',')" }
if (-not (Test-Path $Zip)) { throw "Missing $Zip" }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'python not on PATH' }

$src = Join-Path $Desktop $Name
if (Test-Path $src) { Remove-Item $src -Recurse -Force }
Expand-Archive -Path $Zip -DestinationPath $Desktop -Force
if (-not (Test-Path (Join-Path $src 'mod_info.json'))) { throw "Expand failed: $src" }
$py = Join-Path $src 'tools\brakelight_patch.py'

Write-Host '=== 0) PRE-CHECK ==='
python $py check --game $Game

Write-Host '=== 1) Unique files -> game ==='
$unique = @(
  'Survival\Objects\Database\ShapeSets\brakelight_vault.shapeset',
  'Survival\Scripts\game\interactables\BrakeLightVault.lua'
)
foreach ($rel in $unique) {
  $from = Join-Path $src $rel; $to = Join-Path $Game $rel
  if (-not (Test-Path $from)) { throw "Missing in package: $rel" }
  if ((Test-Path $to) -and -not (Test-Path "$to.$Bak")) { Copy-Item $to "$to.$Bak" -Force; Write-Host "BACKUP $to.$Bak" }
  Copy-Item $from $to -Force
  Write-Host "WROTE $rel ($((Get-Item $to).Length))"
}

Write-Host '=== 2) +1 line in shared files (verified, idempotent) ==='
python $py add --game $Game
if ($LASTEXITCODE -ne 0) { throw 'patch add aborted (shared files untouched). Unique files are inert without registration.' }

Write-Host '=== 3) Vortex staging (unique files + docs only; NO shared overlays) ==='
$vs = Join-Path $VortexMods $Name
if (Test-Path $vs) { Remove-Item $vs -Recurse -Force }
New-Item -ItemType Directory -Path $vs -Force | Out-Null
foreach ($rel in $unique + @('mod_info.json','README.md','VAULT_META.json')) {
  $to = Join-Path $vs $rel
  New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null
  Copy-Item (Join-Path $src $rel) $to -Force
}
Write-Host "STAGED $vs"

Write-Host '=== 4) VERIFY ==='
python $py check --game $Game
$shared = @(
  'Survival\Objects\Database\shapesets.json',
  'Survival\Scripts\game\managers\RecipeManager.lua',
  'Survival\CraftingRecipes\craftbot\craftbot_small_pipes.json',
  'Survival\Gui\Language\English\inventoryDescriptions.json'
)
foreach ($rel in $shared) {
  $links = (& fsutil hardlink list (Join-Path $Game $rel) 2>$null | Measure-Object).Count
  Write-Host "HARDLINKS $links  $rel"
}
Get-FileHash (Join-Path $Game 'Survival\Scripts\game\interactables\ItemPump.lua') -Algorithm MD5 | ForEach-Object { Write-Host "ItemPump.lua $($_.Hash)" }
Get-FileHash (Join-Path $Game 'Survival\Scripts\game\interactables\ItemFilter.lua') -Algorithm MD5 | ForEach-Object { Write-Host "ItemFilter.lua $($_.Hash)" }
Write-Host 'DEPLOY BRAKELIGHT COMPLETE'
