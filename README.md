<p align="center">
  <img src="android/res/mipmap-xxxhdpi/ic_launcher.png" width="120" alt="X1">
</p>

# X1

Aplikacja do sterowania modelami RC (auto, łódź, dron) z tabletu z Androidem.
Komendy idą do modelu przez Bluetooth Low Energy (BLE UART). Na środku ekranu
widać obraz z kamery modelu przesyłany przez RTSP.

Napisana w Qt 6 / QML (C++17). Docelowo na Androida (testowana na tablecie
Lenovo TB-X606F z Androidem 10); da się ją też zbudować jako aplikację desktopową.

![Ekran aplikacji X1](docs/screenshot.png)

## Funkcje

- **Dwa joysticki** obsługiwane jednocześnie, każdy jednym palcem: lewy (JL) i prawy (JP).
- **START / STOP** – przełącznik stanu pracy. STOP zeruje oba joysticki.
- **F1, F2, F3** – przyciski chwilowe (działają tylko w czasie przytrzymania).
- **Lights** – światła, przełącznik (wł./wył.).
- **Horn** – klakson, działa w czasie przytrzymania.
- **Wideo na żywo** z kamery modelu (RTSP, H.264). Po zerwaniu połączenia
  aplikacja co 3 s próbuje połączyć się ponownie.
- **Telemetria** nałożona na obraz: pozycje joysticków, stan, światła,
  połączenie Bluetooth, ostatnia wysłana komenda.
- **Setup** – wyszukiwanie i łączenie z modułem BLE, adres strumienia RTSP
  (zapamiętywany między uruchomieniami).
- Ciemny, granatowo-cyjanowy motyw, czytelny także w nocy.
- Na Androidzie ekran jest zablokowany w poziomie.

## Protokół Bluetooth

Aplikacja łączy się z modułem BLE UART:

| Moduł | Usługa | Charakterystyka zapisu |
|---|---|---|
| Nordic UART Service (np. ESP32, nRF) | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | `6e400002-…` (RX) |
| HM-10 / HM-19 / AT-09 | `0000ffe0-0000-1000-8000-00805f9b34fb` | `0000ffe1-…` |

Każda komenda to linia tekstu zakończona `\n`, wysyłana w kawałkach po 20 bajtów.

| Komenda | Kiedy |
|---|---|
| `JL:x,y` | ruch lewego joysticka, `x` i `y` od -100 do 100 (do góry = `+y`) |
| `JP:x,y` | ruch prawego joysticka, jak wyżej |
| `START` / `STOP` | przełączenie stanu pracy |
| `F1_ON` / `F1_OFF` | naciśnięcie / puszczenie F1 (tak samo `F2`, `F3`) |
| `LIGHT_ON` / `LIGHT_OFF` | przełączenie świateł |
| `HORN_ON` / `HORN_OFF` | naciśnięcie / puszczenie klaksonu |

Pozycje joysticków są wysyłane co najwyżej co 50 ms i tylko wtedy, gdy się zmieniły.
Po (ponownym) połączeniu aplikacja wysyła od razu stan świateł, START/STOP
i pozycje joysticków.

## Wideo (RTSP)

Adres strumienia wpisz w **Setup → Video (RTSP) → Apply**, np.:

```
rtsp://192.168.1.102:8554/stream
```

Obraz odtwarza Qt Multimedia (backend FFmpeg), więc działa każdy strumień RTSP z H.264:
kamera IP, MediaMTX, GStreamer itp.

Do testów bez modelu jest prosty serwer RTSP w Pythonie, który wysyła obraz z kamery
komputera albo obraz testowy: [rtsp_server/](rtsp_server/README.md).

## Budowanie

Wymagania:

- Qt 6.8 lub nowszy z modułami **Qt Quick**, **Qt Svg**, **Qt Bluetooth** i **Qt Multimedia**
- CMake 3.16+ i Ninja (instalowane z Qt)
- Android: Android SDK i NDK, **JDK 17**, Qt dla Androida (`arm64-v8a`)

Najprościej otworzyć `CMakeLists.txt` w Qt Creatorze i wybrać kit Androida albo Desktop.

Z linii poleceń (PowerShell, Android, przykładowe ścieżki):

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot"
C:\Qt\6.8.3\android_arm64_v8a\bin\qt-cmake.bat -S . -B build-android -G Ninja `
    -DCMAKE_BUILD_TYPE=Debug `
    -DANDROID_SDK_ROOT=$env:LOCALAPPDATA\Android\Sdk `
    -DQT_HOST_PATH=C:\Qt\6.8.3\mingw_64
cmake --build build-android --target apk
adb install -r build-android\android-build\build\outputs\apk\debug\android-build-debug.apk
```

Uwagi:

- `android/` zawiera tylko manifest i ikony. Pliki Gradle dostarcza Qt w wersji, którą budujesz.
- Ninja nie zauważa nowych plików w `android/res`. Po dodaniu zasobów usuń
  `build-android/android-build/appX1.apk`, żeby APK się przebudował.
- Na Androidzie aplikacja przy pierwszym uruchomieniu prosi o dostęp do Bluetooth
  (i lokalizacji na Androidzie 11 i starszych, bez której skanowanie BLE nie działa).

## Struktura projektu

| Plik / katalog | Zawartość |
|---|---|
| `main.cpp` | start aplikacji, blokada orientacji poziomej na Androidzie |
| `blelink.h`, `blelink.cpp` | `BleLink` – skanowanie, łączenie i wysyłanie komend przez BLE UART |
| `Main.qml` | główny ekran: joysticki, wideo z telemetrią, pasek przycisków |
| `Joystick.qml` | joystick z obsługą wielu palców |
| `VideoView.qml` | odtwarzacz RTSP z automatycznym ponownym łączeniem |
| `SetupDialog.qml` | okno ustawień: Bluetooth i adres RTSP |
| `Theme.qml` | paleta kolorów aplikacji (z ikony) |
| `icons/` | ikony przycisków (SVG), logo i grafiki źródłowe ikony |
| `android/` | manifest i ikona aplikacji |
| `rtsp_server/` | testowy serwer RTSP w Pythonie |
