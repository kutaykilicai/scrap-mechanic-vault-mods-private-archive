# Deploy ItemSorter-VAULT to Kasa PC
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not (Test-Path "$src\mod_info.json")) { throw "Run from ItemSorter-VAULT-1.0.0 folder" }

$game = 'F:\Steam_Library\steamapps\common\Scrap Mechanic'
$vortex = 'C:\Users\Kutay\AppData\Roaming\Vortex\scrapmechanic\mods\ItemSorter-VAULT-1.0.0'

if (-not (Test-Path $game)) { throw "Scrap Mechanic not found at $game" }

if (Test-Path $vortex) { Remove-Item $vortex -Recurse -Force }
New-Item -ItemType Directory -Path $vortex -Force | Out-Null
Copy-Item -Path "$src\*" -Destination $vortex -Recurse -Force
Write-Host "Vortex staging: $vortex"

$pairs = @(
  @('Survival\Scripts\game\interactables\ItemSorter.lua', 'Survival\Scripts\game\interactables\ItemSorter.lua'),
  @('Survival\Objects\Database\ShapeSets\itemsorter.shapeset', 'Survival\Objects\Database\ShapeSets\itemsorter.shapeset'),
  @('Survival\Objects\Database\shapesets.json', 'Survival\Objects\Database\shapesets.json'),
  @('Survival\Objects\Renderable\interactive\obj_interactive_itemsorter.rend', 'Survival\Objects\Renderable\interactive\obj_interactive_itemsorter.rend'),
  @('Survival\Objects\Mesh\interactive\obj_interactive_itemsorter.fbx', 'Survival\Objects\Mesh\interactive\obj_interactive_itemsorter.fbx'),
  @('Survival\Objects\Textures\interactive\obj_interactive_itemsorter_dif.tga', 'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_dif.tga'),
  @('Survival\Objects\Textures\interactive\obj_interactive_itemsorter_asg.tga', 'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_asg.tga'),
  @('Survival\Objects\Textures\interactive\obj_interactive_itemsorter_nor.tga', 'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_nor.tga'),
  @('Survival\CraftingRecipes\craftbot\craftbot_small_pipes.json', 'Survival\CraftingRecipes\craftbot\craftbot_small_pipes.json'),
  @('Survival\Gui\Language\English\inventoryDescriptions.json', 'Survival\Gui\Language\English\inventoryDescriptions.json'),
  @('Survival\Gui\IconMapSurvival.xml', 'Survival\Gui\IconMapSurvival.xml')
)
foreach ($p in $pairs) {
  $from = Join-Path $src $p[0]
  if (-not (Test-Path $from)) { throw "Missing $from" }
  $to = Join-Path $game $p[1]
  $dir = Split-Path $to -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $to) { Copy-Item $to "$to.bak-itemsorter" -Force }
  Copy-Item $from $to -Force
  Write-Host "Wrote $to"
}
Write-Host "DONE. Enable Item Sorter in Vortex, Deploy, relaunch."
