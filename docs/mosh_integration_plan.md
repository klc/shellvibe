# Mosh Entegrasyonu — Uygulama Planı

> Tarih: 2026-08-07 · Durum: onay bekliyor · İlgili: `docs/product_roadmap_2026-08-07.md` §5.2

## Context

`protocol` sütunu ve UI enum'u Mosh'u vaat ediyor ama arkasında hiçbir şey yok
(`docs/product_roadmap_2026-08-07.md:58` — *"Yalnızca `protocol` string'inde bir değer"*).
`host_form_dialog.dart:56-62` bunu bilerek gizliyor: kayıtlı `'mosh'` protokolü
sessizce SSH'a düşürülüyor. Roadmap madde 5.2 bunu bir karar noktası olarak
işaretlemiş: **"gerçekten uygula ya da UI'dan kaldır"**.

Bu plan "gerçekten uygula" tarafını seçiyor. Hedef, mobilde ürünün asıl vaadi
olan **roaming**: Wi-Fi → hücresel geçişinde, tünel/asansör kesintisinde ve
ekran kapanıp açıldığında oturumun ölmemesi. Bugün SSH'ta bu senaryoların
hepsi keep-alive hatasıyla `connectionLost` üretiyor.

C mosh binary'sini bundle etmek iOS'ta pratik değil, bu yüzden saf Dart
transport kullanılıyor.

### Onaylanan kararlar

| Karar | Seçim |
|---|---|
| Protokol motoru | `dart_mosh` pub paketi, exact pin |
| Platform kapsamı | Tüm platformlar (pure Dart, ek maliyet yok) |
| Bootstrap SSH'ı | Açık tut — SFTP ve tüneller mosh sekmesinde de çalışsın |
| Local echo prediction | Faz 2'ye ertelendi |

### Kapsam dışı (bilinçli)

- **Prediction/local echo** — Faz 2. `dart_mosh` sadece `echoAcks` stream'i
  veriyor; predictor motoru (mosh'un `PredictionEngine`'i, ~700 satır C++) yok.
- **Mosh + ProxyJump** — UDP bir SSH kanalından geçmez. `jumpHostId` dolu olan
  host'ta mosh **engellenecek** (sessizce bozuk çalışmasındansa net hata).
- **Süreç öldükten sonra reattach** — mosh protokolü buna izin vermiyor
  (OCB sayaç durumu istemcide, sunucunun replay filtresi eski sequence'ı
  reddeder). App OS tarafından öldürülürse oturum gider. Karşı önlem: tmux.
- **Serial protokolü** — dokunulmuyor.

---

## Faz 0 — Bağımlılık ve doğrulama zemini

**`pubspec.yaml`**: `dart_mosh: 0.0.4` (caret **yok** — 0.0.x'te patch bump
breaking olabilir). Tek transitif bağımlılığı `pointycastle`, zaten
`pubspec.lock`'ta var.

**Doğrulama harness'ı** (`tool/` altına, kaynak ağacına değil): Docker'da
`mosh-server` çalıştıran bir compose dosyası + elle koşulan bir smoke script.
`dart_mosh` 0.0.x ve 3 star — gerçek bir sunucuya karşı wire uyumunu Faz 1'in
ilk işi olarak kanıtlamalıyız. Bu adım başarısız olursa paketi vendor edip
düzeltmek Faz 1'i ~1 hafta uzatır; plan bu riski taşıyor.

---

## Faz 1 — Transport çekirdeği

### `lib/core/network/mosh_session_manager.dart` (yeni)

`SSHSessionManager` ile aynı sözleşmeyi taşır: bağlan, durum stream'i yayınla,
kapat. Sahiplendiği şeyler:

**Bootstrap** — zaten kurulmuş `SSHClient` üzerinden:

```dart
final result = await client.runWithResult(
  MoshSshBootstrap(term: 'xterm-256color', colors: 256).command(),
);
```

- `result.exitCode != 0` → `mosh-server` yok/PATH dışı. Çıktıyı olduğu gibi
  kullanıcıya göster, "SSH ile bağlan" fallback'i öner. (127 en sık vaka.)
- `MoshServerConfig.parse(output, host: ...)` → port + `MoshKey`.
- **`host:` parametresine DNS adı değil, SSH soketinin çözdüğü IP verilecek.**
  Round-robin DNS'te ayrı bir çözümleme mosh'u başka makineye yollar;
  `mosh-server -s` SSH_CONNECTION'daki IP'ye bind ettiği için hedef zaten
  SSH'ın konuştuğu makinedir. `MoshSession.connect(address:)` bunu doğrudan
  kabul ediyor.

**UDP oturumu** — `MoshSession.connect(server:, cipher: MoshPacketCipher.aesOcb(cfg.key), columns:, rows:, address:)`.

**Sağlık takibi** — mosh'ta keep-alive/ping yok; heartbeat aralığı 3 sn.
Manager `stdout`/`errors` üzerinden son duyum zamanını tutar ve bir
`Stream<MoshLinkState>` yayınlar: `live` / `stale(Duration)` / `serverShutdown`.
**Kritik davranış farkı:** `stale` oturumu öldürmez — mosh'un tüm olayı budur.
SSH tarafındaki `_handleClientChange` → `connectionLost` yolu mosh'ta
kullanılmaz; sadece `serverShutdown` ve `session.done` sekmeyi kapatır.

**Rehome** — `rehome({localAddress, localPort})` çağrısını sarar, eşzamanlı
çağrıları teke indirir (paket içinde `_rehoming` guard'ı var ama biz de debounce
edeceğiz; ağ değişimi olayları salkım halinde gelir).

### `lib/core/network/terminal_mosh_bridge.dart` (yeni)

`TerminalSSHBridge`'in (`lib/core/network/terminal_ssh_bridge.dart`) birebir
aynası, tek fark alt taşıyıcı:

- `terminal.onOutput` → `session.send(utf8.encode(data))`
- `session.stdout` → `terminal.write(...)` (UTF-8 decode, `allowMalformed: true`)
- `terminal.onResize` → `session.resize(width, height)`
- `session.done` → `onClosed?.call()`
- `dispose({closeSession})` aynı imza

`TerminalOutputChain` (`lib/features/terminal/domain/services/terminal_output_chain.dart`)
`onOutput` slotuna yapılan atamayı kendiliğinden adopte ediyor
(`_adopt()`, satır 116) — broadcast ve mobil extra-keys bar için **hiçbir
değişiklik gerekmiyor.**

---

## Faz 2 — Sekme entegrasyonu ve roaming

### `terminal_tab_session.dart`

- `MoshSessionManager? moshSessionManager` ve `TerminalMoshBridge? moshBridge`
  alanları.
- `resizeTerminal()` ve `dispose()` bunları da kapsayacak (mevcut
  `sshBridge`/`ptyBridge` satırlarının yanına birer satır).
- `sshSessionManager` **mosh sekmesinde de dolu kalır** → SFTP
  (`sftp_dual_pane_screen.dart`) ve tüneller (`tunnels_screen.dart`)
  değişmeden çalışır.

### `terminal_tabs_notifier.dart`

`_connectSshTab` içinde SSH kurulduktan sonra bir dallanma:
`host.protocol == 'mosh'` ise `openShell()` yerine mosh bootstrap yolu.
SSH bağlanma, host key doğrulama ve identity çözümleme kodu aynen paylaşılır —
mosh yalnızca kabuğun *nasıl* açıldığını değiştirir.

Eklenecekler:
- `_connectMoshTab(tab, host, identity)` — bootstrap + `MoshSession` +
  `TerminalMoshBridge` + ilk resize (SSH tarafındaki 219. satırdaki ilk-layout
  resize düzeltmesi burada da gerekli).
- Mosh bootstrap başarısız olursa: SSH client zaten canlı, `openShell()` ile
  düz SSH'a düş ve terminale tek satır uyarı yaz. Kullanıcı bağlantısız kalmaz.
- `reconnectTab` mosh sekmesinde yeni bir mosh oturumu açar (reattach yok).

### Roaming tetikleyicileri

İkisi de `MoshSessionManager.rehome()` çağırır:

1. **Ağ değişimi** — yeni bağımlılık `connectivity_plus`.
   `onConnectivityChanged` → tüm canlı mosh oturumlarında debounce'lu rehome.
2. **App resume** — `lib/app/app.dart:72` `_onLifecycleChange` zaten var.
   `AppLifecycleState.resumed` dalında (mevcut auto-lock mantığına dokunmadan)
   rehome tetiklenir. iOS suspend'de UDP soketi ölür; resume'da rebind şart.

Her ikisi de `TerminalTabsNotifier` üzerinden yürür — sekme listesinin sahibi o.

---

## Faz 3 — UI ve kalıcılık

### Host formu — `lib/features/hosts/presentation/dialogs/host_form_dialog.dart`

- 56-62. satırlardaki "Mosh henüz yok" düşürmesi kalkar, dropdown'a Mosh gelir.
- `jumpHostId` seçiliyken Mosh seçilemez (ve tersi) — inline açıklama:
  *"Mosh, jump host üzerinden çalışmaz (UDP tünellenemez)."*
- Mosh seçiliyken görünen alanlar: sunucu binary yolu (varsayılan
  `mosh-server`), UDP port aralığı (varsayılan `60000:61000`).

### Şema — `lib/shared/database/tables.dart` + `app_database.dart`

`Hosts` tablosuna iki nullable sütun: `moshServerPath`, `moshPortRange`.
`schemaVersion` 4 → 5, `onUpgrade`'e `from < 5` dalında iki `m.addColumn`.
`HostModel` (`host_model.dart`) ve `hosts_repository.dart` map'lemeleri
buna göre genişler. Mevcut `protocol` sütununa dokunulmaz.

### Terminal sekmesi göstergesi

Mosh sekmesinde link durumu görünür: `live` sessiz, `stale` olduğunda
*"[mosh] son duyum 12s önce"* rozeti (mosh/Blink davranışı). Kullanıcının
"koptu mu, yavaş mı" ayrımını yapabilmesi bu protokolde SSH'takinden daha
önemli, çünkü stale bir oturum ölü değil.

### Dokümantasyon

`docs/tech_spec.md:288` ve `docs/features_and_competitor_analysis.md:62`
Mosh'u "planlanan" olmaktan çıkarıp gerçek kapsamla (prediction yok,
ProxyJump yok, reattach yok) günceller.

---

## Faz 4 — Prediction (ayrı iş, bu planın dışında)

`MoshSession.echoAcks` altyapısı hazır. Predictor motoru ayrıca planlanacak.

---

## Dokunulacak dosyalar

**Yeni**
- `lib/core/network/mosh_session_manager.dart`
- `lib/core/network/terminal_mosh_bridge.dart`
- `test/unit/network/mosh_session_manager_test.dart`
- `test/unit/network/terminal_mosh_bridge_test.dart`

**Değişecek**
- `pubspec.yaml` — `dart_mosh: 0.0.4`, `connectivity_plus`
- `lib/features/terminal/domain/models/terminal_tab_session.dart`
- `lib/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart`
- `lib/app/app.dart` — resume → rehome
- `lib/features/hosts/presentation/dialogs/host_form_dialog.dart`
- `lib/shared/database/tables.dart`, `lib/shared/database/app_database.dart`
- `lib/features/hosts/domain/models/host_model.dart`,
  `lib/features/hosts/data/repositories/hosts_repository.dart`
- `docs/tech_spec.md`, `docs/features_and_competitor_analysis.md`

---

## Doğrulama

**Birim** (mevcut `test/unit/network/` desenini izler —
`terminal_ssh_bridge_test.dart` sahte session ile kuruluyor, aynısı mosh için):
- `MoshServerConfig.parse` başarısızlığı ve `exitCode != 0` net hata üretiyor mu
- Bridge input/output/resize/dispose yolları
- `stale` durumu oturumu **kapatmıyor**; yalnızca `serverShutdown` kapatıyor

**Entegrasyon (gerçek sunucu, elle)** — Faz 0'daki Docker `mosh-server`:
1. Bağlan, `vim` aç, yaz, boyutlandır → C mosh ile aynı davranış
2. Wi-Fi kapat/aç → oturum sağ kalıyor, birkaç saniyede kendine geliyor
3. Uygulamayı arka plana al, 60 sn bekle, geri dön → rehome sonrası devam
4. `mosh-server` olmayan bir hosta bağlan → net hata + SSH fallback
5. Mosh sekmesinde SFTP ve tünel aç → hâlâ çalışıyor (SSH açık tutma kararı)
6. Jump host'lu bir hostta Mosh seçmeyi dene → UI engelliyor

**Cihaz**: iOS ve Android'de gerçek Wi-Fi ↔ hücresel geçişi. Simülatör bu yolu
kapsamıyor; roaming'in tek gerçek testi budur.

**Her zaman**: `dart analyze` sıfır uyarı, `flutter test` yeşil (AGENTS.md §3).

---

## Referanslar

- Mosh protokol/SSP: <https://mosh.org/mosh-paper.pdf>
- `mosh-server(1)`: bind 60000-61000, `MOSH_SERVER_NETWORK_TMOUT`
- `dart_mosh` 0.0.4 (Apache-2.0): <https://pub.dev/packages/dart_mosh>
- Alternatif motor (kullanılmadı): `unixshells/mosh-dart` (MIT, pub.dev'de yok)
