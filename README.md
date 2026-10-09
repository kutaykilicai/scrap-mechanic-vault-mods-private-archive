# Scrap Mechanic VAULT mods

<p align="center">
  <img src="docs/photos/01.jpg" width="280" alt="Scrap Mechanic base"/>
  <img src="docs/photos/02.jpg" width="280" alt="Scrap Mechanic farm"/>
  <img src="docs/photos/03.jpg" width="280" alt="Scrap Mechanic lift"/>
</p>

Kutay Kılıç — Scrap Mechanic Survival mod paketleri (SM-Bot / VAULT).

## Aktif / önerilen

| Mod | Klasör | Not |
| --- | --- | --- |
| **ItemPump-VAULT** | `mods/ItemPump-VAULT-1.0.0` | noloop MD5 `9171e16adb9e5cfd8a119cf93e47caa4` |
| **ItemFilter** | `mods/ItemFilter-51-0.0.20260828` (Vortex `ItemFilter-51-0.0.20260828`) | id-fix MD5 `cd864de817040f1227c957b84913b589` (önceki `b8e2e2db…`): sandık takibi `shape:getId()` ile, filtre değişince kısıt artık silinmiyor |
| **ClearRain** | `mods/ClearRain-VAULT` | Yağmur alpha ×0.25 |
| **Fly Beacon / FlyNoclip** | `mods/FlyNoclip-VAULT-1.0.0` | Kasa'ya kuruldu 2026-10-09 (2 dosya + 4 ortak dosyaya birer satır, `tools/flynoclip_patch.py`). Oyunda denendi: uçuş çalışıyor. Script 1.0.1 (hız x2.75, kapatma: yukarı-aşağı-yukarı bak / Shift x2) repoda; **Kasa'da hâlâ 1.0.0** (oyun açıktı). Kaldırma: `tools/remove_flynoclip_from_kasa.ps1` |

## Arşiv / iptal

| Mod | Not |
| --- | --- |
| **ItemSorter / Sortbot** | Fazla buggy; kaldırıldı |
| **MapViewer-VAULT** | Beacon mesh denemesi; Vortex’ten kaldırıldı |
| **BrakeLight-VAULT** | Brake Relay; deploy iptal |
| **CookbotSitChest** | Terk; Survival Cookbot vanilla |

## Kurulum

Vortex staging’e ilgili `mods/…` klasörünü kopyala. Oyun açıkken Survival/Vortex dosyası yazma.

## Lisans

Kişisel kullanım; üçüncü taraf Nexus asset kopyası yok (vanilla mesh reuse).
