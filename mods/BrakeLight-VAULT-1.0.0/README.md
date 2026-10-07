# BrakeLight-VAULT 1.0.0 — Fren Rölesi (Brake Relay)

S'ye (geri/fren) basınca arka ışıkları yakan küçük bir parça. Görünüşü oyunun kendi Logic Gate bloğu (1x1x1), kırmızı.

## Neden gerekli
Işıklar sadece **logic** sinyali alır (buton, switch, logic gate). Sürücü koltuğu ise **power** (motorlara giden W/S) ve **bearing** çıkışı verir. O yüzden koltuk → ışık bağlanmıyor, buton da sadece 1–0 tuşlarına atanıyor.
Brake Relay koltuktan power alır, S basılıyken logic çıkışını AÇAR. Işıklar bu parçaya normal şekilde bağlanır.

## Kullanım
1. Craftbot → küçük borular sekmesi (Item Pump'ın yanında) → **Brake Relay** (3 Metal Block). İkon boş görünebilir; parça adı "Brake Relay".
2. Arabaya yerleştir (taşıyıcı olmayan bir yüzeye; tek blok).
3. Connection Tool: **Driver's Seat → Brake Relay** (motor bağlar gibi).
4. Connection Tool: **Brake Relay → arkadaki ışıklar** (her ışığa ayrı; 255'e kadar).
5. Otur: S basılıyken röle ekranı yanar ve ışıklar açılır, bırakınca söner. W veya boşta: kapalı.

Not: Oyunda S hem fren hem geri vites; ikisinde de yanar. Koltuk seviye 1'de 6 bağlantı hakkı var; röle bunlardan birini kullanır.

## Ne değiştirir / neye dokunmaz
- Yeni dosyalar (sadece bu modun): `brakelight_vault.shapeset`, `BrakeLightVault.lua`.
- Ortak 4 dosyaya **tek satır** eklenir (kurulumda, o anki canlı dosyaya; tam kopya gönderilmez):
  `shapesets.json`, `RecipeManager.lua`, `craftbot_small_pipes.json`, `inventoryDescriptions.json`.
- ItemPump.lua, ItemFilter.lua, ClearRain, terrain/Overworld/SurvivalGame **dokunulmaz**. Kurulum aracı ItemPump/ItemFilter MD5'i farklıysa hiçbir şey yazmadan durur.
- **MapViewer tarzı tam-dosya overlay KULLANILMAZ.** Vortex klasörüne ortak dosya konmaz.

## Kaldırma
Önce arabadaki röleleri topla, sonra `tools/remove_brakelight_from_kasa.ps1` (oyun kapalı). 4 satır geri alınır, dosyalar byte-byte eski haline döner.
