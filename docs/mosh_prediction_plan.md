# Mosh Prediction (Local Echo) — Uygulama Planı

> Tarih: 2026-08-08 · Durum: **onay bekliyor** · Öncül: `docs/mosh_integration_plan.md` Faz 4

## Context

Mosh entegrasyonunun Faz 0–3'ü bitti ve roaming Android'de gerçek cihazda
doğrulandı. Planın baştan dışarıda bıraktığı tek parça kaldı: **prediction**,
yani yazılan karakterin sunucudan dönmesini beklemeden ekranda görünmesi.

Roaming "oturum ölmüyor" vaadini karşılıyor. Prediction farklı bir şeyi
karşılıyor: **oturumun hızlı hissettirmesi.** 200 ms RTT'de her tuş vuruşu
200 ms sonra görünür; mosh'un mobilde fark yaratmasının asıl sebebi budur,
roaming değil. Blink Shell'in mobil kalitesi diye anılan şey büyük ölçüde bu.

`dart_mosh` bize zamanlama sinyalini veriyor — `session.send()` girdi durum
numarası döndürüyor, `echoAcks` sunucunun onayladığı numarayı yayınlıyor.
Vermediği şey **ekran modeli**: mosh'un `PredictionEngine`'i (~700 satır C++)
kendi terminal durumu üzerinde çalışır ve tahminleri ayrı bir katmanda tutar.
Bu planın işi o katmanı Dart'ta ve xterm3'ün üstünde kurmak.

---

## Temel kısıt: tahmin buffer'a yazılamaz

İlk akla gelen çözüm — tahmin edilen karakteri `terminal.write()` ile yazmak —
**bozuk.** Mosh'ta sunucu, istemcinin bildiği kareye göre **minimal fark**
gönderir (`oldNum` → `newNum`). Yerel olarak ekrana fazladan karakter
yazarsak sunucunun bir sonraki farkı o hücreleri bilmez, dolayısıyla
düzeltmez: yanlış tahmin ekranda kalıcı olarak kalır.

Mosh'un kendisi bu yüzden tahminleri authoritative ekrandan ayrı tutar ve
render anında üstüne bindirir. Aynısını yapmak zorundayız:

> **Tahminler xterm3 buffer'ına hiçbir koşulda yazılmaz. Ayrı bir overlay
> katmanında çizilir ve ack gelince kaldırılır.**

Bu kısıt planın şeklini belirliyor; pazarlık payı yok.

---

## Önerilen kararlar

| Karar | Öneri | Gerekçe |
|---|---|---|
| Kapsam | Yalnızca **imleç satırı** | Tahmin değerinin ~tamamı kabuk girdisinde; tam ekran modeli maliyetin çoğu |
| Görüntüleme | Overlay `CustomPaint`, `TerminalView` üstünde `Stack` | Buffer'a yazmak protokol olarak yanlış (yukarı bkz.) |
| Varsayılan mod | `adaptive` — yalnız RTT eşiği aşılınca | Düşük gecikmede tahmin görsel gürültüden ibaret |
| Güvenlik varsayılanı | Epoch'ta doğrulanmış echo yoksa **hiçbir şey çizilmez** | Parola istemi (aşağıda) |
| Ayar | `AppSettingsModel`'e `moshPrediction` enum'u | mosh'un `--predict` davranışıyla eşleşsin |

## Kapsam dışı (bilinçli)

- **SSH sekmelerinde prediction.** SSH'ta echo onayı diye bir sinyal yok;
  tahminin doğrulanması imkânsız. Yalnızca mosh sekmelerinde.
- **Tam ekran uygulama içinde tahmin** (vim insert modu vb.). Mosh bunu
  deneyimsel modda yapar; biz yapmıyoruz, sadece güvenle *bırakıyoruz*.
- **Tahmin edilen imleç hareketi/renk.** Yalnızca düz karakter, backspace ve
  satır sonu davranışı.

---

## Faz A — Tahmin motoru (saf Dart, UI yok)

`lib/core/network/mosh_prediction_engine.dart`

Bağımlılığı yok: girdi olarak tuş vuruşları ve sunucu çıktısı alır, çıktı
olarak "şu anda ekranda gösterilmesi gereken tahmin listesi" verir. Bu
sayede tamamı birim testiyle kapanır — Faz B'nin aksine.

### Durum modeli

```dart
class MoshPrediction {
  final int row;          // imleç satırı, mutlak değil viewport-göreli
  final int column;
  final String glyph;
  final int inputStateNum; // session.send()'in döndürdüğü numara
  final DateTime queuedAt;
}
```

Motorun tuttukları: bekleyen tahminler, mevcut **epoch** numarası, epoch'ta
doğrulanmış echo olup olmadığı, son gözlenen imleç konumu.

### Akış

1. **Tuş vuruşu** — `terminal.onOutput` verisi bridge'e gitmeden önce motora
   uğrar. Yazılabilir tek karakterse tahmin kaydı açılır, `send()`'in
   döndürdüğü numarayla etiketlenir. Backspace bekleyen son tahmini siler.
   Enter, ok tuşları, kontrol dizileri → **tüm tahminler temizlenir** (kabuk
   ne yapacağını bilemeyiz).
2. **Echo ack** — `echoAcks` `N` yayınladığında `inputStateNum <= N` olan
   tahminler emekli edilir: sunucunun çıktısı o karakterleri zaten getirdi,
   overlay'in orayı çizmeye devam etmesi çift görüntü olur.
3. **Beklenmeyen sunucu çıktısı** — gelen bayt akışı beklenen echo'yla
   uyuşmuyorsa (imleç zıplaması, temizleme dizisi, alternatif ekran) **epoch
   öldürülür**: her şey temizlenir ve yeni bir doğrulanmış echo görülene
   kadar hiçbir şey çizilmez. Mosh'un "kill epoch" davranışı.
4. **Zaman aşımı** — bir tahmin `srtt * 2` (taban 500 ms) içinde
   onaylanmazsa düşer. Ekranda asılı kalan hayalet karakter, geç görünen
   karakterden kötüdür.

### Modlar

| Mod | Davranış |
|---|---|
| `never` | Motor devre dışı |
| `adaptive` (varsayılan) | `smoothedRtt` eşiğin (öneri: 60 ms) üstündeyse çiz |
| `always` | RTT'ye bakma, yine de doğrulama kurallarına uy |

`smoothedRtt` `MoshTransport` üzerinden zaten açık.

---

## Faz B — Overlay çizimi

`lib/features/terminal/presentation/widgets/mosh_prediction_overlay.dart`

`terminal_screen.dart:217`'deki `TerminalView` bir `Stack` içine alınır;
üstüne `IgnorePointer` + `CustomPaint` bindirilir. Overlay:

- Hücre boyutunu, xterm3'ün kendi `calcCharSize` algoritmasının **birebir
  aynısıyla** hesaplar (`'mmmmmmmmmm'` paragrafı, `maxIntrinsicWidth / 10`).
- `terminal.buffer.cursorX` / `cursorY` ile taban konumu alır (ikisi de public).
- Tahmin edilen glyph'leri **altı çizili** çizer — mosh'un görsel sözleşmesi:
  altı çizili = henüz sunucu onaylamadı.
- `scrollOffset` sıfırdan farklıysa hiçbir şey çizmez (kullanıcı geçmişe
  bakıyorsa tahmin göstermek anlamsız).

### Bu fazın gerçek riski

`calcCharSize` xterm3'te **export edilmiyor** (`lib/ui.dart` barrel'ında yok).
Yani 15 satırlık algoritmayı kopyalamak zorundayız. xterm3 bunu ileride
değiştirirse overlay sessizce kayar — yazı bir piksel sağa/aşağı düşer ve
kimse fark etmez.

Karşı önlem, tercih sırasıyla:
1. xterm3'e `calcCharSize`'ı export eden bir PR (proje zaten xterm2'nin
   devamı olan bir fork'u takip ediyor; kabul şansı iyi).
2. Kabul edilmezse `xterm3` sürümünü caret yerine tam pin'e almak ve
   kopyanın yanına "bu sürümden alındı" notu.

Alternatif olarak render'ı xterm3'ün `TerminalPainter`'ına gömmek düşünülebilir
ama `RenderTerminal` painter'ı içeride kuruyor, dışarıdan enjekte edilemiyor
— bu yol fork gerektirir, overlay gerektirmez.

---

## Faz C — Ayar ve bağlama

- `AppSettingsModel`'e `moshPrediction` (`never` / `adaptive` / `always`),
  varsayılan `adaptive`. Ayarlar ekranına bir select.
- `TerminalMoshBridge` girdi yolunda motoru çağırır; `TerminalOutputChain`
  zaten `onOutput` slotunu sahiplendiği için broadcast ve mobil tuş barı
  etkilenmez (Faz 1'de doğrulanmıştı).
- `TerminalTabSession`'a `moshPredictionEngine` alanı, `dispose()`'a bir satır.

---

## Güvenlik: parola istemleri

**Bu planın en önemli maddesi.** `sudo` ya da `ssh` parola sorduğunda sunucu
echo *yapmaz*. Naif bir tahmin motoru kullanıcının parolasını ekrana yazar.

Tasarımın buna cevabı, tek bir kural:

> Bir epoch'ta **en az bir tahmin sunucu tarafından doğrulanana kadar hiçbir
> tahmin çizilmez.** Tahminler kaydedilir, gösterilmez.

Parola isteminde hiç echo gelmez, dolayısıyla o epoch hiçbir zaman
"doğrulanmış" hâle gelmez ve tek bir karakter bile görünmez. Kabuk satırına
geri dönüldüğünde ilk echo doğrulanır ve tahmin normale döner.

Bu kural gecikmeye mal olur (her epoch'un ilk karakteri tahmin edilmez) ama
takas net: bir karakterlik gecikmeye karşı parolanın ekranda görünmemesi.
Testi `mosh_prediction_engine_test.dart`'ta ayrı bir grup olarak yazılacak ve
bu davranış **başka hiçbir optimizasyon için gevşetilmeyecek.**

---

## Dokunulacak dosyalar

**Yeni**
- `lib/core/network/mosh_prediction_engine.dart`
- `lib/features/terminal/presentation/widgets/mosh_prediction_overlay.dart`
- `test/unit/network/mosh_prediction_engine_test.dart`

**Değişecek**
- `lib/core/network/terminal_mosh_bridge.dart` — girdi yolunda motor
- `lib/features/terminal/domain/models/terminal_tab_session.dart` — alan + dispose
- `lib/features/terminal/presentation/screens/terminal_screen.dart` — Stack + overlay
- `lib/features/settings/...` — `moshPrediction` ayarı
- `pubspec.yaml` — (muhtemelen) `xterm3` pin'i

---

## Doğrulama

**Birim** — motorun tamamı UI'sız test edilebilir:
- Yazılabilir karakter tahmin üretiyor, kontrol dizisi üretmiyor
- `echoAcks` gelince ilgili tahminler emekli oluyor
- Beklenmeyen çıktı epoch'u öldürüyor
- Zaman aşımı asılı tahmini düşürüyor
- **Doğrulanmamış epoch'ta hiçbir tahmin görünür işaretlenmiyor** (parola)
- `never` modunda motor hiç tahmin üretmiyor

**Elle (Faz 0 harness'ı + yapay gecikme)** — `tc netem` ile 200 ms:
1. Kabukta yaz → karakterler anında ve altı çizili görünüyor, echo gelince
   altı çizgi kalkıyor
2. `sudo` parola istemi → **hiçbir karakter görünmüyor**
3. `vim` aç, yaz → tahmin devre dışı, ekran bozulmuyor
4. `Ctrl-C`, ok tuşları → tahminler temizleniyor, hayalet kalmıyor
5. Wi-Fi kes/aç → rehome sırasında asılı tahmin kalmıyor

**Cihaz** — gerçek yüksek gecikmeli hücresel bağlantı. Prediction'ın tek
gerçek testi de bu; masaüstünde LAN üzerinden hiçbir şey hissedilmez.

---

## Tavsiye

**Yapmaya değer, ama sırası şimdi değil.**

Değer gerçek ve tam olarak ürünün hedef kitlesinde: yüksek gecikmeli mobil
bağlantı. Roaming "oturum ölmüyor" diyor, prediction "hızlı hissettiriyor"
diyor; mobil vaadin ikinci yarısı bu.

Buna karşılık risk profili Faz 0–3'ten farklı. Oradaki iş ya çalışıyordu ya
çalışmıyordu. Burada **yanlış ayarlanmış bir motor terminali bozuk
hissettirir** — hayalet karakterler, kayan overlay, tam ekran uygulamada
titreme. Kötü bir prediction, prediction olmamasından kötüdür.

Önerim: önce **iOS roaming testi** kapansın (Faz 0–3'ün son açık maddesi),
sonra bu. Ve girildiğinde Faz A tek başına, gösterimsiz olarak inip
testleriyle otursun — motor doğru çalıştığından emin olmadan piksel çizmeye
başlamak, iki belirsizliği birbirine karıştırmak olur.

---

## Referanslar

- Mosh paper, §3 "Speculative local echo": <https://mosh.org/mosh-paper.pdf>
- `mosh` kaynağı `src/frontend/terminaloverlay.cc` — `PredictionEngine`
- `dart_mosh` `echoAcks` / `MoshHostMessage.echoAck` (fork: `klc/dart_mosh`)
- xterm3 `lib/src/ui/char_metrics.dart` — `calcCharSize` (export edilmiyor)
