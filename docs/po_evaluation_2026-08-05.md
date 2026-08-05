# Terly2 — PO Değerlendirme (5 Ağustos 2026)

**Proje:** Terly2 (Cross-Platform SSH/SFTP & Terminal Remote Workstation)
**Değerlendirme Tarihi:** 5 Ağustos 2026
**Önceki rapor:** [`docs/product_owner_evaluation.md`](product_owner_evaluation.md) (2 Ağustos 2026)
**Yöntem:** Doküman iddiaları yerine kod tabanı üzerinde ölçüm (`dart analyze`, `flutter test`, grep, git log).

---

## 1. Ölçülen Durum (iddia değil)

| Metrik | Değer |
| :--- | :--- |
| `lib` dart dosya sayısı | 137 |
| Test dosyası / test sayısı | 74 / **339 yeşil** |
| `dart analyze` | 0 issue |
| Commit sayısı | 99 |
| CI | **YOK** (`.github` dizini yok) |
| TODO / FIXME | 0 |

Önceki PO raporu (2 Ağustos) 221 test bildiriyordu → 3 günde +118 test ve 4 yeni özellik (split-pane different host, SFTP connection scoping, terminal line height, layout templates). Geliştirme hızı yüksek.

---

## 2. Modül Olgunluk Durumu

### 2.1. Bitmiş — gerçekten kod var

| Modül | Kanıt |
| :--- | :--- |
| **Terminal motoru** | Tab, split pane (farklı host'a dahi), resizable divider, broadcast input (cmd+click), reconnect, font/tema registry, layout template save/replay |
| **Host + Identity Vault** | Argon2id + AES-256-GCM, DEK/KEK, exponential lockout |
| **SFTP** | Dual-pane, transfer queue, in-app remote editor, chmod/chown, atomic upload |
| **Tunnels** | Local `-L` / Remote `-R` / Dynamic SOCKS5 `-D` + throughput |
| **Snippets & Runbooks** | `${INPUT:var}` parametreleri, ayrı runbooks ekranı |
| **Workspaces** | İzolasyon + scoping |
| **E2EE Sync** | `lib/core/sync/e2ee_cloud_sync_service.dart` |
| **Biometric lock** | `settings/domain/services/biometric_lock_service.dart` — önceki raporda P0'daydı, **kapandı** |
| **Clipboard auto-clear** | `clipboard_auto_clear_service.dart` |
| **README** | Gerçek içerikle yenilenmiş — önceki P0 **kapandı** |

### 2.2. Spec'te var, kodda YOK (grep = 0 hit)

- **AI asistanı** — `ollama`, `ai_`, `AiAssistant` için sıfır dosya. Warp'a karşı tek diferansiyatör, hiç başlamamış.
- **Mosh** — yalnızca SSH'e fallback eden enum değeri
- **Serial port** — aynı şekilde enum-only
- **Team Vaults / RBAC / audit log** — sıfır
- **YubiKey / Secure Enclave** — sıfır
- **Session recording (asciinema)** — sıfır
- **Onboarding wizard + `~/.ssh/config` import** — sıfır
- **Warp-style block mode** — sıfır

### 2.3. KRİTİK — yarım özellik (dürüstlük borcu)

**Jump Host / ProxyJump `jumpHostId` alanı DB'de, model'de, host formunda ve sync serializasyonunda var — ancak bağlantı katmanında hiç kullanılmıyor.**

```
lib/core + lib/features/terminal içinde "jumpHost" araması:
  lib/core/sync/e2ee_cloud_sync_service.dart:100   'jumpHostId': h.jumpHostId,
  lib/core/sync/e2ee_cloud_sync_service.dart:310   jumpHostId: Value(item['jumpHostId'] as String?),
```

Yani kullanıcı bastion sunucu seçiyor, uygulama bunu tamamen yok sayıyor ve doğrudan hedefe bağlanıyor. Bu, daha önce `020d55e` commit'inde Mosh dropdown'u için düzeltilen sorunun aynısı. **Sessiz yalan; eksik özellikten daha kötü.** En yüksek öncelikli borç.

---

## 3. Teknik Borç & Hijyen

- `test/scratch/` — 3 adet repro testi commitli (`sel_repro_test.dart`, `sel_repro2_test.dart`, `slash_repro_test.dart`), test suite'ine debug `print` çıktısı basıyor. Silinmeli.
- `Screenshot_20260805_004503.jpg` — repo kökünde untracked artık.
- Commitlenmemiş WIP: `lib/features/terminal/presentation/views/terminal_tab_view.dart` +255/−185 (tab bar compact/overflow, <620px eşiği). Testi de yazılmış, temiz görünüyor → commit edilmeli.
- **CI yok.** 339 test var ama hiçbir otomasyon koşturmuyor. En ucuz kalite kazancı.
- `LICENSE` yok, `CHANGELOG` yok, sürüm hâlâ `1.0.0+1` (hiç release edilmemiş).

---

## 4. Önceliklendirilmiş Backlog

### P0 — Bu hafta (release-blocker)

1. **Jump host kararı:** ya `dartssh2` üzerinde gerçek ProxyJump chain'ini kur, ya UI'dan kaldır. Yarım bırakılamaz.
2. **GitHub Actions:** PR'da `dart analyze` + `flutter test`.
3. **Hijyen:** `test/scratch/` sil, kökteki screenshot'ı sil, terminal tab bar WIP'ini commit et.

### P1 — Diferansiyasyon (pazarda seni Termius'tan ayıran tek şey)

4. **AI asistanı MVP.** Sıfırdan başlanıyor, kapsamı dar tut: Settings'e API key ekranı + terminalde `Cmd+I` → "natural language to shell" ve "explain this error". Ollama/yerel LLM sonraki iterasyon. Bu olmadan 2026'da terminal ürünü pazarlanamıyor.
5. **Onboarding:** `~/.ssh/config` parse + tek tıkla import. Ucuz, retention'a doğrudan etki, ilk 60 saniyeyi kurtarıyor.

### P2 — Sonrası

6. **Mobil arka plan / Mosh (roaming UDP)** — mobil vaadi şu an gerçek değil.
7. **Team Vaults / RBAC** — monetizasyon katmanı, ancak launch öncesi erken.

---

## 5. PO Sonuç

**Mühendislik olgun, ürün hikâyesi eksik.**

- Motor kalitesi: 9/10 (339 test yeşil, 0 analyzer issue, disiplinli katman ayrımı)
- Farklılaştırıcı (AI): 0/10 (hiç kod yok)
- Dürüstlük borcu: 1 adet (jump host)

**Sıra:** önce yalanı kapat (jump host), sonra CI, sonra AI.

Önceki raporun 8.7/10 puanı ürünün *vaadine* göre verilmiş. Kodda ölçülen haliyle: **çekirdek terminal/SSH/SFTP/tunnel ürünü launch-ready, ancak spec'in Faz 4 (AI, hardware key) ve Faz 3 (Team/RBAC) kısımları henüz başlamamış durumda.**
