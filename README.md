# Veyra Connect

**Windows 10/11 icin tek dosyali Discord baglanti yardimcisi (onizleme).**

[**VeyraConnect_Kur.bat dosyasini indir (v1.0.0-beta.1)**](https://github.com/Naveax/Veyra-Connect/releases/download/v1.0.0-beta.1/VeyraConnect_Kur.bat) | [Kaynak kurucu](VeyraConnect_Kur.bat) | [Hata bildir](https://github.com/Naveax/Veyra-Connect/issues)

## Kurulum: indir, cift tikla

1. GitHub **Releases** sayfasindan `VeyraConnect_Kur.bat` dosyasini indir. **Code > Download ZIP** gerekmez.
2. Dosyaya cift tikla. Kurucu, desteklenen Windows surumunu denetleyip resmi ByeDPI arsivini indirmeyi dener; indirilen arsivi yayinlanmis **SHA-256** ile dogrular.
3. Kurulum basariliysa masaustundeki **Veyra Connect** kisayolunu ac. Discord zaten aciksa, mevcut oturumu kapatip yeniden baslatmak icin onay vermen gerekebilir.
4. Call of Duty icin once WinDivert/GoodbyeDPI gibi baska paket filtreleyicilerin kapali olmasi gerekir. Kurulum bunlari izinsiz durdurmaz. Gerekirse **Veyra Oyun Modu** kisayolunu kullan.

> **Beta:** Kaynak kodu ve kurucu yapisi incelenmistir; gercek Windows 10 + Windows 11 kurulumlari ve Discord ses/ekran paylasimi + Call of Duty eszamanli kullanim **genel olarak dogrulanmamistir**. Her oyunda veya her agda calisacagi garanti edilmez.

## Nasil calisir?

Veyra Connect, [hufrea/ByeDPI](https://github.com/hufrea/byedpi) `ciadpi` programini **yerel SOCKS5 proxy** olarak kullanir. Yalnizca `127.0.0.1:18766` uzerinde dinler; **WinDivert kurmaz, cekirdek surucusu yuklemez, sistem proxy'sini veya Windows guvenlik ayarlarini degistirmez**. Discord masaustu uygulamasi SOCKS5 baglanti parametreleriyle baslatilir. Calisan profili dogrulamak icin Discord HTTPS API uzerinde baglanti testleri uygulanir.

**Sinir:** Chromium SOCKS5 ayarlari butun Discord WebRTC/UDP ses ve ekran paylasimi trafigini proxy'ye tasimaz. Bunlar ayrica test edilmelidir. Ses veya ekran paylasimi guvencesi yoktur. Bu arac anti-cheat'i degistirmez veya atlatmaz.

## Destek ve gereksinimler

| Sistem | Durum |
| --- | --- |
| Windows 10 1809+ x64 / x86 | Hedeflenen |
| Windows 11 x64 | Hedeflenen |
| Windows ARM64 | Desteklenmiyor |

Windows PowerShell 5.1, `curl.exe`, internet baglantisi ve masaustu Discord uygulamasi gerekir. Kurucu varsayilan olarak **yonetici izni istemeden**, kullanicinin `%LOCALAPPDATA%\VeyraConnect` dizinine kurulur. Yalnizca istege bagli sistem servisi / DNS islemleri yonetici izni isteyebilir.

## Kullanim ve kaldirma

- **Veyra Connect**: SOCKS5 proxy'yi baslatip Discord'u acma
- **Veyra Oyun Modu**: Kullanici onayiyla mevcut *baska* paket filtreleme servisini kapatma (oyun kapaliyken)
- **Veyra Durum**: DNS / HTTPS / proxy tanilama
- `%LOCALAPPDATA%\VeyraConnect\KALDIR.cmd`: Kurulumu kaldirir, eski kullanici ag ayarlarini silmez
- `%LOCALAPPDATA%\VeyraConnect\DNS_ONAR_OPSIYONEL.cmd`: Istege bagli Discord NRPT kurali, yalnizca var olan kural yoksa
- `%LOCALAPPDATA%\VeyraConnect\DNS_GERI_AL.cmd`: Yalnizca Veyra tarafindan olusturulan DNS kurallarini kaldirir

Kaynak gelistirme icin [src/VeyraConnect.ps1](src/VeyraConnect.ps1), [paket testi](tests/verify-package.py) ve [yayin sureci](docs/RELEASING.md) dosyalarina bak.

## Ucuncu taraf

ByeDPI v0.17.3, **MIT Lisansi** ile dagitilir: [ByeDPI LICENSE](LICENSE_BYEDPI.txt). Kurucu dosyaya kapali kaynak bir binary gommez; kurulum asamasinda resmi Windows arsivini indirir ve dosya SHA-256'sini kontrol eder.

## Guvenlik notu

Antivirus, Windows Firewall, TLS sertifika dogrulamasi, Core Isolation / Memory Integrity, Call of Duty/RICOCHET veya baska anti-cheat dosyalari otomatik degistirilmez. Paket ag erisim kisitlamalarini tum aglarda asma garantisi vermez. Kurucuyu calistirmadan once kaynak dosyalarini inceleyebilirsiniz.