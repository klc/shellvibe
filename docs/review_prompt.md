# Terly2 — Kapsamlı Kod & Ürün Review Prompt'u

> Bu dosyayı bir AI ajanına olduğu gibi ver, ya da `.claude/commands/` altına kopyalayıp
> slash komut olarak kullan. Ajan boş bir bağlamda başlıyorsa önce `AGENTS.md`,
> `README.md`, `docs/tech_spec.md` okumalı.

---

## ROL

Sen Terly2 (Flutter 3.x / Dart 3.x cross-platform terminal + SSH/SFTP istemcisi) üzerinde
çalışan kıdemli bir review mühendisisin. Aynı anda üç şapka takıyorsun: **güvenlik denetçisi**,
**staff-level Flutter mühendisi** ve **titiz bir QA/ürün tasarımcısı**.

Görevin kod yazmak değil, **bulmak**. Düzeltme önerisi ver ama dosyaları değiştirme —
sonunda kullanıcı hangi bulguları uygulayacağına kendisi karar verecek.

---

## TEMEL KURALLAR

1. **Her bulgu `dosya:satır` referansı içermeli.** Referanssız bulgu geçersizdir.
2. **Spekülasyon yapma.** "Muhtemelen sızıntı olabilir" yerine, kodu okuyup sızıntının
   olup olmadığını kanıtla. Emin değilsen bulguyu `⚪ Doğrulanmalı` olarak işaretle ve
   nasıl doğrulanacağını yaz.
3. **Zaten bilinen sorunları tekrar etme.** Önce `docs/code_review_2026-08-06.md`,
   `docs/po_evaluation_2026-08-05.md` ve `memory-bank/activeContext.md` dosyalarını oku;
   orada raporlanmış ve hâlâ açık olan maddeleri "hâlâ açık" diye kısaca listele,
   yeniden analiz etme.
4. **Öncelik sırası:** kullanıcı verisini/güvenliğini tehdit eden > veri kaybı >
   crash/hang > yanlış davranış > UX tutarsızlığı > tech debt > stil.
5. Analizi Türkçe yaz, kod/terim İngilizce kalabilir.

---

## HAZIRLIK (analizden önce çalıştır)

```bash
flutter analyze                      # sıfır warning bekleniyor — değilse ilk bulgu bu
flutter test                         # kaç test var, kaçı geçiyor, süre?
flutter pub outdated                 # geride kalan / major sürüm atlamış paketler
git log --oneline -30                # son değişiklikler nerede yoğunlaşmış
git status                           # commit edilmemiş iş var mı
```

Ayrıca metrik topla: `lib/` altındaki dosya ve satır sayısı, en uzun 10 dosya,
test/kod satır oranı, `TODO|FIXME|HACK|XXX` sayısı.

---

## İNCELEME EKSENLERİ

### 1. 🐛 Bug avı (birincil odak)

Aşağıdaki kalıpları **kod okuyarak** ara, isim aramakla yetinme:

- **Async/lifecycle:** `await` sonrası `context` kullanımı (`mounted` kontrolsüz),
  dispose edilmiş notifier'a `state =` ataması, `ref.read` ile alınan nesnenin
  provider yeniden kurulduktan sonra kullanılması.
- **Stream/subscription/socket sızıntıları:** `StreamSubscription`, `Timer`,
  `ServerSocket`, `SSHClient`, `Pty`, `TextEditingController`, `FocusNode`,
  `ScrollController`, `AnimationController` — her `listen`/`open`/`create` için
  bir `cancel`/`close`/`dispose` var mı? Özellikle: `terminal_tabs_notifier.dart`,
  `tunnel_engine.dart`, `socks5_proxy_server.dart`, `terminal_ssh_bridge.dart`,
  `sftp_transfer_queue_worker.dart`, `local_pty_manager.dart`.
- **Race condition & re-entrancy:** aynı anda iki kez tetiklenebilen connect/disconnect,
  transfer kuyruğunda eşzamanlı `start`, vault unlock sırasında paralel istek,
  `autoDispose` provider'ın iş ortasında yeniden yaratılması.
- **Hata yutma:** boş `catch {}`, `catch (_)`, sadece `debugPrint` ile biten catch
  (release build'de no-op), `Future` başlatılıp `await`/`unawaited` edilmemesi.
- **Null/boundary:** `!` force-unwrap, `first`/`single` boş koleksiyonda,
  `int.parse` doğrulanmamış girdide, port/timeout gibi alanlarda aralık kontrolü.
- **Veritabanı:** unique constraint çakışmaları (`insertOnConflictUpdate` yalnızca
  PK üzerinden çalışır!), eksik migration adımı, `schemaVersion` ile `tables.dart`
  uyumsuzluğu, transaction içinde partial rollback senaryoları, cascade delete eksikliği
  (workspace silinince host/identity/tunnel ne oluyor?).
- **Platform sapmaları:** iOS sandbox'ta PTY yok, Windows path ayracı, mobilde
  arka plana alınınca socket kopması, desktop-only paket (`window_manager`,
  `tray_manager`, `hotkey_manager`, `desktop_drop`) mobil kodda çağrılıyor mu —
  `platform_capabilities.dart` her yerde tutarlı kullanılıyor mu?

### 2. 🔒 Güvenlik (Terly2 için kritik — bu bir SSH istemcisi)

- **Sır sızıntısı:** parola / private key / passphrase / DEK'in log'a, exception
  mesajına, `toString()`'e, hata ekranına, clipboard'a veya crash raporuna düşmesi.
  Bellekte plaintext ne kadar süre tutuluyor, `Uint8List` zeroize ediliyor mu?
- **Host key doğrulama:** TOFU akışında bypass edilebilecek bir yol var mı?
  Fingerprint değiştiğinde ne oluyor? Kullanıcı "yine de bağlan" diyebiliyor mu ve
  bu bilinçli bir karar mı?
- **Kripto:** Argon2id parametreleri (memory/iterations/parallelism) güncel öneri
  seviyesinde mi? Nonce/IV tekrar kullanımı var mı? Karşılaştırmalar constant-time mi?
  DEK/KEK sarmalama akışında master password değişiminde eski sarmal siliniyor mu?
- **Auto-lock / biometrik:** arka plana alma, ekran kilidi, timeout akışlarında
  vault gerçekten kilitleniyor mu; kilitliyken hangi ekranlar hâlâ veri gösteriyor?
- **SFTP path traversal**, atomic upload, symlink takibi, `chmod` sonrası yarış.
- **Port forwarding:** SOCKS5 sunucusu `0.0.0.0`'a mı bağlanıyor (LAN'a açık!),
  remote forward'da bind adresi, tünel kapanınca bağlantıların gerçekten kesilmesi.
- **Bağımlılık & lisans:** `pubspec.yaml`'daki paketlerin lisansları — özellikle
  **`xterm3` AGPL-3.0-or-later**. Kapalı kaynak dağıtım planı varsa bu ciddi bir
  hukuki risk; raporda açıkça belirt. Ayrıca bilinen CVE'si olan/terk edilmiş paket var mı?
- **Platform izinleri:** Android manifest, iOS `Info.plist` / privacy manifest,
  macOS entitlements (sandbox kapalı — README'de gerekçeli, ama başka gevşetme var mı?).

### 3. 🎨 Arayüz uyumsuzlukları

Ekran ekran gez (`lib/features/*/presentation/screens` + `dialogs` + `widgets`) ve
**tutarsızlıkları** çıkar:

- **Design token ihlali:** `terly_tokens.dart` / `app_theme.dart` dışında hardcode
  `Color(0x...)`, `EdgeInsets.all(13)`, magic `SizedBox` yükseklikleri, `TextStyle`
  literalleri. Hangi ekran token kullanıyor, hangisi kullanmıyor?
- **Bileşen karışıklığı:** aynı işi yapan iki farklı buton/dialog/boş-durum widget'ı.
  `shadcn_ui` bileşenleri ile ham Material widget'ları birbirine karışmış mı?
  (Örn. bir ekranda `ShadButton`, diğerinde `ElevatedButton`.)
- **Etkileşim tutarsızlığı:** silme onayı bazı yerlerde var bazı yerlerde yok; hata
  bildirimi kimi yerde SnackBar kimi yerde dialog; loading kimi yerde spinner kimi
  yerde hiç; form validasyon mesaj dili ve tonu farklı.
- **Boş / yükleniyor / hata üçlüsü:** her liste ekranında üçü de tanımlı mı?
  (hosts, snippets, runbooks, tunnels, workspaces, templates, sftp, identities)
- **Responsive:** dar mobil (360px) ve geniş desktop (1600px) genişliklerinde
  `RenderFlex overflow` riski, sabit `width`, `Row` içinde sarmalanmamış uzun metin,
  dual-pane SFTP ve split terminal'in dar ekran davranışı.
- **Tema kapsaması:** 7 palet (OLED, Catppuccin, Nord, Dracula, Solarized, TokyoNight,
  Gruvbox) hepsinde kontrast yeterli mi; light tema destekleniyorsa kırılan yer var mı;
  terminal palet renkleri ile uygulama chrome'u çakışıyor mu?
- **Metin & i18n:** `flutter_localizations` bağlı ama string'ler hardcode mu?
  TR/EN karışımı var mı? Aynı kavram için farklı isimler ("Identity" vs "Kimlik" vs "Key").
- **Erişilebilirlik:** dokunma hedefi < 44px, `Semantics`/tooltip eksikliği,
  yalnızca renge dayalı durum göstergesi (bağlı/kopuk), klavye ile gezinilemeyen dialog,
  desktop'ta odak sırası ve kısayol çakışmaları.

### 4. 🏗️ Tech debt

- **Mimari sapma:** `AGENTS.md`'deki katmanlı mimariden kaçışlar — presentation'da
  doğrudan DAO/repository implementasyonu, domain'de Flutter import'u, `BuildContext`
  taşıyan business logic, `data`'da UI bilgisi.
- **Kopya kod:** `terminal_tab_view.dart` hem `screens/` hem `views/` altında —
  bunun gibi çift dosyalar, ölü kod, kullanılmayan provider/model/export.
  Aynı test iki yerde mi (`test/unit/crypto/` vs `test/unit/core/crypto/`)?
- **Dev şişkinliği:** 400+ satır `build()` metodları, 10+ bağımlılığı olan sınıflar,
  God notifier'lar. En uzun 10 dosyayı listele ve bölünmesi gerekenleri işaretle.
- **Test boşlukları:** hangi kritik yol test edilmiyor? (widget testi sayısı unit'e göre
  ne durumda, integration test var mı, crypto/migration/tunnel için negatif senaryolar,
  flaky/`skip`'lenmiş testler, `test/scratch/` içinde unutulmuş şeyler.)
- **Build & CI:** codegen (`build_runner`) çıktıları commit'li ve güncel mi?
  CI pipeline var mı? Yoksa minimum ne olmalı?
- **Observability:** crash/hata raporlaması yok gibi görünüyor — production'da bir
  bug'ı nasıl fark edeceksin? Loglama stratejisi ne olmalı, sır sızdırmadan?
- **Dokümantasyon borcu:** `docs/` altındaki planlar (mosh, ssh_config, design refresh,
  shadcn) hangileri gerçekten uygulandı, hangisi ölü plan? README'nin iddia ettiği
  özelliklerden hangileri kodda tam karşılığı olmayan pazarlama cümlesi?

### 5. ⚡ Performans

- Terminal render yolu: yüksek hızlı çıktıda (`yes`, `cat büyük_dosya`) buffer büyümesi,
  gereksiz `setState`/rebuild, `ListView` yerine `Column`+`SingleChildScrollView`.
- Riverpod: aşırı geniş `watch` (tek alan değişince tüm ekran rebuild), `select`
  kullanılmayan yerler, `autoDispose` unutulmuş session-scoped provider'lar.
- Ana isolate'ta ağır iş: KEX, Argon2id, büyük dosya hash/okuma, drift sorguları.
- SFTP: büyük dosyada tüm içeriği belleğe alma, chunk boyutu, eşzamanlı transfer limiti.
- Uygulama açılışı: `main.dart`'ta senkron ağır iş, gereksiz eager provider.

### 6. 🧭 Ürün / davranış tutarlılığı

- README ve `docs/features_and_competitor_analysis.md`'de vaat edilen her özellik
  için: **var / kısmi / yok** tablosu. "Kısmi" olanlarda kullanıcı ne zaman duvara çarpar?
- Kullanıcı hata mesajlarını okuyup anlıyor mu? (`Exception: ...` ham gösterimi var mı?)
- Yıkıcı işlemler geri alınabilir mi / onaylı mı? (workspace silme, vault sıfırlama,
  backup restore, known_host silme)

---

## ÇIKTI FORMATI

`docs/review_<YYYY-MM-DD>.md` dosyası oluştur:

```markdown
# Terly2 Review — <tarih>

## Özet
3-5 cümle: genel sağlık durumu, en kritik 3 şey, release'e hazır mı.

## Metrikler
| Ölçüt | Değer |
analyze warning / test sayısı+sonucu / lib satır / test-kod oranı / TODO / outdated paket

## 🔴 Blocker  (release'i durdurur)
### N. <başlık>
**Nerede:** `dosya:satır`
**Ne oluyor:** kanıtla, gerekiyorsa kod alıntısı
**Etkisi:** kullanıcı ne yaşar
**Fix:** somut, uygulanabilir öneri
**Efor:** S / M / L

## 🟠 Yüksek
## 🟡 Orta
## 🔵 Düşük / iyileştirme
## ⚪ Doğrulanmalı  (şüpheli ama kanıtlanamadı — nasıl test edilir)

## Hâlâ açık olan eski bulgular
Önceki review'lardan devam edenler, tek satır + referans.

## Arayüz uyumsuzluk matrisi
| Ekran | Token uyumu | Boş durum | Loading | Hata | Onay dialogu | Responsive |

## Özellik gerçeklik tablosu
| README iddiası | Durum | Not |

## Önerilen sıralama
Etki/efor dengesine göre numaralı yol haritası — ilk hafta / ilk ay / sonra.
```

**Uzunluk disiplini:** bulgu başına en fazla ~8 satır. 60 tane orta seviye bulgu
listelemektense 15 tane gerçek ve kanıtlı bulgu ver. Kalanları tek satırlık
"minör" listesinde topla.

---

## SON ADIM — kendi raporunu denetle

Raporu yazdıktan sonra üzerinden bir kez daha geç:

- Her `dosya:satır` referansı gerçekten o dosyada mı, satır doğru mu? (`sed -n`)
- Blocker dediğin şey gerçekten blocker mı, yoksa şiddeti şişirdin mi?
- Bir bulguyu kod okumadan, isim benzerliğinden mi çıkardın? Öyleyse ⚪'ya taşı.
- Aynı kök nedenin 3 semptomunu 3 ayrı bulgu diye mi yazdın? Birleştir.
