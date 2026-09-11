# Device Link doğrulama harness'ı (Faz 1)

Bu dizin uygulamayla dağıtılmaz. Device Link, masaüstü ile telefon arasında
LAN üzerinden gerçek bir terminal oturumu taşıyacağı için, taşıma katmanı
eklenmeden önce ve sonra elle doğrulanabilir araçları burada tutar.

Faz 1'deki smoke testi gerçek `HttpServer.bindSecure` + `WebSocketTransformer`
akışını kullanır; yalnızca `127.0.0.1`'e bağlanır ve Docker ya da fiziksel cihaz
gerektirmez.

## Çalıştırma

```sh
dart run tool/device_link/smoke.dart
```

Script her adımı satır satır yazar, hepsi geçerse `0`, ilk hatada `1` döner.

## Faz 0 ön kontrolü

Depo kökünden aşağıdaki komutlar, eklenen bağımlılıkları ve platform
yapılandırmasını doğrular:

```sh
flutter pub get
plutil -lint ios/Runner/Info.plist
rg -n 'CHANGE_WIFI_MULTICAST_STATE|CAMERA' android/app/src/main/AndroidManifest.xml
```

`flutter pub get` başarılı olduğunda `pubspec.lock` güncellenir. `plutil`
başarısızsa iOS plist'i geçersizdir; `rg` iki Android iznini yazdırmalıdır.

## Doğrulanan akış

Gerçek protokol aşağıdaki sırayla doğrulanır:

1. Self-signed TLS sunucusu başlar ve WebSocket bağlantısını kabul eder.
2. İstemci QR'dan gelen doğru SPKI piniyle bağlanır.
3. Yanlış SPKI pini bağlantıyı reddeder.
4. `hello` / `hello_ack` sürüm ve şema denetiminden geçer.
5. Yanlış, ikinci kez kullanılan ve süresi dolmuş eşleştirme tokenları reddedilir.
6. Yanlış SPKI piniyle bağlantı reddedilir.
7. Protokol sürüm uyuşmazlığı reddedilir.

Aynı senaryolar CI'da `test/unit/core/network/device_link/` altındaki gerçek
loopback entegrasyon testleriyle de koşar. Harness, bu testlerin yerine geçmez;
geliştiricinin TLS ve WebSocket akışını bağımsız olarak gözlemlemesi içindir.

## Docker kullanılmıyor

Mosh harness'ının aksine, Faz 1 doğrulaması harici bir sunucu veya platform
servisi gerektirmez. Bu nedenle burada Dockerfile ya da compose dosyası yoktur.
İki fiziksel cihazla mDNS, QR kamera izni ve mobil terminal akışı ancak Faz 4
sonrasında elle doğrulanacaktır.
