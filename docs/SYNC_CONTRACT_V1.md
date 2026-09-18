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

Bu build v3 üretir, v1/v2/v3 okur. Daha yüksek bir `schema_version` gördüğünde
açmayı denemez; sürümü söyleyerek reddeder.

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
