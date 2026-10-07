# Map Viewer VAULT 1.0.1

Sıfırdan Survival harita terminali. Resmi Nexus 52 (Surveyor's Mapper) değil. Mod Manager yok. Foliage Eraser yok. `terrain_overworld.lua`, `Overworld.lua`, `SurvivalGame.lua` yok.

## 1.0.1

1.0.0 radyo mesh'i (`radio:{}` olmadan) görünmezdi ve yere oturmuyordu. 1.0.1 Survival beacon mesh kullanır. Elde E çalışmaz; yere koy, sonra E.

## Ne işe yarar

Craftbot'tan **Map Viewer** bas (5 Metal 1 + 1 Circuit Board). Yere koy. **E** ile aç.

- Senin X / Y / Z konumun
- Baktığın yön (+Y = Kuzey, +X = Doğu)
- 7x7 metin gülü (1 kare = 32 m). Sen `@`, işaretler A, B, C…
- İsim yaz, **ADD HERE**. Bu bloğun üstünde saklanır (dünya save'i). En fazla 12.
- **REMOVE LAST** / **CLEAR**

## Ne yapmaz (resmi moda göre eksik)

Resmi Map Viewer kuşbakışı kamera, hücre yükleme, sis/harita görüntüsü, pusula beacon, Log Book ve hotbar aleti kullanır. Bunlar `Overworld.lua` içine `loadCell` handler'ı ister. O yama bu pakette **yok** — yapıları silen terrain yolu da yok.

Bu yüzden:

- Arazi / bina / yol haritası çizilmez
- Keşfedilmemiş POI kendiliğinden işaretlenmez
- Global kısayol yok (E, bu blok)
- İşaretler dünya geneli değil; **bu terminalin** üstünde. İkinci terminal ayrı liste tutar
- El aleti yok
- Görünüş vanilla Survival beacon modeli (mavi tint). Radyo mesh yok. Nexus modelleri kopyalanmadı

## Vortex

1. Oyun kapalı olsun
2. `MapViewer-VAULT-1.0.1` klasörünü Vortex Scrap Mechanic mods staging'e koy, enable et
3. Bu mod şu dosyaları ItemPump ile **paylaşır** (dosya değişimi, ItemPump klasörüne yazılmaz):
   - `shapesets.json`
   - `RecipeManager.lua`
   - `craftbot_small_pipes.json`
   - `inventoryDescriptions.json`
4. İkisi birden açıksa Vortex'te **bu mod** o dört dosyada kazansın. İçerik ItemPump satırlarını da tutar (pump + sorter uuid'leri duruyor). ItemPump sonra yazarsa terminal craftbot'ta görünmez; o zaman bu paketteki dört dosyayı yeniden deploy et.
5. ItemPump / ItemFilter scriptlerine dokunulmadı
6. Tam quit + relaunch

## Güvenlik

- Install.bat / ps1 yok
- Foliage Eraser kurma
- Terrain script yok. Yapılar bu mod yüzünden silinmez
