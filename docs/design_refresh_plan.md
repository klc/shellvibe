# Terly2 Tasarım Yenileme Planı

> Durum: MVP tasarım yenilemesi uygulandı — 1 Ağustos 2026
> Hedef: MVP sonrasında Terly2'yi sade, güven veren ve kendine ait bir marka dili olan profesyonel bir terminal workstation'a dönüştürmek.

## Uygulama özeti

Bu planın MVP sonrası ana tasarım dilini oluşturan bölümü kod tabanına uygulanmıştır:

- Graphite + jade Quiet Ops renkleri `ThemeExtension` tabanlı ortak token sistemine taşındı.
- Material ve Shadcn tema yüzeyleri aynı Terly renk kontratına bağlandı; terminal font tercihi uygulama tipografisinden ayrıldı.
- Ortak sayfa başlığı, arama, yüzey, durum rozeti ve boş/hata durumu bileşenleri oluşturuldu.
- Masaüstüne daraltılabilir dock, sade global header, Activity Center ve `Cmd/Ctrl+K` command palette eklendi.
- Telefon navigasyonu Connect, Sessions, Files ve Tools olmak üzere dört köke indirildi; ikincil araçlar Tools sheet altında toplandı.
- Hosts, Terminal, SFTP, Vault, Tunnels, Snippets/Runbooks ve Settings ana yüzeyleri Quiet Ops diline geçirildi.
- Navigasyon; 375, 768, 1024 ve 1440 px genişliklerde overflow regresyon testleriyle güvenceye alındı.
- Koyu/açık tema tokenları ve UI/terminal font ayrımı test edildi; tam `dart analyze` ve `flutter test` doğrulaması tamamlandı.

Final logo/wordmark çalışması ve ürün verisiyle hazırlanacak kalıcı golden ekran seti, marka onayı gerektiren ayrı bir görsel teslim olarak tutulmaktadır. Geçici terminal sembolü nihai logo kabul edilmemelidir.

## 1. Tasarım hedefi

Terly2, Termius'un görsel kopyası olmamalı. Referans alınacak taraflar bilgi yoğunluğunu sakin sunması, bağlantıya hızlı erişim, oturum merkezli çalışma ve mobil/masaüstü için ayrı navigasyon kararlarıdır. Terly2'nin farkı; terminal, dosya transferi, tüneller ve otomasyonu tek bir "operasyon masası" hissinde birleştirmesi olmalıdır.

Geçici tasarım yönü adı: **Terly Quiet Ops**.

Ana his:

- Sade fakat boş değil
- Teknik fakat soğuk değil
- Yoğun fakat gürültülü değil
- Koyu tema öncelikli fakat gerçek bir açık tema desteği olan
- Masaüstünde klavye odaklı, mobilde dokunma odaklı

## 2. Mevcut arayüzdeki temel sorunlar

Kod tabanındaki mevcut durum, tek tek ekranların kötü olmasından çok ortak bir tasarım sisteminin tamamlanmamış olduğunu gösteriyor:

- Material ve Shadcn bileşenleri yan yana ve farklı görsel dillerde kullanılıyor.
- Mevcut Shadcn araştırma dokümanı paket seçimi için yararlı, ancak entegrasyon zaten yapılmış durumda. Yenileme işi yeni bir UI paketi aramak yerine mevcut bileşenleri tek Terly kontratı altında toplamalı.
- Material `Icons.*` kullanımı Lucide ikonlardan çok daha fazla; ikon kalınlığı ve karakteri ekranlar arasında değişiyor.
- Uygulama içinde çok sayıda doğrudan `Colors.*` ve sabit hex renk bulunuyor. Durum, vurgu ve marka renkleri birbirine karışıyor.
- Her ekran kendi `AppBar`, kart, boş durum ve aksiyon düzenini kuruyor.
- Host gibi liste tabanlı yüzeylerde her satırın ayrı kart olması görsel kalabalık ve gereksiz dikey alan oluşturuyor.
- 7 ana bölüm mobil alt navigasyona aynı anda konuyor; etiketler ve dokunma alanları daralıyor.
- Global üst çubukta logo, workspace, SSH sayısı, tünel sayısı ve kasa durumu aynı ağırlıkta yarışıyor.
- Terminal font ayarı uygulamanın genel `fontFamily` alanını da etkiliyor. UI tipografisi ve monospace terminal tipografisi ayrı kontratlar olmalı.
- Mevcut tek ekran görüntüsü dosyası boş. Uygulama sonrası görsel regresyon için güvenilir bir referans seti bulunmuyor.

## 3. Terly marka çizgisi

### 3.1. Renk sistemi

Varsayılan tema "graphite + jade signal" olmalı. Terminal renk şemaları ayrı kalır; uygulama kabuğu terminal paleti değiştiğinde kimliğini kaybetmez.

| Token | Koyu tema | Açık tema | Kullanım |
|---|---:|---:|---|
| Canvas | `#0B0E12` | `#F5F7F9` | Ana zemin |
| Surface | `#11161C` | `#FFFFFF` | Panel ve sidebar |
| Surface raised | `#171D25` | `#EEF1F4` | Popover, dialog, aktif alan |
| Border | `#27303A` | `#D8DEE5` | 1 px ayırıcı |
| Text primary | `#F4F7FA` | `#171B21` | Ana metin |
| Text muted | `#94A0AE` | `#667085` | İkincil metin |
| Brand | `#5EEAD4` | `#0F766E` | Seçim, odak, ana aksiyon |
| Info | `#60A5FA` | `#2563EB` | Bilgi |
| Success | `#4ADE80` | `#15803D` | Bağlı/çalışıyor |
| Warning | `#FBBF24` | `#B45309` | Dikkat |
| Danger | `#FB7185` | `#BE123C` | Yıkıcı aksiyon/hata |

Kurallar:

- Marka rengi her ikona verilmez; sadece seçim, odak ve birincil aksiyonda kullanılır.
- Bağlantı durumları renk + ikon + metin ile anlatılır; renk tek başına anlam taşımaz.
- Kart gölgesi yerine yüzey tonu ve 1 px sınır kullanılır.
- OLED, Nord ve Catppuccin uygulama kabuğunu değil, tercihen terminal profilini özelleştirir. Uygulama için tek güçlü Terly koyu tema ve bir açık tema korunur.

### 3.2. Tipografi

- UI: Inter veya platformda aynı metrikleri veren paketlenmiş bir sans ailesi.
- Terminal: JetBrains Mono / Fira Code / kullanıcının seçtiği monospace font.
- UI ve terminal font ayarları ayrı saklanır.
- Sayfa başlığı 20/600, bölüm başlığı 14/600, gövde 13–14/400, meta bilgi 12/400.
- Tamamı büyük harf sadece kısa teknik rozetlerde kullanılır.

### 3.3. Şekil, ikon ve hareket

- Ana radius: 6 px; yükseltilmiş panel/dialog: 8 px; sheet: en fazla 12 px.
- Tek ikon ailesi: Lucide. Platforma özgü zorunlu semboller hariç Material ikonlar kaldırılır.
- Standart ikon boyutları: 16, 18 ve 20 px.
- Mikro geçişler 120–200 ms; layout değiştiren gösterişli animasyon kullanılmaz.
- `reduce motion` tercihi ve klavye focus halkası ilk sınıf gereksinimdir.

## 4. Yeni ürün kabuğu

### 4.1. Masaüstü

Masaüstü kabuğu üç katmandan oluşur:

1. **Global dock (56–64 px):** Connect, Sessions, Files, Automate ve Settings. Sadece ikon + tooltip; aktif durumda ince jade gösterge.
2. **Bağlamsal sidebar (220–260 px):** Seçili bölümün grup, host, kasa veya snippet listesi. Gerektiğinde kapanabilir.
3. **Workspace canvas:** Sayfa başlığı, bağlamsal toolbar ve asıl içerik.

Global üst çubuk sadeleştirilir:

- Sol: Terly sembolü ve workspace seçici
- Orta: aktif oturum/sekmeler
- Sağ: global arama/command palette, transfer aktivitesi ve profil/kasa durumu
- SSH ve tünel sayıları ayrı rozetler olarak sürekli gösterilmez; Activity Center içinde özetlenir.

### 4.2. Mobil ve tablet

- Telefon alt navigasyonu en fazla 4 kök: **Connect, Sessions, Files, Tools**.
- Vault, Tunnels, Snippets/Runbooks ve Settings, Tools içinde net gruplar halinde sunulur.
- Tablet 768 px ve üzerinde compact dock + bağlamsal sidebar kullanır.
- Masaüstü dialogları mobilde bottom sheet veya tam ekran task flow olur.
- Dokunma hedefi en az 44×44 px, terminal ekstra tuşleri en az 40 px yükseklik olmalıdır.

### 4.3. Command palette

`Cmd/Ctrl+K` Terly'nin ana hız katmanı olmalı:

- Host bul ve bağlan
- Açık oturuma geç
- SFTP oturumu aç
- Tünel başlat/durdur
- Snippet veya runbook çalıştır
- Ayar veya komut ara

Bu yüzey, navigasyonu saklamak için değil power-user akışını hızlandırmak için kullanılır.

## 5. Ekran bazlı dönüşüm

### Hosts / Connect

- Kart-per-host yapısı yerine yoğun liste veya tablo.
- Sol sidebar'da All Hosts, Favorites, Recent ve Groups.
- Satır: durum noktası, host adı, `user@hostname`, etiketler ve son bağlantı.
- Birincil Connect aksiyonu seçili/hover satırda belirginleşir; Edit/Delete overflow menüsüne taşınır.
- Boş durumda yalnızca metin değil "Add host" ve "Import SSH config" aksiyonları sunulur.

### Terminal / Sessions

- Terminal alanı edge-to-edge ve en baskın yüzey olur.
- 36–40 px oturum tabları; bağlantı durumu, ortam etiketi ve kapanış aksiyonu burada görünür.
- Split, reconnect, search ve broadcast gibi aksiyonlar tek sessiz toolbar'da toplanır.
- Production host için ince danger şeridi/etiketi kullanılır; tüm terminal kırmızıya boyanmaz.
- UI tema paleti terminal ANSI paletinden bağımsız kalır.

### SFTP / Files

- SFTP bağlantıları terminal gibi oturum tablarına sahip olur.
- Masaüstünde resizable iki panel, mobilde tab/switch ile tek aktif panel.
- Dosyalar kart değil kolonlu yoğun satırlarda gösterilir: Name, Size, Modified, Permissions.
- Transfer kuyruğu sağ üstte kalıcı Activity Center'a bağlanır.
- Breadcrumb gerçek segmentlerden oluşur; tek bir path kutusu gibi davranmaz.

### Vault

- Identity listesi host listesinin aynı satır sistemini kullanır.
- Kilitli/kilit açık durumu sakin ama net bir global güvenlik göstergesiyle anlatılır.
- Secret değerler varsayılan olarak gizlidir; reveal/copy aksiyonları loglanabilir ve zamanlı geri bildirim verir.

### Tunnels

- Kartlar yerine kompakt durum tablosu.
- Running, stopped, error durumları ortak status-chip kontratını kullanır.
- Ana aksiyon toggle gibi görünse bile start/stop süreci pending ve error durumlarını ayrı gösterir.

### Snippets & Runbooks

- Tek "Automation Library" yüzeyi altında Snippets ve Runbooks segmented navigation ile birleştirilir.
- Sol liste + sağ detay/editör masaüstü düzeni; mobilde liste -> detay akışı.
- Tag, dil, son kullanım ve favori bilgileri aynı metadata sistemini kullanır.

### Settings

- Uzun tek kolon yerine sol kategori navigasyonu ve maksimum 680–720 px içerik genişliği.
- App Appearance ile Terminal Appearance kesin olarak ayrılır.
- Ayarlar, başlık + kısa açıklama + kontrol düzenini tutarlı kullanır.

## 6. Uygulama fazları

### Faz 0 — Görsel kontrat ve prototip (1–2 gün)

- Quiet Ops yönünü 3 referans ekranla doğrula: Hosts, Terminal, SFTP.
- Koyu ve açık tema renklerini kontrast testinden geçir.
- Desktop 1440 px, tablet 1024/768 px ve telefon 375 px wireframe hazırla.
- Logo/wordmark ayrı bir branding işi olarak ele al; geçici `>_` kutusunu final marka sayma.

Teslim: Onaylı görsel yön, token tablosu ve 3 ekran prototipi.

### Faz 1 — Design system foundation (2–3 gün)

- `TerlyTokens` / `ThemeExtension` ile renk, spacing, radius, typography, motion ve elevation kontratlarını kur.
- Shadcn ve Material theme'lerini aynı token kaynağından üret.
- UI fontu ile terminal fontunu ayır.
- `TerlyButton`, `TerlyIconButton`, `TerlyPageHeader`, `TerlyEmptyState`, `TerlyStatusChip`, `TerlyListRow`, `TerlySearchField` bileşenlerini oluştur.
- Lucide ikon envanterini sabitle.

Teslim: Widget catalog/golden test yüzeyi ve ortak theme kontratı.

### Faz 2 — App shell ve navigasyon (2–3 gün)

- Desktop dock + contextual sidebar + workspace canvas yapısı.
- Telefon için 4 kök sekme, tablet için adaptive shell.
- Sade top bar, Activity Center ve command palette.
- Klavye kısayolları ve focus traversal.

Teslim: Tüm mevcut route'lar yeni shell içinde davranış kaybı olmadan açılır.

### Faz 3 — Ana deneyim (4–6 gün)

- Hosts/Connect
- Terminal/Sessions
- SFTP/Files
- Host oluşturma ve bağlanma akışları
- Terminal boş, connecting, connected, reconnecting ve error durumları

Bu faz sonunda uygulama ilk bakışta yeni ürün gibi görünmelidir.

### Faz 4 — İkincil yüzeyler (4–5 gün)

- Vault
- Tunnels
- Automation Library
- Settings
- Dialog, sheet, context menu, toast ve validation standardizasyonu

### Faz 5 — Mobil optimizasyon (3–4 gün)

- 375/430 px telefon, 768/1024 px tablet kontrolü.
- Extra keys bar, gesture ve soft keyboard senaryoları.
- Bottom sheet/tam ekran form dönüşümleri.
- TalkBack ve VoiceOver semantics kontrolü.

### Faz 6 — Görsel QA ve sertleştirme (2–3 gün)

- Koyu/açık tema, 375/768/1024/1440 px golden ekran seti.
- Hover, focus, pressed, disabled, loading ve error durumları.
- WCAG AA kontrast, reduce-motion ve klavye-only kullanım.
- `dart analyze` ve tam `flutter test`.

Tahmini toplam: onay ve revizyon döngülerine bağlı olarak **3–4 hafta**.

## 7. Kabul kriterleri

- Terminal palet tanımları dışında ekran kodunda doğrudan marka/surface rengi bulunmaz.
- Platforma özgü istisnalar dışında tek ikon ailesi kullanılır.
- Liste satırları varsayılan olarak ayrı kartlara dönüşmez.
- Mobil alt navigasyon 4 kökü geçmez.
- Her ana ekran loading, empty, error ve populated durumlarına sahiptir.
- Mouse olmadan tüm ana akışlar kullanılabilir.
- 375, 768, 1024 ve 1440 px genişliklerde overflow oluşmaz.
- Koyu ve açık temada metin kontrastı en az WCAG AA'dır.
- Mevcut SSH, terminal, SFTP, vault ve tünel davranışları tasarım refactor'ı nedeniyle değişmez.
- Ana ekranlar için onaylı golden/screenshot referansı bulunur.

## 8. Uygulama sırası için karar

Tüm ekranları aynı anda yeniden yazmak yerine önce **Faz 0 + Faz 1**, ardından **App Shell + Hosts + Terminal** dikey dilimi uygulanmalıdır. Bu dilim marka yönünü ve ortak bileşenlerin gerçek kullanımını kanıtlar. Onaydan sonra SFTP ve diğer yüzeylere yayılır.

Bu sıralama, tasarım dili onaylanmadan onlarca ekranı mekanik olarak dönüştürme riskini azaltır.

## 9. Referanslardan alınan prensipler

- Termius'un güncel mobil navigasyonu telefon, tablet ve foldable için farklı kabuklar kullanıyor ve telefonda kök sekme sayısını sınırlı tutuyor: <https://www.termius.com/blog/termius-for-android-a-final-milestone-in-termius-redesign>
- Termius masaüstü yenilemesi, genişleyen özellik setinin sidebar'da gürültü oluşturmasını yatay oturumlar ve command palette ile ele almış: <https://termius.com/blog/termius-x>
- Workspace yaklaşımı oturumları tek tek sekmeler olarak değil, kullanıcının niyetine göre Focus/Split düzenlerinde grupluyor: <https://termius.com/blog/workspaces-focus-without-losing-context>

Bu prensipler bilgi mimarisi için referanstır; renk, ikon, spacing, marka sembolü ve Terly'nin dock + contextual sidebar yapısı özgün kalır.
