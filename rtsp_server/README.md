# X1 RTSP server

Prosty serwer RTSP w Pythonie dla aplikacji X1. Pobiera obraz z lokalnej
kamery (albo generuje obraz testowy), koduje go do H.264 i wysyła przez RTP.

```
rtsp://<adres-IP-komputera>:8554/stream
```

Adres strumienia wpisz w aplikacji X1: **Setup → Video (RTSP) → Apply**.

## Instalacja

Wymaga Pythona 3.10 lub nowszego.

Komendy poniżej są dla **PowerShella w Windows**. Wszystkie uruchamiaj w katalogu
`rtsp_server`, bo tam jest `.venv` i skrypty. Ścieżka zaczyna się od `.\`, bo PowerShell
nie uruchamia programu z bieżącego katalogu bez tego prefiksu.

```powershell
cd C:\Users\User\Documents\X1\rtsp_server
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
```

Na Linuksie i Raspberry Pi (bash) użyj `.venv/bin/python` zamiast `.\.venv\Scripts\python`.

## Uruchomienie

Kamera 0 (domyślna):

```powershell
.\.venv\Scripts\python rtsp_server.py
```

Obraz testowy (bez kamery):

```powershell
.\.venv\Scripts\python rtsp_server.py --test-pattern
```

Z katalogu `X1`, bez zmiany katalogu:

```powershell
.\rtsp_server\.venv\Scripts\python .\rtsp_server\rtsp_server.py
```

Serwer zatrzymujesz przez Ctrl+C.

Opcje:

| Opcja | Domyślnie | Opis |
|---|---|---|
| `--camera N` | `0` | numer kamery |
| `--test-pattern` | – | paski testowe z ruchomym blokiem i zegarem zamiast kamery |
| `--width`, `--height` | `640`, `480` | rozdzielczość |
| `--fps` | `25` | klatki na sekundę |
| `--bitrate` | `1500k` | np. `800k`, `2M` |
| `--port` | `8554` | port RTSP |
| `--host` | `0.0.0.0` | adres nasłuchu |
| `-v` | – | szczegółowy log |

Po starcie serwer wypisuje adresy, pod którymi strumień jest dostępny.

## Sprawdzenie strumienia

W drugim oknie PowerShella, w katalogu `rtsp_server`, gdy serwer działa:

```powershell
.\.venv\Scripts\python check_stream.py rtsp://127.0.0.1:8554/stream
.\.venv\Scripts\python check_stream.py rtsp://127.0.0.1:8554/stream --tcp
```

Można też otworzyć adres w VLC: *Media → Otwórz strumień sieciowy*.

## Jak to działa

- **Obraz:** OpenCV (`cv2.VideoCapture`) czyta klatki z kamery. Na Windows używa DirectShow.
- **Kodowanie:** PyAV koduje klatki do H.264 z ustawieniami pod małe opóźnienie: baseline,
  bez B-klatek, klatka kluczowa co sekundę, SPS/PPS powtarzane przy każdej klatce kluczowej.
  Serwer próbuje po kolei enkoderów `libx264`, `libopenh264` i `h264_mf`.
- **RTSP:** obsługuje `OPTIONS`, `DESCRIBE` (SDP), `SETUP`, `PLAY`, `PAUSE`, `TEARDOWN`
  i `GET_PARAMETER`. Odpowiada na każdą ścieżkę, więc `/stream` jest tylko umowna.
- **RTP:** pakietyzacja H.264 zgodna z RFC 6184 (pojedyncze NAL i FU-A), przez UDP
  albo przeplatana w połączeniu TCP. Każdy nowy klient zaczyna od klatki kluczowej.
  Obsługiwanych jest wielu klientów naraz.

## Uwagi

- **Zapora Windows:** przy pierwszym uruchomieniu Windows może zapytać, czy Python może
  przyjmować połączenia. Zezwól w sieci prywatnej, inaczej tablet nie połączy się z serwerem.
- **Dostęp do kamery (Windows):** jeśli serwer zgłasza `Cannot open camera`, a aplikacja
  Aparat pokazuje obraz, wejdź w *Ustawienia → Prywatność i zabezpieczenia → Kamera* i włącz
  dostęp dla **Python**. Python ze Sklepu Microsoft jest tam osobną aplikacją z własną zgodą.
  Sprawdź też klawisz prywatności kamery na laptopie i czy kamery nie używa inna aplikacja.
- **Ograniczenia:** brak RTCP i autoryzacji. To narzędzie do testów w sieci lokalnej,
  nie do publicznego udostępniania.
- **Rozwiązanie produkcyjne:** [MediaMTX](https://github.com/bluenviron/mediamtx) z FFmpeg
  albo GStreamer `rtsp-server`.
