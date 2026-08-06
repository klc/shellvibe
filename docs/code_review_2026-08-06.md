# Terly2 Production Code Review — 2026-08-06

Kapsam: crypto/network/vault/sync core + yeni SSH config import özelliği (uncommitted).
Durum: `flutter analyze` temiz, 401 test geçiyor.

## Verdict

Kod kalitesi genel olarak yüksek — crypto mimarisi (DEK/KEK, Argon2id, AES-GCM), host key
TOFU akışı, tunnel cleanup, SFTP temp-file commit pattern hepsi doğru düşünülmüş.
Production öncesi **3 gerçek bug** + birkaç eksik var.

## 🔴 Blocker

### 1. ProxyJump hiç implement edilmemiş, ama import "çalışıyor" diyor
`jumpHostId` DB'ye yazılıyor fakat connect akışında hiçbir yerde okunmuyor —
`lib/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart:169`
`SSHConnectConfig` kurarken `host.jumpHostId`'yi tamamen yok sayıyor. Buna rağmen
`lib/features/hosts/domain/services/ssh_config_resolver.dart:344` kullanıcıya
*"Terly routes through the jump host at connect time"* mesajı gösteriyor. Bastion
arkasındaki her import edilen host direkt bağlanmaya çalışıp timeout alacak.

**Fix:** Ya connect-time jump routing ekle (dartssh2 `forwardLocal` ile chain), ya da
import mesajını "jump host kaydedildi ama henüz routing yok" olarak düzelt ve
`createMissingJumpHosts` default'unu gözden geçir.

### 2. Cross-device backup restore, bilinen host çakışmasında komple patlıyor
`lib/shared/database/tables.dart:74` — `KnownHosts` üzerinde `unique(hostname, port)` var.
`lib/core/sync/e2ee_cloud_sync_service.dart:320` restore'da `insertOnConflictUpdate`
kullanıyor — drift'te bu yalnızca **primary key** (id) üzerinden upsert yapar. Hedef cihaz
aynı `hostname:port`'u farklı bir `id` ile zaten tanıyorsa UNIQUE constraint exception
fırlar ve transaction olduğu için **tüm restore** geri alınır. Senaryo: iki cihaz da aynı
sunucuya bağlanmış, birinden backup restore ediliyor → restore her seferinde başarısız.

**Fix:** known_hosts için id yerine `(hostname, port)` üzerinden lookup + update/insert
(veya `DoUpdate(target: [hostname, port])`).

### 3. Import dialog, kilitli vault'ta kapalı görünen anahtarı yine de import etmeye çalışıyor
`lib/features/hosts/presentation/dialogs/ssh_config_import_dialog.dart:256` switch değeri
`_importKeys && !vaultLocked` gösteriyor (OFF görünür), ama satır 73'te servise
`importIdentityFiles: _importKeys` (true) gidiyor. Vault kilitliyken kullanıcı "keys
kapalı" sanıp Import'a basınca `VaultLockedException` toast'ı yiyor.

**Fix:** `importIdentityFiles: _importKeys && !vaultLocked`.

## 🟡 Risk

- `lib/main.dart:20`: `PlatformDispatcher.onError` her hatayı yutuyor, tek çıktı
  `debugPrint` — release build'de no-op. Production'da crash görünürlüğü sıfır. En azından
  dosyaya log, ideali Sentry/Crashlytics benzeri raporlama.
- `lib/core/network/ssh_session_manager.dart:140`: yalnızca `onPasswordRequest` var;
  keyboard-interactive auth yok. 2FA'lı veya `ChallengeResponseAuthentication` kullanan
  sshd'lerde password doğru olsa bile login başarısız olur. dartssh2 KBI callback'ini bağla.
- `lib/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart:167`: username
  fallback zinciri sonunda **`'root'`**. Kullanıcı username girmeyi unutursa root olarak
  bağlanmayı dener. Boş bırakıp hata göstermek veya OS kullanıcı adı daha güvenli.
- `lib/core/sync/e2ee_cloud_sync_service.dart:162,219`: export/import `deriveMasterKey`
  kullanıyor (main isolate) — 64 MiB Argon2id UI'ı 1-3 sn donduruyor.
  `deriveMasterKeyInBackground` zaten var, onu kullan.
- `lib/features/hosts/data/services/ssh_config_import_service.dart:285`: overwrite policy
  `identityId: Value(identityId)` yazıyor — key import kapalıysa `identityId` null ve
  mevcut hostun identity bağlantısı **silinir**. Null iken `Value.absent()` düşün.
- `lib/core/network/tunnel_engine.dart:313`: remote forward'da
  `Socket.connect(localHost, localPort)` timeout'suz — ölü local hedefte connection OS
  default'una kadar askıda kalır.
- `lib/core/network/socks5_proxy_server.dart:69`: client'ın sunduğu method listesi
  kontrol edilmeden `0x00` (no-auth) dönülüyor. RFC 1928: kabul edilebilir method yoksa
  `0xFF` dönmeli. Localhost-only olduğu için etkisi düşük ama spec ihlali.
- `lib/core/network/ssh_session_manager.dart:143,180`: çift keep-alive — dartssh2'nin
  kendi `keepAliveInterval`'i VE manuel `ping()` timer'ı aynı anda çalışıyor. Birini seç.
- `lib/features/hosts/data/services/ssh_config_import_service.dart:190`: key dedupe için
  workspace'teki **tüm** identity'ler (parola dahil) decrypt edilip belleğe alınıyor;
  sadece `privateKey` hash'i gerekli. Gereksiz plaintext yüzeyi.

## 🔵 Nit

- `lib/core/network/ssh_session_manager.dart:184`: host key prompt'u reddedilince bile
  hata "SSH authentication failed" diye sarılıyor — yanıltıcı mesaj.
- `lib/features/hosts/data/services/ssh_config_import_service.dart:276`: overwrite path
  her çakışmada `getHostsByWorkspace` + `firstWhere` — O(n²); baştaki `existingHosts`'tan
  map kur.
- `lib/core/network/tunnel_engine.dart:107`: `watchActiveTunnels` initial yield ile stream
  subscribe arası event kaçırabilir (mikro pencere).
- `pubspec.yaml:19`: `version: 1.0.0+1` — release öncesi gerçek sürüm/build numarası.
- Repo hijyeni: kök dizinde `Screenshot 2026-08-06...png`, `test/scratch/` repro testleri
  suite'te koşuyor — release branch'inden ayıkla veya `.gitignore`.

## Production checklist durumu

| Alan | Durum |
|---|---|
| Analyzer / testler | ✅ temiz, 401 test geçiyor |
| Crypto (KDF, AES-GCM, key wrap) | ✅ sağlam; nonce/salt üretimi doğru, `Random.secure` |
| Host key verification | ✅ TOFU + mismatch reddi doğru; KBI auth eksik (🟡) |
| Secrets at rest | ✅ keychain + DEK; release'te in-memory fallback kapalı — doğru karar |
| Brute-force lockout | ✅ exponential backoff, persist ediliyor |
| Crash reporting | ❌ yok (🟡) |
| Jump host | ❌ storage var, routing yok (🔴 #1) |
| Backup/restore | ⚠️ known_hosts çakışma bugu (🔴 #2) |

Öncelik: önce 🔴 1-3, sonra 🟡'lardan crash reporting ve keyboard-interactive auth.
