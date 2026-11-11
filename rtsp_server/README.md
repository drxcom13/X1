# X1 RTSP server

A simple Python RTSP server for the X1 app. It captures video from a local
camera (or generates a test pattern), encodes it to H.264 and sends it over RTP.

```
rtsp://<computer-IP-address>:8554/stream
```

Enter the stream address in the X1 app: **Setup → Video (RTSP) → Apply**.

## Installation

Requires Python 3.10 or newer.

The commands below are for **PowerShell on Windows**. Run all of them in the
`rtsp_server` folder, where `.venv` and the scripts live. Paths start with `.\`
because PowerShell does not run a program from the current folder without that prefix.

```powershell
cd rtsp_server
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
```

On Linux and Raspberry Pi (bash), use `.venv/bin/python` instead of `.\.venv\Scripts\python`.

## Running

Camera 0 (default):

```powershell
.\.venv\Scripts\python rtsp_server.py
```

Test pattern (no camera needed):

```powershell
.\.venv\Scripts\python rtsp_server.py --test-pattern
```

From the repository root, without changing folders:

```powershell
.\rtsp_server\.venv\Scripts\python .\rtsp_server\rtsp_server.py
```

Stop the server with Ctrl+C.

Options:

| Option | Default | Description |
|---|---|---|
| `--camera N` | `0` | camera index |
| `--test-pattern` | – | colour bars with a moving block and a clock instead of a camera |
| `--width`, `--height` | `640`, `480` | resolution |
| `--fps` | `25` | frames per second |
| `--bitrate` | `1500k` | e.g. `800k`, `2M` |
| `--port` | `8554` | RTSP port |
| `--host` | `0.0.0.0` | address to listen on |
| `-v` | – | verbose log |

On start-up the server prints the addresses where the stream is available.

## Checking the stream

In a second PowerShell window, in the `rtsp_server` folder, while the server is running:

```powershell
.\.venv\Scripts\python check_stream.py rtsp://127.0.0.1:8554/stream
.\.venv\Scripts\python check_stream.py rtsp://127.0.0.1:8554/stream --tcp
```

You can also open the address in VLC: *Media → Open Network Stream*.

## How it works

- **Video:** OpenCV (`cv2.VideoCapture`) reads frames from the camera. On Windows it tries
  DirectShow first, then Media Foundation, and uses the camera only once it delivers a frame.
- **Encoding:** PyAV encodes frames to H.264 with low-latency settings: baseline profile,
  no B-frames, one keyframe per second, SPS/PPS repeated with every keyframe.
  The server tries the `libx264`, `libopenh264` and `h264_mf` encoders in that order.
- **RTSP:** supports `OPTIONS`, `DESCRIBE` (SDP), `SETUP`, `PLAY`, `PAUSE`, `TEARDOWN`
  and `GET_PARAMETER`. It answers on any path, so `/stream` is just a convention.
- **RTP:** H.264 packetization per RFC 6184 (single NAL units and FU-A), over UDP
  or interleaved in the TCP connection. Every new client starts at a keyframe.
  Multiple clients are supported at once.

## Notes

- **Windows Firewall:** the tablet cannot connect unless incoming connections on port 8554
  are allowed. Set the network to *Private* and allow Python when Windows asks, or add a rule
  in PowerShell run as administrator:

  ```powershell
  New-NetFirewallRule -DisplayName "X1 RTSP server (TCP 8554)" -Direction Inbound -Protocol TCP -LocalPort 8554 -Action Allow -Profile Private -RemoteAddress LocalSubnet
  ```

- **Camera access (Windows):** if the server reports `Cannot open camera` while the Camera
  app shows a picture, go to *Settings → Privacy & security → Camera* and turn on access for
  **Python**. Python from the Microsoft Store is listed there as a separate app with its own
  permission. Also check the laptop's camera privacy key and that no other app is using the camera.
- **Limitations:** no RTCP and no authentication. This is a testing tool for the local network,
  not for public streaming.
- **Production setup:** [MediaMTX](https://github.com/bluenviron/mediamtx) with FFmpeg
  or the GStreamer `rtsp-server`.
