# Item Sorter (Scrap Mechanic Survival)

UUID: `d4f8b2c1-7a39-4e6f-91b0-5c8d2e4a7f13`

## Ne yapar
IN (+Y) tarafındaki dump chest’lerden itemleri alır; OUT (−Y) tarafındaki hedef chest’lere ayırır.

- Hedef chest’te **örnek item** varsa → sadece o tipleri alır
- **Boş** hedef chest → overflow (eşleşmeyenler buraya)
- Sorter üzerinde E → isteğe bağlı global filtre (boş = hepsi)
- Logic switch bağlarsan: parent active iken çalışır; bağlı değilse her zaman ON

## Craft
Craftbot → **Item Sorter** — 5× Metal Block Level 1

## Kurulum (Vortex)
1. Bu klasörü `ItemSorter-VAULT-1.0.0` olarak Vortex mods altına kopyala
2. Survival overlay dosyalarını da oyuna yaz (deploy script)
3. Deploy / oyunu Vortex ile aç

## Model
Custom sorter mesh wired in (not placeholder):
- `Survival/Objects/Mesh/interactive/obj_interactive_itemsorter.fbx` (UnitScaleFactor=1, ~25k tris)
- TGA 1024 DifAsgNor under `Survival/Objects/Textures/interactive/`
- `.rend` subMeshMap key: `itemsorter`
- AABB ≈ X 1.64, Y 2.92 (pipe ±Y), Z 2.20
