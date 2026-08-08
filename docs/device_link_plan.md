# Device Link — Masaüstü Terminalini Telefona Bağlama

> Tarih: 2026-08-08 · Durum: **kod tabanına karşı doğrulandı**, onay bekliyor
> İlgili: `docs/tech_spec.md`, `docs/product_roadmap_2026-08-07.md`, `AGENTS.md` §2.3
> Rev. 2026-08-08 — Mosh + prediction merge'ünden sonra tüm dosya/satır referansları
> ve varsayımlar taranarak düzeltildi; bkz. [Kod tabanı doğrulaması](#kod-tabanı-doğrulaması).

## Context

Masaüstünde çalışan **canlı bir terminal oturumuna telefondan bağlanmak**. Asıl
senaryo: bilgisayarda uzun süren bir iş (Claude Code, build, migration, `tail -f`)
çalışırken masadan kalkmak; telefondan hem çıktıyı izlemek hem gerektiğinde
bilgisayar başına dönmeden komut göndermek.

Bugün bunun karşılığı `ssh mac + tmux attach`. Device Link'in bunu yenmesi
gerekiyor ve yenebileceği yer şurası: **sıfır kurulum** (tmux yok, SSH sunucusu
açmak yok, port yönlendirme yok), ürünün kendi mobil terminal UI'ı ve eşleştirme
sonrası tek dokunuşla bağlanma.

Gereken parçaların çoğu repoda zaten var:

| İhtiyaç | Mevcut karşılığı |
| :--- | :--- |
| Masaüstünde PTY + emulator | `lib/core/network/local_pty_manager.dart:11` (`TerminalLocalPtyBridge`) |
| Mobilde terminal render | `xterm3` + `lib/features/terminal/presentation/screens/terminal_screen.dart:17` |
| Mobil klavye (Esc/Ctrl/ok tuşları) | `lib/features/terminal/presentation/widgets/mobile_extra_keys_bar.dart:7` |
| Oturuma girdi enjekte etme noktası | `terminal_output_chain.dart:59` (`base`) veya `bridge.pty.write` |
| Buffer okuma (snapshot) | `xterm3` 6.1.0 public API — `Terminal.buffer`, `BufferLine.get*`, mod getter'ları |
| Şifreli kalıcı depolama | `cryptography` 2.9.0 (Argon2id + AES-GCM) + `flutter_secure_storage` |
| Argon2id hash | `lib/core/crypto/encryption_engine.dart:21` — hazır, yeniden kullanılacak |

Eksik olan tek şey iki cihaz arasındaki **taşıma katmanı**.

> ⚠️ `docs/product_roadmap_2026-08-07.md` §9 önümüzdeki 8 hafta yeni özellik
> yazılmamasını öneriyor. Bu plan o tavsiyeyle çelişiyor; bilinçli bir istisna
> olarak onaylanmalı ya da roadmap'in ilerisine alınmalı.

---

## Kod tabanı doğrulaması

Plan ilk yazıldığında bazı varsayımlar doğrulanmamıştı; Mosh (Faz 0-3) ve
prediction (Faz A/B) işleri de o zamandan sonra merge oldu. Tam tarama sonucu:

| # | İlk varsayım | Gerçek durum |
| :--- | :--- | :--- |
| 1 | **En büyük risk:** `xterm3` buffer'ı dışarıdan serialize edilemeyebilir; fork ya da ikinci `Terminal` gerekebilir | **Çürüdü.** Buffer, hücre, SGR bayrakları, scrollback, imleç ve **tüm mod bayrakları** public + export. Fork da gerekmiyor, ikinci emulator da. Detay Faz 2'de |
| 2 | (örtük) xterm3'te bir serializer vardır | **Yok.** `EscapeEmitter` export edilmiyor ve yalnızca cevap dizileri üretiyor. SGR run emitter'ı elle yazılacak |
| 3 | macOS'te `network.server`/`.client` entitlement'ları eklenecek | **Zaten var**, hem `DebugProfile` hem `Release`. macOS tarafında iş yok |
| 4 | Fan-out noktası `local_pty_manager.dart:39-52` | **:39-53** — ve UTF-8 decode pipeline'ın *içinde*; ham byte musluğu `.transform()`'tan **önce** girmeli |
| 5 | Mobil terminal `terminal_tab_view.dart`'tan gelir | **Yanlış dosya.** O, girdi almayan masaüstü sekme çubuğu. Gerçek sarmalayıcı `terminal_screen.dart:17` |
| 6 | Girdi enjeksiyonu için yeni API gerekir | **Gerekmiyor.** `TerminalOutputChain.base` (`:59-62`) tam bunun için var; `bridge.pty` de public |
| 7 | `basic_utils` X.509 için şart | Muhtemelen değil — `pointycastle` 4.0.0 **ve** `asn1lib` 1.6.5 zaten transitive |
| 8 | `tool/` altına harness koymak yeni konvansiyon | Zaten kurulu: `tool/mosh/{smoke.dart,Dockerfile,docker-compose.yml,README.md}` |
| 9 | Migration kuralı `AGENTS.md` §2.4'te | §2.4'te migration maddesi yok. Gerçek hedef `app_database.dart:49` + `:87` |
| 10 | Predictive local echo kapsam dışı, çakışma yok | Kapsam kararı geçerli, ama `MoshPredictionEngine` artık var ve **iki kod yolunu paylaşıyor**; bkz. "Mosh prediction ile temas" |
| 11 | (belirsiz) `xterm3` tarafında da iş çıkabilir | **Çıkmıyor.** Tüm değişiklik `terly2` içinde; bkz. "xterm3'te değişiklik gerekiyor mu" |

### xterm3'te değişiklik gerekiyor mu — **hayır**

Tüm iş `terly2` içinde. Export yüzeyi doğrulandı: `core.dart` `buffer.dart`,
`line.dart`, `cell.dart`, `cursor.dart`, `terminal.dart` dosyalarını dışa
veriyor; snapshot ve izleyici modu için gereken her API public.

| İhtiyaç | API | Durum |
| :--- | :--- | :--- |
| Buffer seçimi + alt screen | `Terminal.buffer/mainBuffer/altBuffer/isUsingAltBuffer` `:499-505` | ✅ |
| Mod bayrakları | `bracketedPasteMode:479`, `autoWrapMode:434`, `cursorKeysMode:425`, `mouseMode:443`, `mouseReportMode:446`, `cursorVisibleMode:452`, `appKeypadMode:455`, `originMode:431` | ✅ |
| Satır / imleç | `Buffer.lines:80`, `cursorX:91`, `cursorY:95`, `scrollBack:110`, `height:87` | ✅ |
| Hücre | `BufferLine.getCodePoint:98`, `getWidth:102`, `getForeground:61`, `getBackground:65`, `getAttributes:69`, `getUnderlineColor:110`, `getCombiningCharacters:106`, `getTrimmedLength:640` | ✅ |
| Satır sarma | `BufferLine.isWrapped:39` (public field) | ✅ |
| Snapshot'ı telefona yazma | `Terminal.write(String):531` | ✅ |
| Resize | `Terminal.resize():739` | ✅ |
| **İzleyici modu** (reclaim sonrası) | `TerminalView.readOnly` `:128/:224` | ✅ zaten var |

**Tek pürüz, bloklamıyor:** `Buffer.lines`'ın tipi
`IndexAwareCircularBuffer<BufferLine>` ve o sınıf export edilmiyor
(`src/utils/circular_buffer.dart:2`). Tip **adlandırılamıyor** — değişken
bildiriminde ya da fonksiyon imzasında yazılamaz. Kullanım sorunsuz, çıkarım
çalışıyor:

```dart
final lines = buffer.lines;               // tip çıkarımı
for (var i = 0; i < lines.length; i++) {  // Iterable değil → for-in yok
  final line = lines[i];                  // BufferLine
}
```

Serializer imzalarında `List<BufferLine>` taşınacak (girişte tek kopya).

> `core.dart`'a `export 'src/utils/circular_buffer.dart';` eklemek pürüzü
> kaldırırdı ve paket bizim. **Yapılmayacak:** yeni pub.dev sürümü + `terly2`
> pubspec bump maliyeti, karşılığında yalnızca ergonomi. `List` kopyası yeterli.

### AGENTS.md §2.3 ile bilinçli sapma

§2.3 "`terminal.onOutput`'u `session.write`'a bağla" diyor. Device Link'ten gelen
girdi bu slotu **kullanmayacak** — o slot `TerminalOutputChain`'in ve broadcast /
sticky-modifier interceptor'larının. §2.3 yerel kullanıcının girdi yolunu tarif
ediyor; uzak cihaz girdisi farklı bir kaynak. Sapma PR açıklamasında açıkça
belirtilmeli, sessizce yapılmamalı.

### Mosh prediction ile temas

`MoshPredictionEngine` (`lib/core/network/mosh_prediction_engine.dart:31`) ve
`TerminalView.predictionText` artık repoda. Device Link ikisini de kullanmıyor
ama iki noktada aynı kod yoluna dokunuyor:

1. **Ham byte `.map()` slotu.** `TerminalMoshBridge` (`terminal_mosh_bridge.dart:65-73`)
   `.transform(Utf8Decoder)`'dan önce bir `.map()` ile ham byte'ları görüyor.
   Device Link'in `outputTap`'i PTY bridge'inde **aynı** şekli alacak. Faz 6'da
   Mosh oturumları aynalanırsa ikisi tek `.map()`'i paylaşır ve sıralama önem
   kazanır (prediction her byte'ı görmeye devam etmeli).
2. **`TerminalScreen`'in prop seti** (`terminal_screen.dart:216-247`).
   Device-link oturumunda `session.isMosh` false olduğu için `predictionText`
   null kalır — v1'de çakışma yok. İleride Device Link kendi local echo'sunu
   isterse **aynı** prop'a yazacak; o noktada öncelik kuralı gerekir.

Ayrıca `TerminalMoshBridge.resizeTerminal` (`:131`) prediction engine'i koşulsuz
`reset()` ediyor. Aynalanan bir Mosh oturumunda attach→reclaim dizisi epoch'u iki
kez temizler; zararsız (prediction tavsiye niteliğinde) ama bilinerek yapılmalı.

---

### Onaylanan kararlar

| Karar | Seçim | Gerekçe |
| :--- | :--- | :--- |
| Taşıma katmanı | **PTY seviyesi** — ham byte akışı, iki yönlü | App-agnostik: `vim`, `htop`, `psql`, Claude Code hepsi çalışır. Semantik UI tek bir uygulamaya overfit olurdu |
| Ağ | **Yalnızca LAN**, relay yok | Backend/ops/maliyet yok; üçüncü taraf düz metin terminal görmez; RTT 2-5ms olduğu için gerçek terminal hissi mümkün |
| LAN dışı erişim | Kullanıcının kendi overlay ağı (Tailscale/WireGuard) | Kodda sıfır değişiklik, dokümantasyonda bir paragraf |
| Mobil UI | **Gerçek terminal** (mevcut `xterm3` görünümü) | Yeni yüzey inşa etmek yerine çalışan bileşenleri kullan |
| Uzun metin girişi | Native compose sheet → **bracketed paste** | Ham terminale telefondan paragraf yazmak kullanılamaz; dikte desteği bu yolla gelir |
| Ekran durumu aktarımı | Attach anında **tek snapshot**, sonrası ham geçiş | Sürekli diff/frame üretmeye gerek yok; snapshot yalnızca "katılma anı" problemi |
| Snapshot kaynağı | Masaüstündeki **mevcut** `Terminal` instance'ı | İkinci bir headless emulator gerekmiyor — ekran ve scrollback zaten orada |
| Kimlik doğrulama | QR ile pinlenen self-signed TLS + paylaşılan sır | Dart'ta yerli destek var, hand-rolled kripto yok |
| Eşleştirme sıklığı | QR **yalnızca ilk kez**; sonrası otomatik | Günde 10 kez QR okutmak feature'ı öldürür |
| Boyut sahipliği | Telefon attach olunca PTY telefonun ölçüsüne çekilir | Senaryonun tanımı gereği masaüstü o an izlenmiyor |

### Kapsam dışı (bilinçli)

- **Relay / bulut altyapısı.** LAN dışı erişim kullanıcının kendi VPN'i.
- **Semantik mobil UI.** Claude Code'a özel onay kartları, chat görünümü,
  yapısal diff render'ı — hepsi PTY seviyesi kararıyla birlikte düştü.
- **iOS arka plan bildirimi.** Gerçek push APNs ister, APNs sunucu ister,
  sunucu da LAN-only kararını deler. Faz 6'da ayrı bir karar olarak ele alınacak.
  Bu, feature'ın **bilinen en büyük ergonomi açığı**: uygulama arka plandayken
  "Claude onay bekliyor" bildirimi gönderilemez.
- **Çoklu izleyici / ekran paylaşımı.** Bir oturuma aynı anda tek cihaz.
- **Predictive local echo.** LAN'da RTT 2-5ms; gerek yok. Repoda bulunan
  `MoshPredictionEngine` **bu feature'a bağlanmayacak** — ayrı iş, ayrı taşıma
  katmanı. Temas noktaları için "Mosh prediction ile temas" bölümüne bakılmalı.
- **SSH oturumlarının aynalanması.** Mekanizma aynı (`TerminalSSHBridge` de bir
  `Terminal` besliyor) ama Faz 6'ya bırakıldı; v1 yalnızca local PTY.

---

## Mimari özet

```
MASAÜSTÜ                                          TELEFON
                                    
  Pty ──┬──► Terminal (yerel UI)     
        │        │                   
        │        └─ buffer ──► TerminalSnapshot ──┐
        │                                          │  TLS/WS (LAN)
        └──────────────────────► DeviceLinkServer ─┼─────────────► DeviceLinkClient
                                        ▲          │                     │
                                        │          │                     ▼
  pty.write ◄─── outputChain.base ◄─────┘          │              Terminal (mobil UI)
                                                    │                     │
                                                    └─────────────────────┘
                                                       girdi (ham byte)
```

Fan-out noktası `TerminalLocalPtyBridge` (`local_pty_manager.dart:40-53`): bugün
`pty.output`'u tek bir yere (`terminal.write`) veriyor, ikinci bir tüketici
eklenecek. Telefondan gelen girdi `pty.write`'a gitmeli — `terminal.onOutput`
üzerinden **değil**, çünkü o slot `TerminalOutputChain` tarafından yönetiliyor ve
interceptor'ları (broadcast, sticky modifier) telefondan gelen byte'lara
uygulanmamalı.

---

## Faz 0 — Bağımlılıklar ve doğrulama zemini

### Yeni paketler

| Paket | Kullanım | Not |
| :--- | :--- | :--- |
| `nsd` | mDNS servis kaydı (masaüstü) + keşif (mobil) | Hem `register` hem `discover` destekliyor; `multicast_dns` yalnızca keşif yapabildiği için yetersiz |
| `qr_flutter` | QR üretimi (masaüstü) | |
| `mobile_scanner` | QR okuma (mobil) | Kamera izni gerekir |
| `basic_utils` | Self-signed X.509 üretimi | **Önce gereksizliği denensin:** `pointycastle` 4.0.0 *ve* `asn1lib` 1.6.5 `dartssh2` üzerinden zaten `pubspec.lock`'ta. İkisiyle sertifika üretmek ~150 satır; `basic_utils` yalnızca bu deneme başarısız olursa eklenir |

SHA-256 parmak izi için `crypto` zaten transitive; ayrı paket yok.

WebSocket sunucusu için **yeni paket yok**: `dart:io`'nun
`HttpServer.bindSecure` + `WebSocketTransformer.upgrade` kombinasyonu yeterli.
`shelf` eklemeye gerek duyulmamalı.

`pubspec.yaml`'da pinleme yorumları var (`:33-34`, `:88`, `:96`, `:102-103`);
dört yeni paket sıkı bir lock'a giriyor, çözüm çakışması ihtimali hesaba
katılmalı.

### Platform yapılandırması

- **iOS** `ios/Runner/Info.plist`: `NSLocalNetworkUsageDescription`,
  `NSBonjourServices` (`_terly._tcp`), `NSCameraUsageDescription`.
  Bugün üçü de yok. Kullanıcı yerel ağ iznini reddederse feature sessizce
  çalışmaz — bu durum tespit edilip anlamlı bir hata gösterilmeli.
- **macOS**: ~~entitlement eklenecek~~ — `com.apple.security.network.server` ve
  `.client` **hem `DebugProfile.entitlements` hem `Release.entitlements`'ta zaten
  var**; ayrıca `app-sandbox` her ikisinde de `false`. Bu fazda macOS işi yok.
  İlk çalıştırmada gelen firewall istemi code signing olmadan her seferinde
  tekrarlanır — bu hâlâ geçerli.
- **Android** (`android/app/src/main/AndroidManifest.xml`): `INTERNET` **var**;
  `CHANGE_WIFI_MULTICAST_STATE` (mDNS için) ve `CAMERA` **yok**, eklenecek.
- **Windows/Linux**: firewall kuralı kullanıcıya bırakılıyor; bağlantı
  kurulamazsa hata mesajında bundan bahsedilmeli.

### Doğrulama harness'ı

`tool/device_link/` altına, kaynak ağacına değil: iki cihaz gerektirdiği için
CI'da koşamaz. Konvansiyon zaten kurulu — `tool/mosh/` içinde `smoke.dart`,
`Dockerfile`, `docker-compose.yml`, `README.md` var; aynı düzen izlenecek.

Elle koşulan bir smoke script + protokol katmanı için gerçek soket kullanan
entegrasyon testleri (aynı makinede `127.0.0.1` üzerinden server↔client).
Loopback test kalıbı da mevcut: `test/unit/core/network/socks5_proxy_server_test.dart:68`
(`ServerSocket.bind('127.0.0.1', 0)`). Faz 1'in çıkışı bu testlerin geçmesi.

---

## Faz 1 — Taşıma çekirdeği

Yeni dizin: `lib/core/network/device_link/`

| Dosya | Sorumluluk |
| :--- | :--- |
| `device_link_protocol.dart` | Mesaj şeması, kodlama/çözme, protokol sürümü |
| `device_link_identity.dart` | Cihaz anahtar çifti, sertifika üretimi, parmak izi |
| `device_link_server.dart` | Masaüstü: TLS sunucu, WS upgrade, oturum kayıtları |
| `device_link_client.dart` | Mobil: bağlanma, pinleme, yeniden bağlanma |
| `device_discovery.dart` | mDNS kaydı ve keşfi (`nsd` sarmalayıcı) |

`lib/core/network/` konumu `AGENTS.md` §2.1 ile uyumlu ("network isolates, stream
bridges"). Sınıflar `BuildContext`'e dokunmayacak (§2.2) — `MoshPredictionEngine`
ile aynı disiplin.

> **Mevcut precedent zayıf.** Repoda `ServerSocket` kullanımı var
> (`tunnel_engine.dart:155`, `socks5_proxy_server.dart:33`) ama `HttpServer`,
> `WebSocket`, `SecurityContext`, `X509Certificate` kullanımı **sıfır**. TLS
> üretimi ve pinleme tamamen yeni zemin; fazın en uzun kalemi burası olacak,
> protokol şeması değil.

### Kanal ayrımı

WebSocket'in text ve binary opcode'ları ayrı ayrı kullanılıyor:

- **Text frame → JSON kontrol mesajı.** Nadir, küçük, okunabilir.
- **Binary frame → 1 byte tip öneki + payload.** Sık, ham PTY verisi.

| Tip | Yön | Anlam |
| :--- | :--- | :--- |
| `0x01` | S→C | PTY çıktısı |
| `0x02` | C→S | PTY girdisi |
| `0x03` | S→C | Snapshot gövdesi |

Bu ayrım sayesinde ham byte yolunda hiçbir base64/JSON kodlaması yok.

### Kontrol mesajları

```jsonc
// C→S, bağlantının ilk mesajı
{ "t": "hello", "v": 1, "deviceId": "...", "deviceName": "iPhone 15",
  "secret": "<eşleştirmede alınan paylaşılan sır; eşleşmemişse yok>" }

// S→C
{ "t": "hello_ack", "v": 1, "appVersion": "...",
  "sessions": [ { "id": "...", "title": "zsh — ~/www/terly2", "type": "local" } ] }

// C→S, eşleştirme (yalnızca QR akışında)
{ "t": "pair", "token": "<QR'daki tek kullanımlık token>",
  "deviceName": "iPhone 15", "devicePublicKey": "..." }
{ "t": "paired", "secret": "...", "hostName": "mkilic-mbp" }   // S→C

{ "t": "attach", "sessionId": "...", "cols": 52, "rows": 30 }  // C→S
{ "t": "attached", "sessionId": "...", "cols": 52, "rows": 30,
  "alt": false, "bracketedPaste": true, "scrollbackLines": 400 } // S→C
                                                     // ardından 0x03 binary

{ "t": "resize", "cols": 92, "rows": 30 }                      // C→S
{ "t": "detach" }                                              // C→S
{ "t": "reclaimed", "cols": 204, "rows": 52 }                  // S→C, masaüstü kontrolü geri aldı
{ "t": "error", "code": "session_gone", "message": "..." }     // S→C
```

Canlılık için WebSocket'in **kendi ping/pong frame'leri** kullanılıyor,
uygulama seviyesinde ayrı bir heartbeat mesajı tanımlanmıyor. 5 sn ping,
15 sn timeout.

### QR yükü

```jsonc
{
  "v": 1,
  "host": "mkilic-mbp",
  "addrs": ["192.168.1.24", "10.211.55.2", "fe80::1c3f:..."],
  "mdns": "mkilic-mbp._terly._tcp.local",
  "port": 47823,
  "spki": "<sunucu sertifikasının SPKI SHA-256'sı, base64>",
  "token": "<32 byte, tek kullanımlık>",
  "exp": 1754650000
}
```

Üç ayrıntı kritik:

1. **Tek IP yazma.** Makinede WiFi, Ethernet, VPN ve Docker köprüsü aynı anda
   olabilir; yanlış adres seçilirse bağlantı sessizce kurulmaz. Aday adreslerin
   tamamı + mDNS adı gönderilir, telefon hepsini **paralel** dener, ilk
   tamamlanan kazanır, diğerleri iptal edilir.
2. **SPKI pinleme.** `mkilic-mbp.local` için gerçek sertifika alınamaz, o yüzden
   self-signed kullanılıyor. Parmak izi QR'dan geldiği için MITM kapanıyor.
   Ofis/ortak WiFi güvenilmez kabul edilmeli; "LAN olduğu için düz metin
   geçebilir" varsayımı yasak.
3. **TTL 90 saniye + tek kullanım.** Ekranın fotoğrafı kalıcı bir arka kapıya
   dönüşmemeli.

### Kimlik doğrulama modeli

Eşleştirme anında sunucu 32 byte rastgele bir **paylaşılan sır** üretir.
Telefon bunu `flutter_secure_storage`'a yazar; masaüstü **Argon2id hash'ini**
drift'e yazar (düz metin değil). Sonraki bağlanışlarda telefon sırrı `hello`
mesajında sunar. Pinlenmiş TLS altında bearer sır yeterli; mutual TLS ileri bir
sertleştirme adımı olarak Faz 6'da değerlendirilecek.

İkisi de yeni kod istemiyor:

- **Argon2id** → `lib/core/crypto/encryption_engine.dart:21` (`Argon2id _kdf`,
  sertleştirilmiş parametreler `:31-40`). Ayrıca `deriveMasterKeyInBackground`
  `:109-128` isolate'e taşıyor — hash maliyeti UI thread'ini kilitlemesin diye
  aynı yol kullanılmalı.
- **Telefon tarafı sır** → `SecureStorageService`
  (`lib/shared/storage/secure_storage_service.dart:24`); `saveToken` / `getToken`
  / `deleteToken` (`:94/:102/:110`) `tokenPrefix` ile hazır.

Bu düzen `AGENTS.md` §2.4 ile uyumlu (sır düz metin saklanmıyor). Model,
`KnownHostsDao`'nun host-key doğrulama şemasının birebir analoğu — SPKI pinlemesi
de aynı biçimde ele alınmalı.

---

## Faz 2 — Fan-out ve snapshot

### Fan-out

`TerminalLocalPtyBridge` bugün `pty.output`'u tek tüketiciye veriyor
(`local_pty_manager.dart:40-53`). İkinci tüketici eklenmeli: bridge'e opsiyonel
bir çıkış musluğu (`void Function(Uint8List)? outputTap`), `Stream.broadcast`'e
çevirmek yerine — böylece mevcut UTF-8 decode zinciri bozulmaz.

**Musluğun yeri kritik.** Bugünkü boru hattı:

```dart
pty.output
    .cast<List<int>>()          // ← musluk BURAYA girer
    .transform(const Utf8Decoder(allowMalformed: true))
    .listen((String data) => terminal.write(data));
```

Decode `.transform()` adımında oluyor, yani listener gövdesinde ham byte
**kalmıyor**. Musluk `.transform()`'tan önce, `.map()` olarak eklenmeli. Kalıp
zaten repoda — `TerminalMoshBridge` prediction engine'i tam bu şekilde besliyor
(`terminal_mosh_bridge.dart:65-73`):

```dart
session.stdout
    .map((bytes) { predictionEngine.onServerOutput(bytes); return bytes; })
    .transform(const Utf8Decoder(allowMalformed: true))
```

Aynı biçim kopyalanacak; iki bridge stilistik olarak ayrışmamalı.

Telefondan gelen girdi doğrudan `pty.write`'a gider — `bridge.pty` zaten public
(`local_pty_manager.dart:13`), yeni API gerekmiyor. `terminal.onOutput`
kullanılmaz: o slot `TerminalOutputChain`'in ve broadcast/sticky-modifier
interceptor'larının; telefondan gelen byte'ların bunlardan geçmesi yanlış
davranış üretir (örneğin broadcast açıkken telefon girdisi diğer panellere
de kopyalanır).

> String yolu tercih edilirse alternatif `TerminalOutputChain.base`
> (`terminal_output_chain.dart:59-62`) — interceptor'ları atlayarak tek seferlik
> teslim eden, tam bu amaç için var olan API; `broadcast_input_router.dart:63`
> kullanıyor. Ham byte korunduğu için **`pty.write` tercih ediliyor**; `base`
> UTF-8 round-trip'i zorlar ve ikili veride (mouse raporu, kısmi UTF-8) kayıp
> riski taşır.

### Paket birleştirme

Ink tabanlı TUI'ler (Claude Code) spinner için saniyede ~10 redraw basar. Ham
geçişte bu, telefonun WiFi radyosunu hiç uyutmaz. **Frame atlanmaz** — akış
bozulur. Bunun yerine 30-50ms'lik bir tamponda byte biriktirilip tek WS
frame'inde gönderilir: hiçbir şey düşmez, sıra bozulmaz, paket sayısı ~10 kat
azalır. Nagle mantığı.

### Snapshot

`lib/core/network/device_link/device_link_snapshot.dart`

> ⚠️ **Dosya/tip adı değişti.** `xterm3` içinde zaten
> `abstract class TerminalSnapshot` var (`lib/src/core/snapshot.dart:1`, export
> edilmeyen 3 satırlık alakasız internal arayüz). Kütüphaneler ayrı olduğu için
> teknik çakışma yok ama okuyucu yanıltıcı; bizim tip `DeviceLinkSnapshot`.

**İkinci bir headless emulator gerekmiyor.** Masaüstündeki `Terminal`
instance'ı ekranı ve scrollback'i zaten tutuyor; snapshot onun buffer'ının
ANSI'ye geri serialize edilmesi.

### Buffer erişimi — doğrulandı, risk kapandı

Planın ilk sürümündeki "buffer'a erişilemeyebilir" riski **çürüdü**. `xterm3`
6.1.0'da snapshot için gereken her şey public ve `package:xterm3/xterm.dart`
üzerinden export edilmiş durumda:

| İhtiyaç | API |
| :--- | :--- |
| Aktif / ana / alternatif buffer | `Terminal.buffer` `:499`, `.mainBuffer` `:501`, `.altBuffer` `:503` |
| Alternate screen bayrağı | `Terminal.isUsingAltBuffer` `:505` |
| Ölçü | `Terminal.viewWidth` `:409`, `.viewHeight` `:413` |
| Satırlar / scrollback sınırı | `Buffer.lines` `:80`, `.height` `:87`, `.scrollBack` `:110` |
| İmleç | `Buffer.cursorX` `:91`, `.cursorY` `:95`, `Terminal.cursorVisibleMode` `:452` |
| Hücre içeriği | `BufferLine.getCodePoint(i)` `:98`, `.getWidth(i)` `:102`, `.getCombiningCharacters(i)` `:106` |
| Stil | `.getForeground(i)` `:61`, `.getBackground(i)` `:65`, `.getAttributes(i)` `:69`, `.getUnderlineColor(i)` `:110` |
| Boş kuyruk kırpma | `BufferLine.getTrimmedLength([cols])` `:640` |
| Satır sarma | `BufferLine.isWrapped` `:39` (public field) |
| Mod bayrakları | `bracketedPasteMode` `:479`, `autoWrapMode` `:434`, `cursorKeysMode` `:425`, `mouseMode` `:443`, `mouseReportMode` `:446` |

Renk ve stil kodlaması `lib/src/core/cell.dart`'ta belgeli: `CellAttr` bit
maskeleri (bold 1<<0 … encircled 1<<15) ve `CellColor` tip alanları
(`named` 1<<25, `palette` 2<<25, `rgb` 3<<25) SGR'ye doğrudan çevrilebiliyor.
**`CellFlags` kullanılmayacak** — `CellAttr`'ın eksik eski alt kümesi.

> **Ama hazır serializer yok.** `EscapeEmitter` export edilmiyor ve yalnızca
> device-attribute / status / bracketed-paste cevapları üretiyor. SGR run
> emitter'ı bu fazda sıfırdan yazılacak — fazın gerçek maliyeti burada, erişim
> riskinde değil.

> `xterm3` paketinin sahibi biziz (`/Users/mkilic/www/klc/xterm3`, `klc/xterm3`,
> pub.dev'e 6.1.0 olarak yayınlanmış). API'de bir eksik çıkarsa upstream
> beklemeden kapatılabilir; bu, kalan tüm buffer risklerini ikinci dereceye
> indiriyor.

Snapshot'ın taşıması gerekenler:

- Scrollback'in son N satırı (varsayılan 400) — kullanıcı bağlanır bağlanmaz
  yukarı kaydırabilsin
- Ekran hücreleri, SGR run'ları halinde sıkıştırılmış
- İmleç konumu ve görünürlüğü
- **Satır sarma bayrağı** (`BufferLine.isWrapped:39`). Taşınmazsa telefonda
  yeniden boyutlandırmada mantıksal satırlar yanlış yerden bölünür — snapshot ilk
  bakışta doğru görünür, hata ancak resize'da ortaya çıkar.
- **Mod bayrakları**: alternate screen (`vim` açıksa aktif), bracketed paste,
  autowrap, application cursor keys, mouse tracking. Bunlar taşınmazsa
  snapshot'tan **sonraki** byte'lar telefonda yanlış yorumlanır ve hata çok geç
  fark edilir.

### Resize ile snapshot arasındaki yarış

`TIOCSWINSZ` sonrası uygulama `SIGWINCH` alır ama yeniden çizimi **asenkron**
yapar (50-200ms). Beklemeye çalışmak yanlış: "ne kadar" sorusunun sabit cevabı
yok. Doğru davranış snapshot'ı **gecikmeden göndermek** ve arkasından gelen
redraw byte'larının düzeltmesine bırakmak — akış devam ettiği için kendi
kendini onarır.

---

## Faz 3 — Boyut sahipliği ve devir

`TerminalTabSession` (`lib/features/terminal/domain/models/terminal_tab_session.dart:36`)
yeni alan alır: `DeviceLinkAttachment? attachment` (bağlı cihaz kimliği,
devralınmadan önceki `cols`/`rows`, devir zamanı).

Bu alan **opsiyonel değil, zorunlu**: bugün `cols`/`rows` hiçbir yerde
saklanmıyor, yalnızca `terminal.viewWidth` / `viewHeight` üzerinden okunuyor.
Telefon PTY'yi kendi ölçüsüne çektiği anda eski değer kaybolur; saklanacak
başka yer yok.

İki bağlantı noktası:

- **Resize tek boğazdan geçer:** `TerminalTabSession.resizeTerminal(w, h, [pw, ph])`
  (`:156-166`) — `terminal.resize` yapıp `sshBridge` / `moshBridge` / `ptyBridge`'e
  dağıtıyor. Attach, resize ve reclaim hep buradan geçmeli; bridge'e doğrudan
  gidilmeyecek.
- **Teardown sıralaması:** `dispose()` (`:168-209`) prediction reset → outputChain
  → subscription'lar → bridge'ler → `terminal.dispose()` (`:208`) sırasını
  izliyor. `attachment` teardown'ı `terminal.dispose()`'dan **önce** yapılmalı
  (telefona `error`/`detach` gönderip soketi kapatmak için).

| Olay | Davranış |
| :--- | :--- |
| Telefon attach | Mevcut `cols`/`rows` saklanır, PTY telefonun ölçüsüne çekilir, masaüstü UI'ında kalıcı "paylaşımda" göstergesi belirir |
| Telefon döndürme / font değişimi | `resize` mesajı, PTY yeniden boyutlanır |
| **Telefon klavyesi açılır** | **Resize gönderilmez.** Görünür yükseklik yarıya iner ama `rows` sabit kalır; yalnızca görünüm kaydırılır. Aksi halde her klavye açılışında Claude Code yeniden çizer ve ekran zıplar |
| Masaüstünde tuşa basılır | Kontrol masaüstüne döner, PTY eski ölçüsüne çekilir, telefona `reclaimed` gider, telefon izleyici moda düşer |
| Telefon detach / 15 sn ping timeout | PTY eski ölçüsüne döner, gösterge kaybolur |

İzleyici modu için `xterm3`'te yeni bir şey gerekmiyor: `TerminalView.readOnly`
(`terminal_view.dart:128`, `:224`) zaten var ve girdi bağlantısını kapatıyor
(`custom_text_edit.dart:182`, `gesture_handler`, `scroll_handler`). `reclaimed`
mesajı geldiğinde telefon bu prop'u `true`'ya çeker — ayrıca byte gönderimi de
istemci tarafında kesilir (iki katmanlı, UI'a güvenilmez).

Telefonda gerçekçi ölçüler: **portre 45-55 kolon**, yatay 80+. Claude Code 50
kolonda sıkışık ama kullanılabilir; tasarım portre-dar için yapılmalı, yatay
bonus kabul edilmeli.

Masaüstü göstergesi opsiyonel değil: telefondan gelen byte yerel makinede kod
çalıştırıyor, bunun görünmez olması kabul edilemez. Göstergenin yanında tek
tıkla kesme olmalı (`tray_manager` zaten bağımlılıkta).

---

## Faz 4 — Mobil UI

`lib/features/device_link/presentation/`

| Dosya | İçerik |
| :--- | :--- |
| `screens/pairing_qr_screen.dart` | Masaüstü: QR + kalan süre + "iptal" |
| `screens/scan_pair_screen.dart` | Mobil: `mobile_scanner`, izin reddi durumu |
| `screens/linked_session_screen.dart` | Mobil: terminal + durum şeridi |
| `widgets/session_picker_sheet.dart` | `hello_ack`'teki oturum listesi |
| `widgets/compose_sheet.dart` | Uzun metin / dikte girişi |

Terminal görünümü ve `mobile_extra_keys_bar` **yeniden yazılmaz**, mevcut
bileşenler kullanılır — Device Link onlara farklı bir byte kaynağı bağlamaktan
ibaret olmalı.

### Hangi bileşen yeniden kullanılır

Planın ilk sürümü yanlış dosyayı işaret ediyordu. Doğrusu:

| Bileşen | Durum |
| :--- | :--- |
| `views/terminal_tab_view.dart:52` | ❌ **Kullanılmaz.** `const TerminalTabView({super.key})` — hiç girdi almıyor, her şeyi Riverpod'dan okuyor; masaüstü sekme çubuğu chrome'u |
| `screens/terminal_screen.dart:17` | ✅ **Asıl hedef.** `TerminalScreen(session, showExtraKeys)` — `TerminalView`'ı `:216-247` arasında kuran sarmalayıcı |
| `widgets/mobile_extra_keys_bar.dart:7` | ✅ **Koşulsuz kullanılır.** Düz `StatefulWidget`, Riverpod yok, `TerminalTabSession` bilmiyor; girdileri `terminal` / `outputChain` / `onInput`, üçü de opsiyonel |

`TerminalScreen` bedava değil: `session.id`, `isConnecting`, `sessionType`,
`host`, `isConnected`, `errorMessage`, `disconnectCause` alanlarını okuyor ve
`terminalTabsProvider`'a `tapPane` / `reconnectTab` çağırıyor (`:95-97`, `:195-197`).

**Karar: device-link oturumu gerçek bir `TerminalTabSession` olarak
`terminalTabsProvider`'a kaydedilir.** Telefon, bridge'i WebSocket olan bir sekme
açmış olur; `TerminalScreen` olduğu gibi çalışır, mobil ekran yalnızca durum
şeridini ekler. Alternatif (`TerminalView` + `MobileExtraKeysBar`'ı elle kurup
`TerminalScreen`'i atlamak) yeniden bağlanma bannerını ve pane davranışını
tekrar yazmayı gerektirir — reddedildi.

Bu kararın yan etkisi: `sessionType` enum'una (`terminal_tab_session.dart:18`,
bugün `{ssh, local}`) üçüncü bir üye mi ekleneceği, yoksa Mosh gibi bayrakla mı
(`isMosh` `:90` kalıbı) ayrışacağı Faz 4'ün ilk kararı. **Bayrak tercih ediliyor**
— enum'a dokunmak tüm switch'leri kırar.

### Oturum seçici

Masaüstünde birden fazla sekme açık olabilir. "Aktif olana bağlan" varsayımı
ilk yanlış tahminde can sıkar; `hello_ack` listeyi taşıyor, kullanıcı seçiyor.
Oturum değiştirme aynı mekanizma: `detach` → `attach` → yeni snapshot.

Liste bedava geliyor: `TerminalTabsNotifier._ownedTabs`
(`terminal_tabs_notifier.dart:88`) yetkili kayıt; `{id, title, sessionType}`
doğrudan oradan türetiliyor, yeni tesisat yok.

### Compose sheet

Ham terminale telefondan paragraf yazmak kullanılamaz: imleç hareketi acı,
dikte düzgün çalışmaz, otomatik düzeltme kavga eder. Native bir `TextField`
(dikte destekli) metni toplar, gönderirken **bracketed paste** ile sarar:

```
ESC [ 200 ~   <metin>   ESC [ 201 ~
```

Sarmalanmazsa metindeki ilk `\n` Claude Code'a submit olarak gider ve prompt
yarıda kesilir. `attached` mesajındaki `bracketedPaste` bayrağı false ise
sarmalama yapılmaz (uygulama modu desteklemiyor demektir).

---

## Faz 5 — Kalıcı eşleştirme ve otomatik bağlanma

### Drift tablosu

`lib/shared/database/tables.dart` içine `PairedDevices`, DAO'su
`lib/shared/database/daos/paired_devices_dao.dart`.

> DAO'nun `lib/shared/database/daos/` altında olması `AGENTS.md` §2.1'in lafzıyla
> ("DAO'lar `features/<name>/data`") çelişiyor, ama repodaki sekiz DAO'nun tamamı
> orada. **Repo precedent'i izleniyor**; sapma bilinçli.

Somut adımlar (`AGENTS.md` §2.4 atfı gevşekti — orada migration maddesi yok,
gerçek kısıt kodda):

1. `PairedDevices` tablosunu `tables.dart`'a ekle (`Hosts:43` kalıbı; `id` PK
   `text()`, `Set<Column> get primaryKey => {id}`).
2. `app_database.dart:20-44` — hem `tables:` hem `daos:` listesine ekle.
3. `app_database.dart:49` — `schemaVersion` **5 → 6**.
4. `app_database.dart:87` civarı — `if (from < 6) { await m.createTable(pairedDevices); }`.
   `from < 4` dalı (`:79-80`) birebir örnek.
5. `build_runner` çalıştır.
6. Migration testi: `test/unit/shared/database/database_migration_test.dart`
   zaten var, oraya vaka eklenir.

| Sütun | Tip | Not |
| :--- | :--- | :--- |
| `id` | text, PK | Cihazın ürettiği kalıcı kimlik |
| `name` | text | "iPhone 15" — kullanıcıya gösterilen |
| `platform` | text | ios / android |
| `secretHash` | text | Argon2id; **düz metin sır asla yazılmaz** |
| `publicKey` | text | İleride mTLS'e geçiş için saklanıyor |
| `pairedAt` / `lastSeenAt` | datetime | Ayarlar ekranında gösterilir |

### Ayarlar ekranı

`lib/features/settings/presentation/` altında "Eşleşmiş cihazlar": liste, son
görülme zamanı, **kaldır**. Telefon kaybedildiğinde erişimi kesebilmek için
zorunlu.

### Otomatik yeniden bağlanma

Uygulama öne geldiğinde: mDNS keşfi → saklı kimlikle bağlan → `attach` →
snapshot. Kullanıcı hiçbir şeye basmaz. QR yalnızca ilk eşleştirmede.

Ağ değişimi sinyali hazır: `connectivity_plus` (^7.3.1) zaten bağımlılıkta ve
`TerminalTabsNotifier._watchConnectivity()` (`terminal_tabs_notifier.dart:123-127`)
Mosh rehoming'i için `onConnectivityChanged`'i dinliyor. Device Link aynı akıştan
beslenir — WiFi değişiminde yeniden keşif tetiklenir.

`v1` protokol sürümü uyuşmazlığında (uygulamalar farklı sürümde) `error`
mesajı net olmalı — sessiz başarısızlık en kötüsü.

---

## Faz 6 — Sonraki adımlar (ayrı kararlar)

1. **SSH oturumlarının aynalanması.** `TerminalSSHBridge` de bir `Terminal`
   besliyor; mekanizma aynı, fan-out noktası farklı.
2. **Bildirim kanalı.** Feature'ın en büyük ergonomi açığı. Üç seçenek, üçü de
   bir şeyden feragat ediyor:
   - *Bildirim yok* — yalnızca uygulama açıkken çalışır, değerin yarısı gider.
   - *Yalnızca-uyandırma relay'i* — bulutta minik bir servis, sadece "bir şey
     oldu" sinyali taşır; terminal verisi LAN'da kalır (control plane bulutta,
     data plane LAN'da). Sıfır-altyapı hedefini deler.
   - *Kullanıcının kendi kanalı* — ntfy / Pushover / Telegram bot. Sıfır
     altyapı, ama kurulum sürtünmesi.
3. **Claude Code hook entegrasyonu.** `PreToolUse` / `Notification` / `Stop`
   hook'ları, ekran kazımadan yapısal olay üretir. PTY seviyesi mimariyle
   çelişmiyor — bağımsız bir yan kanal.
4. **Mutual TLS.** Bearer sır yerine istemci sertifikası.

---

## Güvenlik notları

| Tehdit | Karşı önlem |
| :--- | :--- |
| Aynı ağdaki saldırgan MITM | QR'dan pinlenen SPKI parmak izi |
| Ekranın fotoğrafı / omuz sörfü | QR TTL 90 sn + tek kullanım |
| Çalınan/kaybolan telefon | Ayarlardan cihaz kaldırma; sır cihazda `flutter_secure_storage`'da |
| Masaüstü veritabanının sızması | Sır düz metin değil, Argon2id hash olarak saklanır |
| Kullanıcının haberi olmadan paylaşım | Masaüstünde kalıcı gösterge + tek tıkla kesme |
| Yerel ağ izninin reddi | Tespit edilip açık hata; sessiz başarısızlık yok |

Telefondan gelen her byte yerel makinede kod çalıştırıyor. Bu feature'ın tehdit
modeli SSH istemcisininkinden **daha ağır**, çünkü hedef kullanıcının kendi
geliştirme makinesi.

---

## Riskler ve azaltım

| Risk | Etki | Azaltım |
| :--- | :--- | :--- |
| ~~`xterm3` buffer'ı dışarıdan serialize edilemiyor~~ | — | **Kapandı.** API taraması buffer, hücre, stil ve tüm mod bayraklarının public olduğunu gösterdi; paket zaten bizim fork'umuz |
| SGR run emitter'ı elle yazılıyor, kenar durumları kaçıyor | Snapshot telefonda bozuk görünür, hata geç fark edilir | Round-trip testi (iki buffer'ın hücre hücre eşitliği) Faz 2 kabul kriteri; wide char, combining char, alternate screen, 256-renk ve RGB ayrı vakalar |
| TLS + WebSocket için repoda precedent yok | Faz 1 tahminden uzun sürer | Fazın ilk işi sertifika üretimi + pinleme (protokol şeması değil); `pointycastle` + `asn1lib` ile denenip gerekirse `basic_utils`'a düşülür |
| iOS yerel ağ izni reddi / Bonjour aksaklığı | Mobil hat çalışmaz | QR'daki doğrudan IP listesi mDNS'e bağımlılığı azaltıyor; mDNS yalnızca yeniden bağlanmada kritik |
| AP isolation (ofis/misafir WiFi) | Bağlantı hiç kurulamaz | Teşhis edilebilir hata mesajı + dokümantasyonda Tailscale önerisi |
| App Store, uzak kod yürütme gerekçesiyle reddeder | Mobil hat kapanır | Roadmap §7'de zaten izlenen risk; Device Link bunu **artırıyor**, review öncesi hukuki/politika kontrolü |
| Telefon ölçüsüne resize kullanıcıyı şaşırtır | Güven kaybı | Masaüstünde açık bildirim şeridi + kolay geri alma |
| iOS arka planda oturumun kopması | "Sürekli bağlı" hissi yok | Öne gelişte otomatik yeniden bağlanma; snapshot sayesinde ucuz |
| Test edilebilirlik (iki cihaz gerekir) | Regresyon riski | Protokol katmanı `127.0.0.1` üzerinden entegrasyon testiyle CI'da; UI elle |

---

## Doğrulama

`AGENTS.md` §3 gereği her fazın çıkışında `dart analyze` sıfır uyarı ve
`flutter test` tam yeşil.

Faza özel kabul kriterleri:

- **Faz 0** — Dört yeni paket `pubspec.lock`'u kırmadan çözülüyor; iOS/Android
  izin anahtarları yerinde; `tool/device_link/` iskeleti duruyor.
- **Faz 1** — `127.0.0.1` üzerinden server↔client entegrasyon testi: eşleştirme,
  yanlış token reddi, yanlış SPKI reddi, protokol sürüm uyuşmazlığı, TTL dolmuş
  token reddi, tek kullanımlık token'ın ikinci kullanımının reddi.
- **Faz 2** — İki ayrı test kümesi:
  - *Fan-out:* muslukta akan verinin **ham byte** olduğu (decode edilmiş `String`
    değil) ve `terminal.write`'ın etkilenmediği.
  - *Snapshot round-trip:* bilinen bir ANSI dizisiyle beslenen `Terminal`'in
    serialize edilip ikinci bir `Terminal`'e yazılması, iki buffer'ın hücre hücre
    eşitliği. Ayrı vakalar: alternate screen, SGR run'ları, 256-renk, 24-bit RGB,
    çift genişlikli karakter, combining character, **sarılmış satır (`isWrapped`)
    ve ardından resize**, mod bayraklarının aktarımı.
- **Faz 3** — Attach/detach/reclaim sonrası PTY ölçüsünün doğru geri alınması.
- **Faz 4** — Bracketed paste sarmalama testi; çok satırlı metnin tek submit
  üretmesi.
- **Faz 5** — Migration testi; QR'sız yeniden bağlanma; cihaz kaldırma sonrası
  eski sırla bağlanma denemesinin reddi.

Uçtan uca elle senaryo (iki cihaz): masaüstünde `flutter test` başlat → telefondan
bağlan → çıktıyı izle → uçak moduna al, geri getir → oturum devam ediyor mu →
compose sheet ile çok satırlı komut gönder → masaüstünde tuşa bas, kontrol geri
alınıyor mu.

---

## Önerilen sıralama

Faz 1-2-3 birlikte **ince ama uçtan uca çalışan bir iskelet** üretir: QR →
bağlan → resize → snapshot → ham akış, tek oturum, kalıcı eşleştirme yok.
Bu iskelet ayakta durmadan Faz 4-5'e geçilmemeli; ikisi de üstüne bağımsız
olarak binen parçalar.

**Risk profili kaydı.** İlk sürümde en uzun kalem Faz 2 (buffer erişimi
belirsizdi) sanılıyordu. Doğrulama sonrası ağırlık **Faz 1'e** geçti: TLS
sertifikası üretimi ve SPKI pinlemesi için repoda hiçbir precedent yok, oysa
Faz 2'nin buffer tarafı tamamen çözülmüş durumda (kalan iş sadece SGR emitter'ı).
Sıralama değişmiyor, ama Faz 1'e ayrılan süre artırılmalı.
