# Mosh Prediction (Local Echo) — Uygulama Planı

> Tarih: 2026-08-08 · Durum: Faz A–C tamam · Öncül: `docs/mosh_integration_plan.md` Faz 4

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
Bu planın işi o katmanı Dart'ta kurmak.

### Her iki bağımlılık da bizim

- `dart_mosh` → `klc/dart_mosh` (Apache-2.0), commit ile pinli. Faz 1'de zaten
  bir kez yamalandı (`sinceLastHeard`, `isServerShutdown`).
- `xterm3` → `klc/xterm3` (AGPL-3.0-or-later), pub.dev'den 6.0.1.

Yani "paket bunu vermiyor" bir duvar değil, bir iş kalemi. Aşağıdaki tasarım
bunu varsayarak yazıldı: doğru yer neresiyse değişiklik oraya gidiyor.

**Prediction için `dart_mosh`'ta değişiklik gerekmiyor** — `echoAcks` ve
`send()`'in döndürdüğü durum numarası motorun ihtiyacı olan sinyalin tamamı.
Değişiklik gereken yer xterm3 ve orada da küçük.

---

## Temel kısıt: tahmin buffer'a yazılamaz

İlk akla gelen çözüm — tahmin edilen karakteri `terminal.write()` ile yazmak —
**bozuk.** Mosh'ta sunucu, istemcinin bildiği kareye göre **minimal fark**
gönderir (`oldNum` → `newNum`). Yerel olarak ekrana fazladan karakter
yazarsak sunucunun bir sonraki farkı o hücreleri bilmez, dolayısıyla
düzeltmez: yanlış tahmin ekranda kalıcı olarak kalır.

Mosh'un kendisi bu yüzden tahminleri authoritative ekrandan ayrı tutar ve
render anında üstüne bindirir. Aynısını yapmak zorundayız:

> **Tahminler xterm3 buffer'ına hiçbir koşulda yazılmaz. Boyama katmanında,
> buffer'ın üstüne çizilir ve ack gelince kaldırılır.**

Bu kısıt planın şeklini belirliyor; pazarlık payı yok.

---

## Önerilen kararlar

| Karar | Öneri | Gerekçe |
|---|---|---|
| Kapsam | Yalnızca **imleç satırı** | Tahmin değerinin ~tamamı kabuk girdisinde; tam ekran modeli maliyetin çoğu |
| Görüntüleme | xterm3'te `predictionText`, IME composing yolunun aynısı | Hizalama inşa gereği doğru; terly2'de piksel matematiği yok |
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

## Faz A — Tahmin motoru (saf Dart, UI yok) ✅

`lib/core/network/mosh_prediction_engine.dart`

Bağımlılığı yok: girdi olarak tuş vuruşları ve sunucu çıktısı alır, çıktı
olarak "şu anda ekranda gösterilmesi gereken tahmin listesi" verir. Bu
sayede tamamı birim testiyle kapanır — Faz B'nin aksine.

### Durum modeli

```dart
class MoshPrediction {
  final String glyph;
  final int inputStateNum; // session.send()'in döndürdüğü numara
  final DateTime queuedAt;
}
```

Satır/sütun taşınmıyor: kapsam imleç satırı ve çizim imleçten başlıyor, yani
konum zaten imlecin kendisi. Motorun dışarı verdiği tek şey
`String get visibleText` — gösterilmesi gereken, henüz onaylanmamış
karakterler. Faz B'nin beklediği de tam olarak bu.

Motorun içeride tuttukları: bekleyen tahminler, mevcut **epoch** numarası ve
o epoch'ta doğrulanmış echo olup olmadığı.

### Akış

1. **Tuş vuruşu** — `terminal.onOutput` verisi bridge'e gitmeden önce motora
   uğrar. Yazılabilir tek karakterse tahmin kaydı açılır, `send()`'in
   döndürdüğü numarayla etiketlenir. Backspace bekleyen son tahmini siler.
   Enter, ok tuşları, kontrol dizileri → **tüm tahminler temizlenir** (kabuk
   ne yapacağını bilemeyiz).
2. **Echo ack** — `echoAcks` `N` yayınladığında `inputStateNum <= N` olan
   tahminler emekli edilir: sunucunun çıktısı o karakterleri zaten getirdi,
   `visibleText`'te kalmaları çift görüntü olur.
   **Ama epoch onaylanana kadar ack'ler hiç işlenmez.** `MoshHostMessage`
   echo ack ile ekran baytlarını aynı pakette taşıyor; ack önce uygulanırsa
   baytın onaylayacağı tahmini silip götürür ve onay yalnızca bayt
   eşleşmesinden gelebildiği için epoch oturum boyunca bir daha onaylanmaz —
   hiçbir şey görünmez. Erteleme çağrı sırasına bağımlılığı tümden kaldırıyor.
   *(Planın ilk hâlinde yoktu; Faz A yazılırken çıktı.)*
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

## Faz B — Çizim: xterm3'te `predictionText` ✅

Araştırırken çıkan şey planı basitleştirdi: **xterm3 bu işi zaten yapıyor.**
`render.dart:1163` `_paintComposingText`, IME kompozisyon metnini imleçte,
buffer'a hiç girmeden, **altı çizili** çiziyor. Prediction'ın ihtiyacı olan
şeklin birebir aynısı — hatta görsel sözleşme bile aynı.

Tek eksik, o metni dışarıdan verememek: `_composingText` `TerminalView`'ın
IME geri çağrısıyla set edilen özel durumu (`terminal_view.dart:738`).

### Değişiklik (fork'ta, ~20 satır)

- `TerminalView`'a `String? predictionText` parametresi
- `RenderTerminal`'a aynı isimde bir setter, `markNeedsPaint` ile
- Boyama: `_paintComposingText`'in yanına eşi, aynı imleç ofseti ve aynı
  `underline: true` stiliyle
- Çakışma kuralı: **IME kompozisyonu varsa tahmin çizilmez.** Kullanıcı
  aktif olarak karakter besteliyorsa spekülasyon göstermek karışıklık olur.

xterm3 mosh'u öğrenmiyor — aldığı şey "imleçte şu metni göster" gibi genel
bir kanca. Mosh bilgisi terly2'de kalıyor.

### Neden `Stack` + `CustomPaint` değil

İlk taslak overlay'i terly2 tarafında, `TerminalView` üstünde bir `Stack`
içinde çiziyordu. Bunun için hücre boyutunu xterm3'ün `calcCharSize`
algoritmasıyla **birebir aynı** hesaplamak gerekiyordu; o fonksiyon export
edilmiyor, yani 15 satır kopyalanacaktı. xterm3 ileride hesabı değiştirirse
overlay sessizce kayardı — yazı bir piksel oynar, kimse fark etmez.

Fork bizim olduğu için bu yolu tamamen bırakıyoruz. Metni xterm3'ün kendi
boyama yolundan geçirmek hizalamayı **inşa gereği** doğru yapıyor: aynı
painter, aynı `cellSize`, aynı imleç ofseti. Kaydırma ve yeniden boyutlandırma
da mevcut render yolunun zaten çözdüğü şeyler.

`TerminalPainter`'ı dışarıdan enjekte etme fikri de bu yüzden gereksiz kaldı
(`RenderTerminal` painter'ı içeride kuruyor; o yol fork'ta daha büyük bir
cerrahi olurdu).

### Lisans notu

xterm3 AGPL-3.0-or-later ve `klc/xterm3` public. Değişiklik oraya indi ve
**6.1.0 olarak pub.dev'e yayınlandı**, yani `pubspec.yaml` git ref'ine hiç
ihtiyaç duymadan `^6.1.0` sürüm kısıtına döndü.

**Çizimde plandan bir sapma çıktı.** Boyama `_paintComposingText`'in yanına
konunca imleç guard'ının (`shouldPaint`) içinde kalıyordu; `shouldPaint`
`_shouldShowCursor`'ı içerdiği için tahmin edilen metin imleçle birlikte
yanıp sönüyor, uygulama imleci gizlediğinde hiç görünmüyordu. `_CursorPaintState`
artık `isRowVisible` taşıyor: tahmin **imlecin satırı ekranda mı** diye bakıyor,
**imleç çiziliyor mu** diye değil. Kompozisyon eski davranışında kaldı, zaten
imleci görünür zorluyor.

---

## Faz C — Ayar ve bağlama ✅

- `AppSettingsModel`'e `moshPrediction` (`never` / `adaptive` / `always`),
  varsayılan `adaptive`, JSON'a yazılıyor ve bilinmeyen değer `adaptive`'e
  düşüyor. Ayarlar ekranına bir select.
- Enum `lib/core/models/mosh_prediction_mode.dart`'ta: ayarlar katmanının ağ
  katmanındaki motor sınıfına bağımlı olmaması için.
- `TerminalMoshBridge` girdi yolunda motoru çağırır; `TerminalOutputChain`
  zaten `onOutput` slotunu sahiplendiği için broadcast ve mobil tuş barı
  etkilenmez (Faz 1'de doğrulanmıştı).
- `TerminalTabSession` motoru **sahiplenir** ve bridge'e geçirir — tek örnek.
  İkisi ayrı motor yaratsaydı özellik sessizce ölü olurdu: UI'ın okuduğu
  `visibleText` hiç dolmazdı.
- Yeniden çizim `Stream<void>` üzerinden: domain modeli Flutter notifier
  tiplerine bağlanmıyor, ekran `StreamBuilder` ile `predictionText`'i besliyor.

### Faz A'da bırakılmış iki eksik burada kapandı

1. **Parçalı UTF-8 çözme.** Motor her paketi ayrı `utf8.decode` ediyordu; çok
   baytlı bir karakter iki datagram'a bölündüğünde U+FFFD çıkıyor, eşleşme
   tutmuyor ve epoch ölüyordu — Türkçe metinde sürekli. Artık chunked decoder
   kullanılıyor, `reset()` sink'i yeniliyor.
2. **Ack ertelemesi.** Faz A'daki düzeltme ack'i onaylanmadan önce tamamen
   atıyordu. Artık en büyük ack saklanıp onay sonrası uygulanıyor: aynı
   kilitlenme çözülüyor ama bilgi kaybolmuyor.

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
- `test/unit/network/mosh_prediction_engine_test.dart`

**Değişecek**
- `klc/xterm3` — `TerminalView.predictionText` + boyama (ayrı repo, ~20 satır)
- `lib/core/network/terminal_mosh_bridge.dart` — girdi yolunda motor
- `lib/features/terminal/domain/models/terminal_tab_session.dart` — alan + dispose
- `lib/features/terminal/presentation/screens/terminal_screen.dart` — `predictionText` beslemesi
- `lib/features/settings/...` — `moshPrediction` ayarı
- `pubspec.yaml` — `xterm3` yeni sürüm (ya da geçici git ref)

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
- xterm3 `lib/src/ui/render.dart:1163` — `_paintComposingText`, çizimin emsali
- Fork'lar: `klc/dart_mosh` (Apache-2.0), `klc/xterm3` (AGPL-3.0-or-later)
