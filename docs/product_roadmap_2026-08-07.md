# Terly2 — PO Değerlendirmesi ve Ürünleşme Yol Haritası

**Tarih:** 7 Ağustos 2026
**Önceki raporlar:** [`product_owner_evaluation.md`](product_owner_evaluation.md) (2 Ağu), [`po_evaluation_2026-08-05.md`](po_evaluation_2026-08-05.md) (5 Ağu)
**Yöntem:** Doküman iddiaları değil, kod tabanı üzerinde ölçüm (`git log`, grep, dosya sayımı).
**Girdi varsayımları:** Freemium abonelik modeli · tek kişi full-time · 5 platform hedefi · 6 aylık ufuk.

---

## 1. Yönetici Özeti

**Elinde çok iyi bir mühendislik projesi var. Ürün yok.**

Bu bir hakaret değil, bir teşhis. 27.000 satır Dart, 405 test, 5 haftada 115 commit, sıfır analyzer issue — bu üretim kalitesinde bir *kod tabanı*. Ama bir kullanıcının Terly2'yi bulup, indirip, kurup, para ödeyip, ikinci cihazına senkronize edip, çöktüğünde senin haberinin olması için gereken hiçbir şey henüz mevcut değil.

Somut olarak: **CI yok, imzalı build yok, dağıtım kanalı yok, otomatik güncelleme yok, hesap sistemi yok, ödeme sistemi yok, lisans dosyası yok, landing page yok, telemetri yok.** "Cloud Sync" diye anılan özellik aslında bir dosya export/import fonksiyonu — arkasında sunucu yok.

Bu tabloda risk şu: son 5 haftadaki hız tamamen *özellik* eklemeye gitti. Ürünleşme işi özellik işinden daha az eğlenceli ama v1.0 ile aranda duran şey o. Önümüzdeki 6 ayın ilk 2 ayında **tek satır yeni kullanıcı özelliği yazmamanı** öneriyorum.

| Boyut | Puan | Gerekçe |
| :--- | :---: | :--- |
| Çekirdek mühendislik | 9/10 | Katman ayrımı disiplinli, kripto mimarisi doğru, test yoğunluğu yüksek |
| Özellik kapsamı (çekirdek) | 8/10 | Terminal/SSH/SFTP/tünel/vault gerçekten çalışıyor |
| Diferansiyasyon | 2/10 | AI sıfır kod; Mosh & serial enum-only; agent forwarding yok |
| **Release hazırlığı** | **1/10** | CI, imzalama, dağıtım, güncelleme, crash görünürlüğü — hepsi yok |
| **Ticarileşme** | **0/10** | Hesap, abonelik, entitlement, sync backend — hiçbiri yok |
| Pazara gidiş | 0/10 | Site, marka, fiyat, beta listesi yok |

---

## 2. Ölçülen Durum (7 Ağustos)

| Metrik | Değer | 5 Ağu'ya göre |
| :--- | :--- | :--- |
| `lib/` Dart dosyası | 144 | +7 |
| Üretim kodu (generated hariç) | ~27.200 satır | — |
| Test dosyası / test | 80 / **405** | +6 / +66 |
| `dart analyze` | 0 issue | = |
| Commit | 115 (son 30 günde 114) | +16 |
| CI | **YOK** (`.github` dizini mevcut değil) | değişmedi |
| Sürüm | `1.0.0+1`, `publish_to: none` | hiç release yok |
| LICENSE / CHANGELOG | **YOK** | değişmedi |
| Açık branch | 11 | temizlenmemiş |

### 2.1. Önceki raporlardan kapanan maddeler ✅

- **ProxyJump artık gerçek.** `terminal_tabs_notifier.dart:152-280` içinde `jumpHostId` zinciri yürütülüyor, döngü koruması var. 5 Ağustos raporundaki "dürüstlük borcu" **kapandı** — bu en kritik düzeltmeydi.
- **Keyboard-interactive auth eklendi** (`ssh_session_manager.dart:172`). Tek promptlu `Password:` senaryosu çalışıyor.
- **Crash logging var** (`main.dart` → app support dizinine `crash.log`). Kodun kendi yorumu dürüst: "aggregate crash visibility için değil".
- **`~/.ssh/config` import** tamamlandı ve merge edildi.
- **6 Ağustos code review blocker'ları kapandı**: `known_hosts` restore artık `(hostname, port)` üzerinden lookup yapıyor (`e2ee_cloud_sync_service.dart:318-330`); Argon2id türetmesi `deriveMasterKeyInBackground` ile isolate'e taşınmış (satır 162, 219). Bu iki madde bu yol haritasında iş kalemi olarak yer almıyor.

### 2.2. Hâlâ spec'te var, kodda yok ❌

| Vaat | Kod durumu |
| :--- | :--- |
| AI asistanı (Natural language → shell, error explain) | `ollama` / `openai` / `anthropic` / `ai_` → **0 dosya** |
| Mosh (roaming UDP) | Yalnızca `protocol` string'inde bir değer — implementasyon yok |
| Serial port | Aynı şekilde enum-only |
| SSH agent forwarding | Yalnızca `~/.ssh/config` parser'ında `ForwardAgent` anahtarı tanınıyor (`ssh_config_resolver.dart:387`) — bağlantı katmanında forwarding yok |
| Team Vaults / RBAC / audit log | 0 |
| YubiKey / Secure Enclave | 0 |
| Session recording | 0 |
| Warp tarzı block mode | 0 |

> **PO notu:** Rakip analizi dokümanındaki karşılaştırma tablosunda Terly2 sütunu, *hedefi* mevcut yetenek gibi gösteriyor. Bu tablo yarın bir yatırımcıya veya beta kullanıcısına gitse yanıltıcı olur. Tabloyu "Bugün / v1.0 / Yol haritası" olarak üç kolona ayır.

### 2.3. Hijyen borcu

- `test/scratch/` — 3 adet repro testi hâlâ commitli (`sel_repro_test.dart`, `sel_repro2_test.dart`, `slash_repro_test.dart`). 5 Ağustos'ta işaretlendi, silinmedi.
- 10 branch açık; 7'si merge edilmiş görünüyor.
- Commitlenmemiş WIP: `workspaces_notifier.dart` + 3 generated dosya.
- `.claude/` untracked — `.gitignore`'a girmeli.

---

## 3. Ürünleşme Boşluk Analizi

Kod ile ürün arasındaki fark burada. Aşağıdakilerin hiçbiri "özellik" değil; hepsi para almanın ön koşulu.

### 3.1. Release mühendisliği — hiç yok

| Gereksinim | Durum | Neden zorunlu |
| :--- | :--- | :--- |
| CI (analyze + test) | Yok | 405 test var, hiçbiri otomatik koşmuyor. En ucuz kalite kazancı. |
| macOS imzalama + notarization | Yok | Sandbox kapalı → **Mac App Store imkânsız**. Developer ID + notarization tek yol. Notarize edilmemiş uygulamayı Gatekeeper açtırmaz. |
| Windows code signing | Yok | İmzasız `.exe` SmartScreen uyarısı verir → indirmelerin çoğu ölür. EV/OV sertifika gerekiyor (yıllık ~$200-400). |
| Linux paketleme | Yok | `.deb` + `.rpm` + AppImage veya Flatpak. |
| Otomatik güncelleme | Yok | Doğrudan dağıtımda güncelleme kanalı olmadan güvenlik yaması dağıtamazsın. Bir SSH istemcisi için bu kabul edilemez. |
| Crash/hata görünürlüğü | Yerel dosya | Kullanıcı sana `crash.log` göndermeyecek. Sentry benzeri bir kanal şart. |
| Sürüm/CHANGELOG disiplini | Yok | — |

### 3.2. Ticari altyapı — hiç yok

Freemium abonelik modeli seçtiğin an, uygulamanın dışında bir sistem inşa etmeyi de seçmiş oluyorsun:

1. **Hesap & kimlik** — kayıt, e-posta doğrulama, oturum, şifre sıfırlama.
2. **Zero-knowledge sync backend** — mevcut `e2ee_cloud_sync_service.dart` yalnızca yerel dosyaya export/import yapıyor. Gerçek sync için: şifreli blob depolama, cihaz kaydı, çakışma çözümü, versiyonlama.
3. **Faturalama** — masaüstünde Stripe. Mobilde **zorunlu olarak** Apple IAP ve Google Play Billing (dijital abonelik için mağaza kuralı; %30 → 2. yıl %15 komisyon). Üç kaynağı tek bir *entitlement* servisinde birleştirmen gerekecek.
4. **Feature gating** — istemci tarafında Free/Pro/Team sınırlarını uygulayan katman. Kodda `purchase` / `billing` / `paywall` / abonelik anlamında `entitlement` geçen tek satır yok (`secure_storage_service.dart`'taki "entitlement" macOS keychain izniyle ilgili, ticari katmanla alakasız).
5. **Destek kanalı** — zero-knowledge mimaride "şifremi unuttum" = "verin gitti". Bu, destek yükü ve churn kaynağıdır; onboarding'de recovery key akışı tasarlanmalı.

### 3.3. Hukuki & güven

- **LICENSE yok.** Proprietary diyorsun ama EULA metni yok.
- Gizlilik politikası, KVKK/GDPR aydınlatma metni, veri işleme kaydı — abonelik alacaksan zorunlu.
- **Bağımsız güvenlik denetimi.** "Zero-knowledge şifreleme" iddiasıyla para alan bir üründe, dış denetim raporu olmadan bu iddia pazarlama sloganıdır. Rakiplerin (Termius, 1Password vb.) yayınlanmış denetim raporu var. Bütçe kalemi olarak planla.

### 3.4. Tek bağımlılık riskleri

| Bağımlılık | Risk |
| :--- | :--- |
| `dart_ssh2` (Pure Dart SSH) | Kripto katmanının doğruluğu tamamen bu pakete bağlı. Bakımı durursa CVE'leri sen yamalamak zorundasın. |
| `xterm3` (maintained fork) | "Maintained fork" = bakım artık senin. |
| macOS sandbox kapalı | App Store yok + bir path bug'ı OS tarafından sınırlanmıyor. SFTP path-traversal kontrolleri savunma katmanı değil, **tek** savunma. |
| Solo geliştirici | Bus factor = 1. Abonelik satıyorsan bu bir müşteri riski. |

---

## 4. Stratejik Karar: Konumlandırma ve Fiyatlandırma

### 4.1. Kime satıyorsun?

Rakip analizindeki "herkesin en iyisini birleştir" konumlandırması bir satış mesajı değil, bir özellik listesi. Tek kişilik bir ekip için önerdiğim keskinleştirme:

> **"Telefonundaki ile masaüstündeki aynı terminal. Sunucularının parolaları bizim göremediğimiz şekilde şifreli."**
>
> Hedef persona: **birden fazla cihazdan sunucu yöneten sysadmin / DevOps / indie geliştirici.** Warp'ın mobili yok, Blink sadece Apple'da, Tabby'nin sync'i yok, Termius pahalı ve SFTP'yi ücretli duvarın arkasında tutuyor.

### 4.2. Önerilen paketleme

Termius'un en büyük şikâyeti: SFTP ve port forwarding gibi *temel* şeyleri paywall'a koyması. Bunu silah olarak kullan — **çekirdeği cömertçe ücretsiz bırak, senkronizasyon ve zekâyı ücretlendir.**

| | **Free** | **Pro** (~$8/ay, $79/yıl) | **Team** (~$15/kişi/ay) |
| :--- | :--- | :--- | :--- |
| Local shell, SSH, SFTP, tüneller | ✅ sınırsız | ✅ | ✅ |
| Host / identity vault | ✅ sınırsız | ✅ | ✅ |
| Snippets | ✅ | ✅ | ✅ |
| Cihaz sayısı | 1 | sınırsız | sınırsız |
| E2EE cihazlar arası sync | ❌ | ✅ | ✅ |
| AI asistanı | kendi API key'inle | dahil kota | dahil kota |
| Runbooks, layout templates, workspaces | temel | tam | tam |
| Team Vault, RBAC, audit log | ❌ | ❌ | ✅ |

**Neden bu sınır doğru:** ücretsiz katman tek başına Termius'un ücretli katmanından iyi → dağıtım ve ağızdan ağıza büyüme buradan gelir. Para, tek cihazda çözülemeyen problemden (sync) ve marjinal maliyeti olan şeyden (AI) alınır. İkisi de sunucu maliyeti doğurduğu için ücretlendirmesi kullanıcıya adil görünür.

---

## 5. 6 Aylık Yol Haritası

### Kapsam üzerine dürüst bir itiraz

"5 platform aynı anda" + "freemium abonelik" + "tek kişi" + "6 ay" kombinasyonu, tek bir kısıtı gevşetmeden tutturulabilir değil. Neden:

- 5 platform = 5 ayrı paketleme, imzalama, mağaza/dağıtım, güncelleme ve QA hattı.
- Mobil, ekstra olarak: App Store & Play review süreçleri, IAP entegrasyonu, **ve mobil vaadinin gerçek olması için Mosh/arka plan işi** (şu an sıfır).
- Abonelik altyapısı tek başına 6-8 haftalık bir backend projesi.

Bunları paralel yürütmeye çalışırsan hiçbiri v1.0 kalitesine ulaşmaz. **Önerim: 5 platformdan vazgeçme, ama aynı anda değil — 2 dalga halinde çıkar.** Aşağıdaki plan 6 ayın sonunda beş platformu da sahada bırakıyor; masaüstünü 4. ayda, mobili 6. ayda.

```
Ay 1        Ay 2         Ay 3         Ay 4          Ay 5        Ay 6
Ağu 7-Eyl 5 Eyl          Eki          Kas           Ara         Oca
──────────────────────────────────────────────────────────────────────
[Release    [Ticari      [AI MVP +    [DESKTOP      [Mobil      [MOBİL
 mühendis-   altyapı]     private      v1.0          beta +      v1.0
 liği]                    beta]        LAUNCH]       IAP]        LAUNCH]
                                                                + Team alfa
```

---

### 🔧 Ay 1 — Release Mühendisliği (7 Ağu – 5 Eyl)
**Hedef:** Üç masaüstü platformunda, imzalı, kurulabilir, kendini güncelleyen bir artifact CI'dan otomatik çıkıyor.
**Kural: Bu ay sıfır yeni kullanıcı özelliği.**

| # | İş | Çıktı |
| :-- | :--- | :--- |
| 1.1 | GitHub Actions: PR'da `dart analyze` + `flutter test` (mac/win/linux matrix) | Yeşil rozet |
| 1.2 | Release workflow: tag → 3 platform build → artifact | `v0.9.0-beta` |
| 1.3 | macOS Developer ID imzalama + notarization + stapling | `.dmg` |
| 1.4 | Windows code signing sertifikası alımı + imzalı installer | `.msi`/`.exe` |
| 1.5 | Linux `.deb` + `.rpm` + AppImage | 3 paket |
| 1.6 | Otomatik güncelleme kanalı (appcast + imza doğrulama) | Uygulama içi "güncelle" |
| 1.7 | Crash/hata raporlama SDK'sı + kullanıcı onayı (opt-in) | Panoda ilk crash |
| 1.8 | LICENSE + EULA + gizlilik politikası + CHANGELOG + SemVer | Repo kökünde |
| 1.9 | Hijyen: `test/scratch/` sil, branch temizliği, `.claude/` gitignore, WIP commit | Temiz `main` |
| 1.10 | Rakip analizi tablosunu "Bugün / v1.0 / Yol haritası" olarak dürüstleştir | Güncel doküman |

**Çıkış kriteri:** Sıfır bilgiye sahip bir kişi bir linke tıklayıp, uyarı görmeden kurabiliyor; uygulama içinden güncelleme alabiliyor; çöktüğünde senin panelinde görünüyor.

---

### 💳 Ay 2 — Ticari Altyapı (Eylül)
**Hedef:** Bir kullanıcı hesap açıp Pro'ya abone olabiliyor ve iki masaüstü cihaz arasında verisi senkronize oluyor.

| # | İş | Not |
| :-- | :--- | :--- |
| 2.1 | Hesap servisi: kayıt, e-posta doğrulama, oturum, cihaz kaydı | Sunucu **asla** plaintext görmez |
| 2.2 | Zero-knowledge sync backend: şifreli blob + versiyon + çakışma çözümü | Mevcut export/import kodunu buraya bağla |
| 2.3 | Recovery key akışı + "şifreni unutursan veri kurtarılamaz" onayı | Destek yükünü şimdi azalt |
| 2.4 | Stripe: abonelik, deneme süresi, fatura, iptal, vergi | Masaüstü kanalı |
| 2.5 | Entitlement servisi + istemci feature gating katmanı | Mobil IAP'ı da taşıyacak şekilde tasarla |
| 2.6 | Mevcut yerel yedek formatını (v2 envelope) sunucu tarafı format'a köprüle | `E2EECloudSyncService` bugün tek seferlik tam yedek üretiyor; sürekli sync için delta/versiyon modeli gerekiyor |
| 2.7 | Çok cihazlı çakışma senaryolarını test kapsamına al | Aynı host'u iki cihazda düzenleme, silme/güncelleme yarışı |

**Çıkış kriteri:** Test kartıyla uçtan uca satın alma; Mac'te eklenen host 30 saniye içinde Windows'ta; sunucudaki veriyi indirip okumaya çalıştığında ciphertext'ten başka bir şey göremiyorsun.

---

### 🤖 Ay 3 — Diferansiyatör + Private Beta (Ekim)
**Hedef:** Ürünün "neden bunu seçeyim" cevabı kodda var ve 50-100 gerçek kullanıcı elinde.

| # | İş |
| :-- | :--- |
| 3.1 | **AI asistanı MVP** — Settings'te API key (OpenAI/Anthropic/Ollama), terminalde `Cmd+I` → doğal dil → shell komutu (çalıştırmadan önce onay), "bu hatayı açıkla" |
| 3.2 | AI güvenlik sınırı: hangi verinin gönderildiği şeffaf, varsayılan opt-in, gizli/parola içeren satırların maskelenmesi |
| 3.3 | Onboarding akışı: ilk açılışta `~/.ssh/config` algıla → tek tıkla içe aktar (import kodu hazır, önüne akış koy) |
| 3.4 | Landing page + waitlist + fiyat sayfası + dokümantasyon sitesi |
| 3.5 | Private beta: 50-100 kullanıcı, geri bildirim kanalı, haftalık sürüm |
| 3.6 | Bağımsız güvenlik denetimi başlat (kripto + sync protokolü) |
| 3.7 | Ürün analitiği (gizlilik odaklı, opt-in): aktivasyon hunisi, retention |

**Çıkış kriteri:** `v1.0-rc`. Beta'da haftalık aktif kullanım ölçülüyor; ilk 20 ödeme yapan kullanıcı (beta indirimiyle).

---

### 🚀 Ay 4 — Masaüstü v1.0 Lansmanı (Kasım)
**Hedef:** Kamuya açık çıkış, ilk gerçek gelir.

| # | İş |
| :-- | :--- |
| 4.1 | Beta bulgularını kapat, `v1.0.0` etiketle |
| 4.2 | Güvenlik denetimi raporunu yayınla (bu, güven satın alan tek kanıt) |
| 4.3 | Lansman: Product Hunt, Hacker News, r/sysadmin, r/selfhosted, Lobsters |
| 4.4 | Karşılaştırma içeriği: "Terly vs Termius", "Terly vs Warp" — SEO'nun ilk ayağı |
| 4.5 | Destek altyapısı: dokümantasyon, SSS, e-posta/Discord |
| 4.6 | Paralel: mobil sertleştirme başlar (aşağıya bkz.) |

**Çıkış kriteri:** 3 masaüstü platformunda genel kullanıma açık v1.0; ilk aylık yinelenen gelir; crash-free oturum > %99.5.

---

### 📱 Ay 5 — Mobil Beta (Aralık)
**Hedef:** iOS ve Android'de mobil vaadi *gerçek* — sadece derlenmiş değil.

| # | İş | Not |
| :-- | :--- | :--- |
| 5.1 | Mobil arka plan davranışı: bağlantı kopma/yeniden kurma, oturum durumu koruma | iOS soketi arka planda kapatır — bugün yanıltıcı |
| 5.2 | **Mosh veya eşdeğer roaming kararı**: gerçekten uygula ya da UI'dan kaldır | Enum-only bırakmak 5 Ağustos'ta kapattığın hatanın aynısı |
| 5.3 | Apple IAP + Google Play Billing → entitlement servisine bağla | Dijital abonelikte mağaza kullanımı zorunlu |
| 5.4 | Mobil UX geçişi: klavye barı, jest, dokunmatik SFTP | |
| 5.5 | TestFlight + Play internal testing dağıtımı | Review sürecini erken tetikle — sürpriz red riskini öne çek |
| 5.6 | App Store review risk incelemesi (terminal/uzak kod yürütme kuralları) | Termius & Blink emsal var, ama kural yorumu değişebiliyor |

**Çıkış kriteri:** İki mağazada da beta dağıtımı onaylanmış; abonelik mobilde satın alınabiliyor ve masaüstünde geçerli.

---

### 🏁 Ay 6 — Mobil v1.0 + Team Alfa (Ocak 2027)
**Hedef:** Beş platform sahada; kurumsal gelir hattı açılıyor.

| # | İş |
| :-- | :--- |
| 6.1 | iOS + Android v1.0 mağaza lansmanı |
| 6.2 | "Tek abonelik, beş cihaz" pazarlama hikâyesi — asıl farkın bu, öne çıkar |
| 6.3 | **Team Vault alfa**: paylaşılan şifreli kasa, Admin/Operator/Read-only rolleri, audit log |
| 6.4 | 5-10 takımla ücretli pilot |
| 6.5 | 6 ay retrospektifi + Ay 7-12 planı (SSO/SAML, self-hosted sync, agent forwarding, donanım anahtarı) |

---

## 6. Takip Edilecek Metrikler

| Aşama | Metrik | Ay 6 hedefi (öneri) |
| :--- | :--- | :--- |
| Kalite | CI yeşil oranı, crash-free oturum | %100 / >%99.5 |
| Aktivasyon | Kurulumdan ilk başarılı SSH bağlantısına kadar geçen süre | < 3 dk, %60+ tamamlama |
| Retention | 4. hafta aktif kullanıcı oranı | > %25 |
| Dönüşüm | Free → Pro | > %3 |
| Gelir | Aylık yinelenen gelir (MRR) | ilk 100 ödeyen kullanıcı |
| Destek | İlk yanıt süresi | < 24 saat |

Bugün bu metriklerin **hiçbirini ölçemiyorsun** — telemetri yok. Ay 3'teki 3.7 maddesi bu yüzden opsiyonel değil.

---

## 7. Riskler ve Azaltım

| Risk | Etki | Azaltım |
| :--- | :--- | :--- |
| App Store, terminal/uzak kod yürütme gerekçesiyle reddeder | Mobil hattı kapanır | Ay 5'te değil, **Ay 4'te** boş bir kabuk build ile review sürecini test et |
| macOS sandbox kapalı → App Store yok | Dağıtım kanalı kaybı | Kabul et; doğrudan dağıtımı birinci sınıf yap (notarization + auto-update) |
| `dart_ssh2` bakımı durur / CVE çıkar | Ürünün kalbi | Upstream'i izle, fork planı hazırla, denetim kapsamına dahil et |
| Zero-knowledge iddiası denetimsiz | Güven ve hukuki risk | Ay 3'te denetim başlat, Ay 4'te raporu yayınla |
| Tek kişi bağımlılığı | İş sürekliliği | Kod escrow / dokümantasyon; ilk gelirle birlikte ikinci geliştirici |
| Backend işi tahminden uzun sürer | Tüm takvim kayar | Ay 2 backend'i mümkün olan en aptal haliyle yap (managed servis, hazır auth) — burada mühendislik yapma |
| Özellik ekleme cazibesi | Ay 1-2 sulanır | Bu iki ayda yeni özellik PR'ı açma kuralını yaz ve uygula |

---

## 8. Senin Vermen Gereken Kararlar

Bu yol haritasının kilitlenmesi için 5 karar gerekiyor:

1. **Marka ve alan adı** — "Terly" ismi kesin mi? Ticari marka araması yapıldı mı?
2. **Backend'i kim/nasıl?** — Kendin mi yazacaksın yoksa hazır servisler (managed auth + object storage + Stripe) mi? Öneri: kesinlikle hazır servis; sync backend'i "şifreli blob koy/al" seviyesinde tut.
3. **Denetim bütçesi** — Bağımsız kripto denetimi için ayrılabilecek bütçe var mı? Yoksa "zero-knowledge" iddiasının dilini yumuşatmak gerekir.
4. **Mosh: yap ya da kaldır.** Ay 5'te karar verilecek ama bugünden zihnen kapat — üçüncü seçenek yok.
5. **Fiyat noktası** — Yukarıdaki $8/ay bir başlangıç önerisi; beta kullanıcılarıyla test edilmeli.

---

## 9. Sonuç

5 haftada 27 bin satırlık, 405 testli, temiz mimarili bir SSH iş istasyonu çıkarmışsın. Mühendislik tarafında yapılacak iş listesi kısa; asıl mesafe ürün tarafında.

Tek cümlelik tavsiye: **önümüzdeki 8 hafta boyunca hiçbir yeni özellik yazma; sadece elindekini insanların kurabileceği, güncelleyebileceği ve parasını ödeyebileceği bir şeye dönüştür.**

Ondan sonra AI'ı ekle, sonra mobili çıkar, sonra takımlara sat.
