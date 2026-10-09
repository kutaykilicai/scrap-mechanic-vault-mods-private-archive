# FlyNoclip-VAULT 1.0.0 — Uçuş İşaretçisi (Fly Beacon)

Survival'da uçma ve (deneysel) duvardan geçme. Yere konan tek bir parça. Görünüşü oyunun kendi **beacon** modeli, sarı renkte (MapViewer 1.0.1'de çalışan mesh ile aynı, yeni mesh yok).

## Neden komut (/fly) değil de parça?
Survival'da yeni chat komutu eklemenin tek yolu `SurvivalGame.lua`'yı değiştirmek. Kural gereği o dosyaya dokunulmadı. Bu yüzden aç/kapa parçadan ve bir tuş hareketinden yapılıyor.

## Kullanım
1. Craftbot → küçük borular sekmesi (Item Pump'ın yanında) → **Fly Beacon** (3 Metal Block). İkon boş görünebilir.
2. Yere koy. Parçaya bak, **E**:
   **KAPALI → UÇUŞ → UÇUŞ + NOCLIP → KAPALI**
3. Uçarken:
   - **W/A/S/D + fare**: baktığın yöne uçarsın (yukarı bak + W = yüksel, aşağı bak + W = alçal). Space de yukarı çıkarır.
   - **Shift**: 2 kat hız.
   - Parçaya bakıp **U (Tinker)**: hız seviyesi 1–4.
   - **Ctrl'e hızlıca 2 kez bas**: uçuş her yerde KAPANIR.
4. **Noclip (UÇUŞ + NOCLIP modunda):** duvara/zemine bak, **Shift basılı tutarak ona doğru it**. ~0,2 sn sonra en fazla 8 m ötede boş bir yere ışınlanırsın. Gerçek "içinden süzülme" değil, duvarın arkasına atlama.

## Kapatınca ne olur?
Sadece bu modun açtığı şeyler geri alınır: yüzme/dalış durumu kapanır, hız 1.0'a (oyunun varsayılanı) döner. Kapalıyken script hiçbir şey yapmaz. Dünya save'ine veri yazmaz (storage yok). Parçayı toplarsan uçan herkesin uçuşu kapanır.

## Kurulum (oyun TAMAMEN kapalıyken)
Survival'da mod yükleyici yok; parça 4 ortak dosyada birer satırla kayıt edilmeli. BrakeLight ile aynı güvenli yöntem:

1. Paketin içindeki 2 dosya oyuna/Vortex'e gider (Vortex overlay yolu, oyun klasörüne göre):
   - `Survival/Objects/Database/ShapeSets/flynoclip_vault.shapeset`
   - `Survival/Scripts/game/interactables/FlyNoclipVault.lua`
2. `tools/flynoclip_patch.py add --game "<Scrap Mechanic klasörü>"` ortak 4 dosyaya **birer satır** ekler:
   `shapesets.json`, `RecipeManager.lua`, `craftbot_small_pipes.json`, `inventoryDescriptions.json`.
   Tam dosya kopyası gönderilmez, ItemPump'ın overlay'iyle çakışmaz.
3. Hepsini yapan taslak: `tools/deploy_flynoclip_to_kasa.ps1` (zip'i önce `%TEMP%\FlyNoclip-VAULT-work` içine koy; masaüstü kullanılmaz). Oyun açıksa durur.
4. Tam çık + yeniden aç.

## Kaldırma
Uçuşu kapat, parçayı topla. Oyun kapalıyken `tools/remove_flynoclip_from_kasa.ps1`. 4 satır geri alınır, dosyalar byte-byte eski haline döner.

## Dokunulmayanlar
ItemPump.lua, ItemFilter.lua, ClearRain, SurvivalGame.lua, SurvivalPlayer.lua, WaterManager.lua, terrain/Overworld. Kurulum aracı ItemPump/ItemFilter MD5'i beklenenden farklıysa hiçbir şey yazmadan durur.

## Bilinen sınırlar / riskler
- **Oyunda test edilmedi.** Uçuş yöntemi (havada yüzme + dalış) başka Survival uçuş modlarının kullandığı yöntem; noclip ışınlama ise en belirsiz kısım. Oyun izin vermezse noclip kendini kapatır, uçuş açık kalır.
- **Yüksekten kapatınca düşersin.** Düşme hasarı olabilir; yere yakınken kapat ya da `/god` aç.
- **Su üstünde** oyunun su sistemi hızı/yüzmeyi kendi ayarlar, hareket titreyebilir.
- **Parçadan çok uzaklaşma** (~150 m'de uyarı gelir). Parçanın olduğu alan yüklenmezse script durur. Parça yüklenmezse uçuş kapanabilir (düşme) ya da açık kalabilir (o zaman Ctrl x2 çalışmaz; suya girip çık ya da parçanın yanına dön).
- Sandık vb. bir şey **taşırken** uçuş kendiliğinden kapanır (takılmayı önlemek için).
- Ctrl x2'nin uçarken algılanması test edilmedi; olmazsa E ile kapat.
- Hız seviyesi parça başına, save'e yazılmaz (yeniden yüklemede 2/4).
