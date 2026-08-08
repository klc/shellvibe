# Device Link — Masaüstü Terminalini Telefona Bağlama

> Tarih: 2026-08-08 · Durum: taslak, onay bekliyor · İlgili: `docs/tech_spec.md`,
> `docs/product_roadmap_2026-08-07.md`, `AGENTS.md` §2.3

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
| Masaüstünde PTY + emulator | `lib/core/network/local_pty_manager.dart` (`TerminalLocalPtyBridge`) |
| Mobilde terminal render | `xterm3` + `lib/features/terminal/presentation/views/terminal_tab_view.dart` |
| Mobil klavye (Esc/Ctrl/ok tuşları) | `lib/features/terminal/presentation/widgets/mobile_extra_keys_bar.dart` |
| Oturuma girdi enjekte etme noktası | `lib/features/terminal/domain/services/terminal_output_chain.dart` |
| Şifreli kalıcı depolama | `cryptography` + `flutter_secure_storage` |

Eksik olan tek şey iki cihaz arasındaki **taşıma katmanı**.

> ⚠️ `docs/product_roadmap_2026-08-07.md` §9 önümüzdeki 8 hafta yeni özellik
> yazılmamasını öneriyor. Bu plan o tavsiyeyle çelişiyor; bilinçli bir istisna
> olarak onaylanmalı ya da roadmap'in ilerisine alınmalı.

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
- **Predictive local echo.** LAN'da RTT 2-5ms; gerek yok. (Mosh planındaki
  Faz 2 predictor'ı ile karıştırılmamalı — ayrı iş.)
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

Fan-out noktası `TerminalLocalPtyBridge`: bugün `pty.output`'u tek bir yere
(`terminal.write`) veriyor, ikinci bir tüketici eklenecek. Telefondan gelen
girdi `pty.write`'a gitmeli — `terminal.onOutput` üzerinden **değil**, çünkü o
slot `TerminalOutputChain` tarafından yönetiliyor ve interceptor'ları
(broadcast, sticky modifier) telefondan gelen byte'lara uygulanmamalı.

---

## Faz 0 — Bağımlılıklar ve doğrulama zemini

### Yeni paketler

| Paket | Kullanım | Not |
| :--- | :--- | :--- |
| `nsd` | mDNS servis kaydı (masaüstü) + keşif (mobil) | Hem `register` hem `discover` destekliyor; `multicast_dns` yalnızca keşif yapabildiği için yetersiz |
| `qr_flutter` | QR üretimi (masaüstü) | |
| `mobile_scanner` | QR okuma (mobil) | Kamera izni gerekir |
| `basic_utils` | Self-signed X.509 üretimi | `pointycastle` üzerine kurulu, o da `dartssh2` ile zaten `pubspec.lock`'ta |

WebSocket sunucusu için **yeni paket yok**: `dart:io`'nun
`HttpServer.bindSecure` + `WebSocketTransformer.upgrade` kombinasyonu yeterli.
`shelf` eklemeye gerek duyulmamalı.

### Platform yapılandırması

- **iOS** `ios/Runner/Info.plist`: `NSLocalNetworkUsageDescription`,
  `NSBonjourServices` (`_terly._tcp`), `NSCameraUsageDescription`.
  Bugün üçü de yok. Kullanıcı yerel ağ iznini reddederse feature sessizce
  çalışmaz — bu durum tespit edilip anlamlı bir hata gösterilmeli.
- **macOS**: `com.apple.security.network.server` ve `.client` entitlement'ları;
  ilk çalıştırmada gelen firewall istemi code signing olmadan her seferinde
  tekrarlanır.
- **Android**: `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE` (mDNS için),
  `CAMERA`.
- **Windows/Linux**: firewall kuralı kullanıcıya bırakılıyor; bağlantı
  kurulamazsa hata mesajında bundan bahsedilmeli.

### Doğrulama harness'ı

`tool/` altına, kaynak ağacına değil: iki cihaz gerektirdiği için CI'da
koşamaz. Elle koşulan bir smoke script + protokol katmanı için gerçek soket
kullanan entegrasyon testleri (aynı makinede `127.0.0.1` üzerinden
server↔client). Faz 1'in çıkışı bu testlerin geçmesi.

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

---

## Faz 2 — Fan-out ve snapshot

### Fan-out

`TerminalLocalPtyBridge` bugün `pty.output`'u tek tüketiciye veriyor
(`local_pty_manager.dart:39-52`). İkinci tüketici eklenmeli. Önerilen biçim:
bridge'e opsiyonel bir çıkış musluğu (`void Function(Uint8List)? outputTap`),
`Stream.broadcast`'e çevirmek yerine — böylece mevcut UTF-8 decode zinciri
bozulmaz ve muslukta **ham byte** akar (decode edilmiş `String` değil).

Telefondan gelen girdi doğrudan `pty.write`'a gider. `terminal.onOutput`
kullanılmaz: o slot `TerminalOutputChain`'in ve broadcast/sticky-modifier
interceptor'larının; telefondan gelen byte'ların bunlardan geçmesi yanlış
davranış üretir (örneğin broadcast açıkken telefon girdisi diğer panellere
de kopyalanır).

### Paket birleştirme

Ink tabanlı TUI'ler (Claude Code) spinner için saniyede ~10 redraw basar. Ham
geçişte bu, telefonun WiFi radyosunu hiç uyutmaz. **Frame atlanmaz** — akış
bozulur. Bunun yerine 30-50ms'lik bir tamponda byte biriktirilip tek WS
frame'inde gönderilir: hiçbir şey düşmez, sıra bozulmaz, paket sayısı ~10 kat
azalır. Nagle mantığı.

### Snapshot

`lib/core/network/device_link/terminal_snapshot.dart`

**İkinci bir headless emulator gerekmiyor.** Masaüstündeki `Terminal`
instance'ı ekranı ve scrollback'i zaten tutuyor; snapshot onun buffer'ının
ANSI'ye geri serialize edilmesi.

> **Faz 2'nin ilk işi:** `xterm3` 6.x'in buffer API'sinin hücre içeriğine ve
> stil bayraklarına dışarıdan erişime izin verdiğini doğrulamak. İzin
> vermiyorsa iki seçenek var — paketi fork edip erişim açmak, ya da PTY
> çıktısını ayrıca besleyen ikinci bir `Terminal` tutmak (bellek maliyeti var
> ama API riski yok). Bu doğrulama başarısız olursa faz ~3 gün uzar.

Snapshot'ın taşıması gerekenler:

- Scrollback'in son N satırı (varsayılan 400) — kullanıcı bağlanır bağlanmaz
  yukarı kaydırabilsin
- Ekran hücreleri, SGR run'ları halinde sıkıştırılmış
- İmleç konumu ve görünürlüğü
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

`TerminalTabSession`'a yeni alan: `DeviceLinkAttachment? attachment`
(bağlı cihaz kimliği, devralınmadan önceki `cols`/`rows`, devir zamanı).

| Olay | Davranış |
| :--- | :--- |
| Telefon attach | Mevcut `cols`/`rows` saklanır, PTY telefonun ölçüsüne çekilir, masaüstü UI'ında kalıcı "paylaşımda" göstergesi belirir |
| Telefon döndürme / font değişimi | `resize` mesajı, PTY yeniden boyutlanır |
| **Telefon klavyesi açılır** | **Resize gönderilmez.** Görünür yükseklik yarıya iner ama `rows` sabit kalır; yalnızca görünüm kaydırılır. Aksi halde her klavye açılışında Claude Code yeniden çizer ve ekran zıplar |
| Masaüstünde tuşa basılır | Kontrol masaüstüne döner, PTY eski ölçüsüne çekilir, telefona `reclaimed` gider, telefon izleyici moda düşer |
| Telefon detach / 15 sn ping timeout | PTY eski ölçüsüne döner, gösterge kaybolur |

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

### Oturum seçici

Masaüstünde birden fazla sekme açık olabilir. "Aktif olana bağlan" varsayımı
ilk yanlış tahminde can sıkar; `hello_ack` listeyi taşıyor, kullanıcı seçiyor.
Oturum değiştirme aynı mekanizma: `detach` → `attach` → yeni snapshot.

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
`lib/shared/database/daos/paired_devices_dao.dart`. Schema versiyonu artar,
migration yazılır (`AGENTS.md` §2.4).

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
| `xterm3` buffer'ı dışarıdan serialize edilemiyor | Snapshot yapılamaz, feature'ın temeli gider | Faz 2'nin **ilk** işi bunu doğrulamak; fallback olarak ikinci `Terminal` instance'ı |
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

- **Faz 1** — `127.0.0.1` üzerinden server↔client entegrasyon testi: eşleştirme,
  yanlış token reddi, yanlış SPKI reddi, protokol sürüm uyuşmazlığı.
- **Faz 2** — Snapshot round-trip testi: bilinen bir ANSI dizisiyle beslenen
  `Terminal`'in serialize edilip ikinci bir `Terminal`'e yazılması, iki buffer'ın
  hücre hücre eşitliği. Alternate screen ve SGR run'ları ayrı vaka.
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
