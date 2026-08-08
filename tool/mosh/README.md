# Mosh doğrulama harness'ı (Faz 0)

`docs/mosh_integration_plan.md` Faz 0'ın çıktısı. Amaç tek bir soruyu
cevaplamak: **`dart_mosh` gerçek bir `mosh-server` ile wire uyumlu mu?**
Paket 0.0.x ve az kullanılıyor; Faz 1'in üstüne kod yazmadan önce bu kanıt
gerekiyor.

Bu klasör uygulamayla dağıtılmaz, `lib/` altına hiçbir şey koymaz ve CI'da
koşmaz — Docker gerektirdiği için elle çalıştırılır.

## Çalıştırma

```sh
docker compose -f tool/mosh/docker-compose.yml up -d --build
dart run tool/mosh/smoke.dart
docker compose -f tool/mosh/docker-compose.yml down
```

Script her adımı satır satır yazar, hepsi geçerse `0`, ilk hatada `1` döner.

## Neyi doğruluyor

1. `mosh-server new -s ...` SSH üzerinden `exitCode 0` ile açılıyor
2. `MOSH CONNECT` satırı parse ediliyor ve port yayınlanan aralıkta
3. UDP oturumu kuruluyor, sunucu ilk ekran karesini yolluyor
4. Gönderilen komutun çıktısı geri geliyor (SSP iki yönde de anlaşıyor)
5. `resize` + `rehome` sonrası oturum yaşıyor ve cevap vermeye devam ediyor

5. madde Faz 2'deki roaming'in temel taşı — ağ değişimi ve app resume
aynı `rehome()` çağrısına bağlanacak.

## Ortam notları

- SSH `127.0.0.1:2222`, kullanıcı/parola `mosh`/`mosh`. Tek kullanımlık hesap;
  compose her portu loopback'e bağlıyor, dışarı açık değil.
- UDP `60000-60010` 1:1 publish ediliyor. `mosh-server` bu aralığın dışında bir
  port seçerse datagramlar container'a ulaşmaz — script bunu ayrı bir kontrol
  olarak raporluyor.
- `mosh-server -s`, `SSH_CONNECTION`'daki IP'ye bind eder. Container içinde bu
  eth0 adresidir ve Docker'ın port yönlendirmesi oraya gider, yani `-i`
  gerekmez.

## Başarısız olursa

Plan bu riski taşıyor: uyum kanıtlanamazsa `klc/dart_mosh` fork'unda düzeltme
yapılır (paket zaten commit ile pinlenmiş durumda) ve Faz 1 ~1 hafta uzar.
Fork: <https://github.com/klc/dart_mosh> · upstream: `gwitko/dart_mosh`.
