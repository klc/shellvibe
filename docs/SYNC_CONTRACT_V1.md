# Sync Contract v1 — Zero-Knowledge Backup Envelope

> Tarih: 2026-09-18 · Durum: **v3 envelope uygulandı ve testlerle sabitlendi**
>
> Bu belge `shellvibe-server`'daki [ADR 003](../../shellvibe-server/docs/adr/003-zero-knowledge-sync-envelope.md)'ün
> istemci tarafındaki karşılığıdır ve o ADR'nin doğrulama kapısının bu depoya
> düşen yarısını kapatır. Sunucu `ciphertext`'i opaque bir string olarak görür;
> bu belge o string'in **içinde ne olduğunu** kilitler.
>
> Kaynak: `lib/core/sync/backup_envelope.dart`,
> `lib/core/sync/e2ee_cloud_sync_service.dart`.
> Testler: `test/unit/core/sync/backup_envelope_test.dart`.

## 1. Sunucunun gördüğü ve göremediği

Sunucu şunları saklar: vault ve cihaz kimliği, revision numarası,
`schema_version`, `encryption_version`, `ciphertext_sha256`, `size_bytes`,
zaman damgaları ve ciphertext'in kendisi.

Sunucu şunları **göremez**: host adı, kullanıcı adı, SSH private key, parola,
snippet, runbook, workspace adı — hiçbiri. Anahtar materyali sunucuya hiç
gitmez, sunucuda türetilmez ve escrow edilmez.

**Hesap parolası sync anahtarı değildir.** Hesap parolası sıfırlanması şifreli
kullanıcı verisini açmaz. Bunlar ayrı iki sırdır ve ayrı kalmak zorundadır.

## 2. Envelope sürümleri

| Sürüm | Taşıdığı | Sonuç |
|---|---|---|
| v1 | Yalnız identity ciphertext | Çözebilecek anahtar dışa çıkmadı; sırlar yalnız yazan cihazda kullanılabilir |
| v2 | + passphrase ile sarılmış vault DEK | Yedek kendi kendine yeterli, ama tek bir sır açabilir |
| **v3** | + rastgele payload anahtarı, sır başına bir sarma | Passphrase **veya** recovery kodu açar; passphrase değişimi payload'ı yeniden şifrelemez |
| v4 | + payload anahtarı altında sarılmış sync anahtarı | Otomatik sync'in işlem günlüğünü şifreleyen anahtar yedekle birlikte taşınır |
| **v5** | payload anahtarı hesap anahtarı altında sarılır; hesabın anahtar kaydı zarfın içinde | Cihaz passphrase'i bilmeden mühürler; passphrase ve recovery kodu yine açar (§11) |

Bu build v1–v5 okur. Bulut yedeğini ve sync zeminini, cihaz hesap anahtarını
tutuyorsa v5, tutmuyorsa v3/v4 olarak yazar; dosyaya alınan yedek her zaman
v3/v4'tür, çünkü arkasında bir hesap yoktur. Daha yüksek bir `schema_version`
gördüğünde açmayı denemez; sürümü söyleyerek reddeder.

## 3. v3 anahtar düzeni

```text
payloadKey        = 32 rastgele bayt (Random.secure)

payload           = AES-256-GCM(payloadKey, UTF-8(payload JSON))
dek_wrapped       = AES-256-GCM(payloadKey, base64(vault DEK))

K_pass            = Argon2id(passphrase,                salt)
pk_wrapped_pass   = AES-256-GCM(K_pass,  base64(payloadKey))

K_recovery        = Argon2id(normalize(recoveryCode),   recovery_salt)
pk_wrapped_recovery = AES-256-GCM(K_recovery, base64(payloadKey))
```

Açma yönü: sır → Argon2id → ilgili `pk_wrapped_*` çözülür → `payloadKey` →
`payload` ve `dek_wrapped` çözülür.

### Şifreleme parametreleri

| Parametre | Değer | Kaynak |
|---|---|---|
| KDF | Argon2id | `EncryptionEngine` |
| Şifre | AES-256-GCM | `EncryptionEngine` |
| Nonce | 12 bayt, her şifreleme için yeni | ciphertext'in başına eklenir |
| Salt | 16 bayt, her envelope için yeni | `salt`, `recovery_salt` ayrı üretilir |
| payloadKey | 32 bayt | her `seal` çağrısında yeni |

Her ciphertext alanı `base64(nonce ‖ ciphertext ‖ tag)` biçimindedir.

## 4. JSON alanları

```json
{
  "schema_version": 3,
  "salt": "<base64, 16 bayt>",
  "recovery_salt": "<base64, 16 bayt>",
  "payload": "<base64 AES-GCM>",
  "dek_wrapped": "<base64 AES-GCM>",
  "pk_wrapped_pass": "<base64 AES-GCM>",
  "pk_wrapped_recovery": "<base64 AES-GCM>"
}
```

`recovery_salt` ve `pk_wrapped_recovery` birlikte `null` olabilir — recovery
kodu olmadan mühürlenmiş bir yedek demektir. Biri varsa diğeri de olmak
zorundadır; `BackupEnvelope.hasRecoveryPath()` ikisini birden arar, böylece
geri yükleme ekranı recovery seçeneğini ancak gerçekten varsa gösterir.

## 5. Payload kapsamı

`payload` içindeki JSON şu tabloları taşır:

`workspaces`, `identities`, `host_groups`, `hosts`, `known_hosts`,
`port_forward_rules`, `snippets`, `runbooks`, `runbook_steps`.

Kapsam **dışı**, kasıtlı olarak:

- **Paired Device sırları.** ADR 003: known-host güven kararı cihaz-yerel
  kalır. Bir yedekten geri yüklenen eşleşme, kullanıcının o cihazda hiç
  vermediği bir güven kararıdır.
- **Vault master password ve sarılmış DEK'in yerel kopyası.** Cihaz keychain'ine
  aittir; yedek kendi DEK kopyasını `dek_wrapped` içinde taşır.
- **Terminal geçmişi, oturum durumu, ayarlar.** Yedek kimlik ve altyapı
  verisidir, uygulama durumu değil.

`identities` içindeki `passwordEncrypted`, `privateKeyEncrypted` ve
`passphraseEncrypted` alanları **yedeğin kendi DEK'i altında** şifreli gelir.
Geri yüklemede her biri çözülüp bu cihazın vault DEK'i altında yeniden
şifrelenir (`_rewrapSecret`), yani sırlar farklı bir cihazda da kullanılabilir
kalır. v1 yedeklerinde DEK olmadığı için bu adım atlanır ve sonuç
`secretsRecovered: false` ile işaretlenir.

## 6. Recovery kodu

- 256 bit rastgele (`recoveryCodeBytes = 32`).
- Crockford base32, **`I`, `L`, `O`, `U` çıkarılmış** — elle yazılmış bir kod
  rakamla veya başka harfle karıştırılamaz.
- Beşerli gruplar hâlinde gösterilir: `X4K7M-9PQR2-…`.
- **Hiçbir yerde saklanmaz.** Ne cihazda, ne sunucuda. Kurulumda kullanıcıya
  bir kez gösterilir ve yeniden yazdırılarak doğrulanır.
- Türetmeden önce normalize edilir: tire, boşluk ve büyük/küçük harf farkı
  atılır. Parola yöneticisinden yapıştırılan bir kod tiresiz gelir; normalize
  edilmezse doğru kod "yanlış" görünür.

**Kaybı geri alınamaz.** Passphrase de recovery kodu da kaybolmuşsa yedek
kalıcı olarak açılamaz. Bu bir eksiklik değil, zero-knowledge'ın tanımıdır.

## 7. Başarısızlık davranışı

Tek bir istisna tipi: `BackupEnvelopeException`.

Aynı istisnayı üreten durumlar — **kasıtlı olarak ayırt edilmez**:

- yanlış passphrase
- yanlış recovery kodu
- kurcalanmış ciphertext (payload, sarılmış anahtar veya DEK)
- değiştirilmiş salt
- başka bir yedekten kopyalanmış payload

Ayırt edebilen bir çağrı yeri oracle olurdu; kullanıcıya verilecek cevap da her
durumda aynı. AES-GCM kimlik doğrulaması bunların hepsini aynı tag hatasına
indirger.

Farklı mesaj alan tek iki durum, güvenlik sınırında olmayanlar: okunamayan JSON
ve bu build'in bilmediği bir `schema_version`.

**Hiçbir hata yolunda kısmi veri dönmez ve hiçbir kayıt yazılmaz.** Çözme
başarısızsa veritabanı transaction'ı hiç açılmaz.

## 8. Sunucu tarafıyla bağ

`PUT /api/v1/sync/vault` gövdesinde:

| Alan | Değer |
|---|---|
| `ciphertext` | Bu belgedeki envelope JSON'ı, tek string olarak |
| `ciphertext_sha256` | O string'in **UTF-8 baytları** üzerinden SHA-256, hex |
| `schema_version` | Envelope'un `schema_version`'ı (3) |
| `encryption_version` | Şifreleme düzeninin sürümü |
| `base_revision` | İstemcinin bildiği son revision |
| `upload_id` | İstemci üretimi idempotency anahtarı |
| `device_id` | Sunucunun bu cihaza verdiği ULID |

Sunucu `ciphertext_sha256`'yı kendi hesabıyla karşılaştırır ve tutmazsa `422`
döner. Hash, string'in baytları üzerinden alınır — çözülmüş payload üzerinden
değil.

## 9. Doğrulama kapısı

ADR 003'ün istemciden beklediği maddeler ve durumları:

| Madde | Durum |
|---|---|
| `SYNC_CONTRACT_V1.md` | 🟢 Bu belge |
| Tamper fixture'ı | 🟢 `backup_envelope_test.dart` — payload, sarılmış anahtar, DEK, salt ve çapraz-envelope kopyası |
| Yanlış passphrase fixture'ı | 🟢 `backup_envelope_test.dart` |
| Yanlış recovery kodu | 🟢 `backup_envelope_test.dart` |
| v1/v2 geriye uyum | 🟢 `backup_envelope_test.dart` |
| Concurrent revision testi | 🟢 Sunucu tarafında, `SyncVaultOptimisticConcurrencyTest` |
| Plaintext sızıntı taraması | 🟢 Sunucu tarafında, `RedactionProcessor` + edge log testleri |

## 10. Değişiklik politikası

- Envelope'a geriye uyumlu alan eklemek sürüm artırmaz; okuyucu bilmediği alanı
  yok sayar.
- Anahtar düzenini, KDF parametrelerini veya bir alanın anlamını değiştirmek
  **yeni bir `schema_version` gerektirir**, ve okuyucu eski sürümleri taşımaya
  devam eder.
- Bir sürümü okumayı bırakmak, o sürümle yazılmış her yedeği kalıcı olarak
  erişilemez yapar. Bu ancak açık bir migrasyon yolu ile yapılabilir.

## 11. Hesap anahtarı (v5)

v4'e kadar passphrase **çalışan sırdı**: her cihaz onu saklıyor ve her yedeği
onunla mühürlüyordu. v5'te cihaz rastgele bir **hesap anahtarı** tutar;
passphrase ve recovery kodu yalnızca o anahtarı sarar. İkisi de hiçbir cihazda
saklanmaz ve yalnızca eldeki cihazlar yetmediğinde yazılır: kurtarma ve web
paneli.

```text
accountKey   = 32 rastgele bayt, hesabın ömrü boyunca sabit
wrapKey      = HKDF-SHA256(accountKey, salt yok, info "shellvibe/account-key/wrap/v1")
macKey       = HKDF-SHA256(accountKey, salt yok, info "shellvibe/account-key/record-mac/v1")

payloadKey   = 32 rastgele bayt, her seal çağrısında yeni
payload, dek_wrapped, sync_key_wrapped = v4'teki gibi, payloadKey altında
pk_wrapped_ak = AES-256-GCM(wrapKey, base64(payloadKey))
```

### Anahtar kaydı

Hesap başına bir tane. Sunucuda `GET/PUT /api/v1/sync/account-key` altında
durur ve her v5 zarfına `key_record` alanı olarak aynen kopyalanır; böylece
yedek tek başına açılabilir kalır (panel ikinci bir istek yapmaz).

```json
{"v": 1, "body": "<JSON string>", "mac": "<base64>"}
```

```text
body      = {"pass": {"salt", "wrapped"}, "recovery": {"salt", "wrapped"}?}
wrapped   = AES-256-GCM(Argon2id(sır, salt), base64(accountKey))
mac       = HMAC-SHA256(macKey, UTF-8(body))
```

MAC `body`'nin **tam baytları** üzerindendir; `body` bu yüzden string olarak
taşınır, kanonik JSON üzerinde anlaşmak gerekmez. MAC'in işi: anahtarı tutan
bir cihaz, passphrase'i bilmeden bir kaydın kendi anahtarına ait olduğunu
söyleyebilir. Sunucunun verdiği kayıt zarfa kopyalanmadan önce, başka bir
cihazın verdiği anahtar saklanmadan önce bununla sınanır. Açılan ama başka bir
kayıttan taşınmış bir slot reddedilir.

Açma yönü: sır → Argon2id → slot → `accountKey` → MAC doğrulanır → `wrapKey` →
`pk_wrapped_ak` → `payloadKey`. Anahtarı tutan cihaz ilk üç adımı atlar.

### Tek anahtar kuralı

**Sunucudaki kayıt hesabın anahtarıdır ve cihaz yalnızca o kaydın kefil olduğu
anahtarı tutar.** Kayıt bir revision'ın üstüne yazılır (`base_revision`,
uyuşmazsa `409 account_key_conflict`); aynı anda kurulum yapan iki cihazdan biri
kazanır, diğeri kazananın kaydını okuyup anahtarını benimser. Hiçbir yol
anahtar üretip tek başına devam etmez.

Kayıt hesaba aittir, vault'a değil: "bulut yedeğini sil" onu kaldırmaz.
Kurulum mu / mevcut hesaba katılma mı kararını da o verir.

### Sıfırlama

Passphrase, recovery kodu ve anahtarı tutan her cihaz kaybolduysa tek çıkış
web panelindeki **Danger zone → Reset encryption**'dır (`DELETE
/panel/encryption`, panelin yeniden doğrulaması arkasında: parola ya da bağlı
Google/GitHub girişi, artı `RESET` yazmak). Anahtar kaydını, iki vault'u, işlem
günlüğünü ve açık aktarımları tek transaction'da siler. Uygulama kilit açma
ekranından oraya yönlendirir; API'de karşılığı yoktur, çünkü uygulamadaki
yeniden doğrulama parolası olmayan hesaplarda çalışmaz.

Sıfırlamadan sonra:

- Anahtarı tutan cihaz bunu açılışta görür (kayıt artık onun anahtarına ait
  değildir): yedek ekranı uyarır, sync `accountKeyMismatch` ile durur ve eski
  anahtarla yeni günlüğe hiçbir şey yazmaz.
- "Remove From This Device" kurulumu ve cihazın sync'teki yerini (sürümler,
  imleçler, giden kuyruğu, sync anahtarı) birlikte unutur. Cihaz yeniden
  eklendiğinde join baştan çalışır: yeni zemini birleştirir, kendi satırlarını
  gönderir, hiçbir şeyi değiştirmez. Cihazdaki veri kaybolmaz.
- Eski yedekler sunucudan silinmiştir; dosyaya alınmış kopyalar eski
  passphrase ile açılmaya devam eder.

### Geçiş

- Kaydı olmayan hesap v3/v4 ile eskisi gibi çalışır. Sunucunun
  `enabled` bayrağı (`SYNC_ACCOUNT_KEY_ENABLED`) açılana kadar yeni kayıt
  oluşturulmaz.
- Bayrak açıkken passphrase'i tutan bir cihaz her açılışta geçmeyi dener: kayıt
  varsa passphrase'iyle açıp anahtarı benimser, yoksa üretip yazar.
- Passphrase cihazdan ancak şu ikisi doğruysa silinir: anahtar kayda karşı
  doğrulandı, ve hesabın sync zemini ya yok ya da v5. Zemin v4 kaldığı sürece
  geride kalan bir cihaz ona passphrase ile dönmek zorunda kalabilir.
- Zaten sync'te olan ve anahtarı tutan cihaz, v4 zemini v5 olarak yeniden
  yazar. Yalnızca anahtarı tutan (kodla katılmış) bir cihaz v4 zeminle
  karşılaşırsa bekler ve bunu `groundNeedsUpdate` olarak söyler.
- **Tek yönlüdür.** Kaydı olan hesaba `schema_version < 5` yükleme
  `422 envelope_version_retired` ile reddedilir. Eski build'ler v5'i okuyamaz.
  Bu yüzden bayrak, her platformda v5 okuyan build yayında olmadan açılmaz.

### Bilinen sınırlar

- Anahtar döndürme yok: iptal edilen bir cihaz elindeki anahtarı geri vermez.
- Passphrase değiştirme henüz yok. Eklendiğinde eski passphrase, eski kaydın
  bir kopyasını tutan birine karşı anahtarı korumaz; onu yalnız anahtar
  döndürme çözer.
- Kayıt geri sarılmaya karşı sayaç taşımaz. Bugün kayıtlar arasındaki tek fark
  recovery slot'unun varlığıdır.

## 12. Cihazdan cihaza aktarım

Hesap anahtarını tutan bir cihazdan tutmayan birine, passphrase yazmadan.
Bir cihaz QR kodu gösterir, diğeri tarar; sonrası sunucudaki kısa ömürlü bir
posta kutusundan geçer (`/api/v1/sync/handoffs`, 180 saniye, slot başına tek
yazma). Kod, kullanıcının elindeki cihazın ekranından okunur; sunucunun
seçememesi ya da öğrenememesi gereken şeyleri o taşır.

```text
QR      = {id, gösterenin tek kullanımlık X25519 açık anahtarı, 32 baytlık sır,
           kullanıcı id, yön, son kullanma}
shared  = X25519(tarayanın tek kullanımlık anahtarı, gösterenin açık anahtarı)
keys    = HKDF-SHA256(shared, salt = sır,
                      info = JSON["shellvibe/handoff/v1", id, kullanıcı,
                                  gösterenin açık anahtarı, tarayanın açık anahtarı, yön])
          -> 64 bayt: offer anahtarı ‖ answer anahtarı
offer   = {pk: tarayanın açık anahtarı, box: AES-256-GCM(offer anahtarı, yük)}
answer  = AES-256-GCM(answer anahtarı, yük)
```

Hangi cihazın gösterdiği kameraya bağlıdır, anahtarın kimde olduğuna değil:

| Gösteren | Tarayan | Anahtar nerede geçer |
|---|---|---|
| Anahtarı tutan (masaüstü) | Yeni cihaz (telefon) | `answer` |
| Yeni cihaz (masaüstü) | Anahtarı tutan (telefon) | `offer` |

Güvenlik özellikleri, `device_handoff_test.dart` ile sabitlenmiş:

- Sunucu mesajları okuyamaz: ne özel anahtarlardan birine ne de koddaki sırra
  sahiptir.
- Sunucu tarayanın açık anahtarını kendi anahtarıyla değiştiremez: `offer`
  koddaki sırrı gerektiren bir anahtarla mühürlüdür, değiştirilen anahtar başka
  anahtarlar türetir ve `offer` açılmaz. Gösteren cihaz `offer` açılmadan hiçbir
  şey mühürlemez.
- Bir mesaj başka bir aktarıma, başka bir hesaba ya da ters yöne taşınamaz;
  hepsi türetmeye bağlıdır.
- Alan cihaz gelen anahtarı saklamadan önce hesabın anahtar kaydına karşı
  doğrular.
- Veren cihaz anahtarı ancak vault açıkken okuyabilir.

Kodun dayanmadığı tek şey: fotoğrafının çekilip, **aynı hesaba giriş yapmış**
biri tarafından, gerçek cihazdan önce kullanılması. Bu yüzden kısa ömürlü ve
tek kullanımlıktır, ve içinde passphrase yoktur: aktarımdan sonra sızan bir kod
hiçbir şey açmaz.
