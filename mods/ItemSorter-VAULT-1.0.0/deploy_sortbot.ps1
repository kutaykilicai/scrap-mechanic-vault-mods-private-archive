$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$game = 'F:\Steam_Library\steamapps\common\Scrap Mechanic'
$vortex = 'C:\Users\Kutay\AppData\Roaming\Vortex\scrapmechanic\mods\ItemSorter-VAULT-1.0.0'
if (-not (Test-Path $game)) { throw "Scrap Mechanic missing: $game" }

if (Test-Path $vortex) { Remove-Item $vortex -Recurse -Force }
New-Item -ItemType Directory -Path $vortex -Force | Out-Null
Copy-Item -Path "$src\*" -Destination $vortex -Recurse -Force
Write-Host "Vortex staged: $vortex"

$rels = @(
  'Survival\Scripts\game\interactables\ItemSorter.lua',
  'Survival\Objects\Database\ShapeSets\itemsorter.shapeset',
  'Survival\Objects\Database\shapesets.json',
  'Survival\Objects\Renderable\interactive\obj_interactive_itemsorter.rend',
  'Survival\Objects\Mesh\interactive\obj_interactive_itemsorter.fbx',
  'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_dif.tga',
  'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_asg.tga',
  'Survival\Objects\Textures\interactive\obj_interactive_itemsorter_nor.tga',
  'Survival\CraftingRecipes\craftbot\craftbot_small_pipes.json',
  'Survival\Gui\Language\English\inventoryDescriptions.json',
  'Survival\Gui\IconMapSurvival.xml'
)
foreach ($rel in $rels) {
  $from = Join-Path $src $rel
  if (-not (Test-Path $from)) { Write-Host "SKIP $rel"; continue }
  $to = Join-Path $game $rel
  $dir = Split-Path $to -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $to) { Copy-Item $to "$to.bak-sortbot" -Force }
  Copy-Item $from $to -Force
  Write-Host "Wrote $rel"
}

# Merge Sortbot into dispenser.json via Python for clean JSON
$py = @'
import json
from pathlib import Path
game = Path(r"F:\Steam_Library\steamapps\common\Scrap Mechanic")
disp = game / "Survival" / "CraftingRecipes" / "dispenser.json"
entry = json.loads(Path(r"ENTRYPATH").read_text(encoding="utf-8"))
raw = disp.read_text(encoding="utf-8")
lines = [ln for ln in raw.splitlines() if not ln.strip().startswith("//")]
data = json.loads("\n".join(lines))
uuid = entry["itemId"]
data = [e for e in data if e.get("itemId") != uuid]
data.append(entry)
text = "// this file is generated\n" + json.dumps(data, indent="\t") + "\n"
disp.write_bytes(text.encode("utf-8"))  # no BOM
print("dispenser entries", len(data), "sortbot", uuid)
'@
$entryPath = Join-Path $src 'Survival\CraftingRecipes\dispenser_sortbot_entry.json'
$py = $py.Replace('ENTRYPATH', $entryPath.Replace('\','\\'))
$tmpPy = Join-Path $env:TEMP 'merge_dispenser_sortbot.py'
Set-Content -Path $tmpPy -Value $py -Encoding UTF8
python $tmpPy
if ($LASTEXITCODE -ne 0) { throw "dispenser merge failed" }

Write-Host "DONE. Fully quit Scrap Mechanic and relaunch. Craft Sortbot at Mechanic Station."
