#!/usr/bin/env python3
"""Minimal RTSP server: local camera (or test pattern) -> H.264 -> RTP.

Serves one live stream to any number of clients:

    rtsp://<this-pc-ip>:8554/stream

Transports: RTP over UDP (default for most players) and RTP interleaved
over the RTSP TCP connection (e.g. "rtsp_transport=tcp" in FFmpeg).

Dependencies: opencv-python (camera, test pattern), av (H.264 encoder).
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import fractions
import logging
import random
import socket
import struct
import sys
import threading
import time
from dataclasses import dataclass, field

import av
import cv2
import numpy as np

log = logging.getLogger("rtsp")

RTP_CLOCK = 90_000          # H.264 RTP clock rate
RTP_PAYLOAD_TYPE = 96       # dynamic payload type announced in SDP
RTP_MAX_PAYLOAD = 1400      # keep packets below a typical 1500-byte MTU
TCP_MAX_BUFFER = 2_000_000  # drop frames for TCP clients that cannot keep up


# --------------------------------------------------------------------------
# H.264 helpers
# --------------------------------------------------------------------------

def split_annexb(data: bytes) -> list[bytes]:
    """Split an Annex B byte stream into NAL units (start codes removed)."""
    starts = []
    i = 0
    while True:
        j = data.find(b"\x00\x00\x01", i)
        if j < 0:
            break
        starts.append(j + 3)
        i = j + 3
    nals = []
    for k, s in enumerate(starts):
        e = starts[k + 1] - 3 if k + 1 < len(starts) else len(data)
        nal = data[s:e].rstrip(b"\x00")  # drop the leading 0 of a 4-byte start code
        if nal:
            nals.append(nal)
    return nals


def nal_type(nal: bytes) -> int:
    return nal[0] & 0x1F


def packetize(nal: bytes, last_in_frame: bool):
    """Yield (payload, marker) RTP payloads for one NAL unit (RFC 6184)."""
    if len(nal) <= RTP_MAX_PAYLOAD:
        yield nal, last_in_frame
        return
    # FU-A fragmentation
    header = nal[0]
    fu_indicator = (header & 0xE0) | 28
    ntype = header & 0x1F
    data = nal[1:]
    chunk = RTP_MAX_PAYLOAD - 2
    for off in range(0, len(data), chunk):
        start = off == 0
        end = off + chunk >= len(data)
        fu_header = (0x80 if start else 0) | (0x40 if end else 0) | ntype
        yield bytes([fu_indicator, fu_header]) + data[off:off + chunk], end and last_in_frame


@dataclass
class AccessUnit:
    nals: list[bytes]
    timestamp: int          # 90 kHz clock, relative to stream start
    keyframe: bool


# --------------------------------------------------------------------------
# Video source + encoder (runs in its own thread)
# --------------------------------------------------------------------------

def open_encoder(width: int, height: int, fps: int, bitrate: int) -> av.CodecContext:
    """Create a low-latency H.264 encoder, trying the encoders PyAV may ship."""
    candidates = [
        ("libx264", {"preset": "ultrafast", "tune": "zerolatency",
                     "profile": "baseline", "x264-params": "repeat-headers=1"}),
        ("libopenh264", {"profile": "constrained_baseline"}),
        ("h264_mf", {"rate_control": "cbr", "scenario": "live_streaming"}),
    ]
    last_error = None
    for name, options in candidates:
        try:
            ctx = av.CodecContext.create(name, "w")
            ctx.width = width
            ctx.height = height
            ctx.pix_fmt = "yuv420p"
            ctx.time_base = fractions.Fraction(1, fps)
            ctx.framerate = fractions.Fraction(fps, 1)
            ctx.bit_rate = bitrate
            ctx.gop_size = fps          # one keyframe per second: new clients join fast
            ctx.max_b_frames = 0        # no reordering -> lower latency
            ctx.options = options
            ctx.open()
            log.info("H.264 encoder: %s", name)
            return ctx
        except Exception as exc:  # encoder not available in this FFmpeg build
            last_error = exc
            log.debug("encoder %s unavailable: %s", name, exc)
    raise RuntimeError(f"No usable H.264 encoder found ({last_error})")


class VideoSource(threading.Thread):
    """Captures frames, encodes them and hands access units to a callback."""

    def __init__(self, args, on_access_unit):
        super().__init__(daemon=True, name="video")
        self.args = args
        self.on_access_unit = on_access_unit
        self.stop_event = threading.Event()
        self.sps: bytes | None = None
        self.pps: bytes | None = None
        self.error: str | None = None
        self.ready = threading.Event()

    def _open_camera(self):
        if sys.platform == "win32":
            backends = [("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF)]
        else:
            backends = [("ANY", cv2.CAP_ANY)]
        for name, backend in backends:
            cap = cv2.VideoCapture(self.args.camera, backend)
            if not cap.isOpened():
                log.debug("camera %d: %s backend cannot open it", self.args.camera, name)
                cap.release()
                continue
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.args.width)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.args.height)
            cap.set(cv2.CAP_PROP_FPS, self.args.fps)
            ok, _ = cap.read()   # some drivers open fine but never deliver frames
            if not ok:
                log.debug("camera %d: %s backend opened it but delivers no frames",
                          self.args.camera, name)
                cap.release()
                continue
            log.info("camera %d opened via %s", self.args.camera, name)
            return cap
        hint = ""
        if sys.platform == "win32":
            hint = ("; check Settings > Privacy & security > Camera: camera access must be "
                    "on for Python (the Microsoft Store Python is listed there as its own "
                    "app). Also check that no other app (Zoom, Teams) is using the camera "
                    "and that the laptop's camera privacy key/shutter is off. "
                    "Use --test-pattern to run without a camera")
        raise RuntimeError(f"Cannot open camera {self.args.camera}{hint}")

    def _test_frame(self, n: int) -> np.ndarray:
        w, h = self.args.width, self.args.height
        img = np.zeros((h, w, 3), np.uint8)
        # colour bars
        colors = [(255, 255, 255), (0, 255, 255), (255, 255, 0), (0, 255, 0),
                  (255, 0, 255), (0, 0, 255), (255, 0, 0), (40, 40, 40)]
        bw = w // len(colors)
        for i, c in enumerate(colors):
            img[:, i * bw:(i + 1) * bw] = c
        # moving block shows that the stream is live
        x = (n * 8) % max(1, w - 60)
        cv2.rectangle(img, (x, h // 2 - 30), (x + 60, h // 2 + 30), (0, 0, 0), -1)
        cv2.putText(img, time.strftime("%H:%M:%S") + f"  #{n}", (20, h - 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 3, cv2.LINE_AA)
        cv2.putText(img, time.strftime("%H:%M:%S") + f"  #{n}", (20, h - 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 1, cv2.LINE_AA)
        return img

    def run(self):
        cap = None
        try:
            if not self.args.test_pattern:
                cap = self._open_camera()
            encoder = open_encoder(self.args.width, self.args.height,
                                   self.args.fps, self.args.bitrate)
        except Exception as exc:
            self.error = str(exc)
            self.ready.set()
            return
        self.ready.set()

        t0 = time.monotonic()
        frame_interval = 1.0 / self.args.fps
        next_frame = t0
        n = 0
        while not self.stop_event.is_set():
            if cap is not None:
                ok, img = cap.read()
                if not ok:
                    log.warning("camera read failed, retrying")
                    time.sleep(0.1)
                    continue
                if img.shape[1] != self.args.width or img.shape[0] != self.args.height:
                    img = cv2.resize(img, (self.args.width, self.args.height))
            else:
                # pace the test pattern to the requested frame rate
                next_frame += frame_interval
                delay = next_frame - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                img = self._test_frame(n)

            timestamp = int((time.monotonic() - t0) * RTP_CLOCK)
            frame = av.VideoFrame.from_ndarray(img, format="bgr24").reformat(format="yuv420p")
            frame.pts = n
            n += 1
            for packet in encoder.encode(frame):
                nals = [x for x in split_annexb(bytes(packet)) if nal_type(x) != 9]  # drop AUD
                if not nals:
                    continue
                for nal in nals:
                    if nal_type(nal) == 7:
                        self.sps = nal
                    elif nal_type(nal) == 8:
                        self.pps = nal
                self.on_access_unit(AccessUnit(nals, timestamp, packet.is_keyframe))

        if cap is not None:
            cap.release()


# --------------------------------------------------------------------------
# RTSP / RTP
# --------------------------------------------------------------------------

@dataclass
class RtpSession:
    session_id: str
    peer_ip: str
    tcp_writer: asyncio.StreamWriter | None = None   # interleaved TCP
    tcp_channel: int = 0
    udp_socket: socket.socket | None = None          # RTP over UDP
    udp_rtcp_socket: socket.socket | None = None
    udp_addr: tuple[str, int] | None = None
    playing: bool = False
    need_keyframe: bool = True
    ssrc: int = field(default_factory=lambda: random.getrandbits(32))
    seq: int = field(default_factory=lambda: random.getrandbits(16))
    ts_offset: int = field(default_factory=lambda: random.getrandbits(32))

    def send(self, au: AccessUnit):
        if not self.playing:
            return
        if self.need_keyframe:
            if not au.keyframe:
                return
            self.need_keyframe = False
        if self.tcp_writer is not None:
            if self.tcp_writer.transport.get_write_buffer_size() > TCP_MAX_BUFFER:
                self.need_keyframe = True   # client too slow: skip until next keyframe
                return
        ts = (self.ts_offset + au.timestamp) & 0xFFFFFFFF
        for i, nal in enumerate(au.nals):
            for payload, marker in packetize(nal, i == len(au.nals) - 1):
                header = struct.pack("!BBHII", 0x80, (0x80 if marker else 0) | RTP_PAYLOAD_TYPE,
                                     self.seq, ts, self.ssrc)
                self.seq = (self.seq + 1) & 0xFFFF
                packet = header + payload
                if self.tcp_writer is not None:
                    self.tcp_writer.write(b"$" + bytes([self.tcp_channel])
                                          + struct.pack("!H", len(packet)) + packet)
                elif self.udp_socket is not None and self.udp_addr is not None:
                    try:
                        self.udp_socket.sendto(packet, self.udp_addr)
                    except OSError as exc:
                        log.debug("UDP send failed: %s", exc)

    def close(self):
        self.playing = False
        for s in (self.udp_socket, self.udp_rtcp_socket):
            if s is not None:
                s.close()
        self.udp_socket = self.udp_rtcp_socket = None


class RtspServer:
    def __init__(self, args):
        self.args = args
        self.sessions: dict[str, RtpSession] = {}
        self.loop: asyncio.AbstractEventLoop | None = None
        self.source = VideoSource(args, self._on_access_unit_threadsafe)

    # called from the video thread
    def _on_access_unit_threadsafe(self, au: AccessUnit):
        if self.loop is not None:
            self.loop.call_soon_threadsafe(self._broadcast, au)

    def _broadcast(self, au: AccessUnit):
        for session in list(self.sessions.values()):
            session.send(au)

    def _sdp(self, server_ip: str) -> str:
        fmtp = "packetization-mode=1"
        sps, pps = self.source.sps, self.source.pps
        if sps and pps:
            fmtp += f";profile-level-id={sps[1:4].hex()}"
            fmtp += (";sprop-parameter-sets="
                     f"{base64.b64encode(sps).decode()},{base64.b64encode(pps).decode()}")
        return (
            "v=0\r\n"
            f"o=- {random.getrandbits(31)} 1 IN IP4 {server_ip}\r\n"
            "s=X1 camera\r\n"
            "c=IN IP4 0.0.0.0\r\n"
            "t=0 0\r\n"
            "a=control:*\r\n"
            f"m=video 0 RTP/AVP {RTP_PAYLOAD_TYPE}\r\n"
            f"a=rtpmap:{RTP_PAYLOAD_TYPE} H264/{RTP_CLOCK}\r\n"
            f"a=fmtp:{RTP_PAYLOAD_TYPE} {fmtp}\r\n"
            f"a=framerate:{self.args.fps}\r\n"
            "a=control:track0\r\n"
        )

    @staticmethod
    def _bind_udp_pair(ip: str) -> tuple[socket.socket, socket.socket]:
        """Bind an even/odd UDP port pair for RTP/RTCP."""
        for _ in range(50):
            port = random.randrange(20000, 60000, 2)
            rtp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            rtcp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                rtp.bind((ip, port))
                rtcp.bind((ip, port + 1))
                rtp.setblocking(False)
                rtcp.setblocking(False)
                return rtp, rtcp
            except OSError:
                rtp.close()
                rtcp.close()
        raise OSError("no free UDP port pair")

    async def _read_request(self, reader: asyncio.StreamReader):
        """Read one RTSP request; skip interleaved binary frames (RTCP from client)."""
        while True:
            first = await reader.readexactly(1)
            if first == b"$":
                hdr = await reader.readexactly(3)
                await reader.readexactly(struct.unpack("!H", hdr[1:3])[0])
                continue
            break
        head = first + await reader.readuntil(b"\r\n\r\n")
        lines = head.decode("utf-8", "replace").split("\r\n")
        method, url, _ = (lines[0].split(" ") + ["", "", ""])[:3]
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        length = int(headers.get("content-length", "0") or 0)
        if length:
            await reader.readexactly(length)
        return method.upper(), url, headers

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        peer_ip = writer.get_extra_info("peername")[0]
        server_ip = writer.get_extra_info("sockname")[0]
        log.info("client connected: %s", peer_ip)
        my_sessions: list[str] = []

        def reply(cseq, status="200 OK", extra: dict | None = None, body: str = ""):
            out = [f"RTSP/1.0 {status}", f"CSeq: {cseq}", "Server: X1-rtsp/1.0"]
            for k, v in (extra or {}).items():
                out.append(f"{k}: {v}")
            if body:
                out.append(f"Content-Length: {len(body.encode())}")
            writer.write(("\r\n".join(out) + "\r\n\r\n" + body).encode())

        try:
            while True:
                method, url, headers = await self._read_request(reader)
                cseq = headers.get("cseq", "0")
                session_id = headers.get("session", "").split(";")[0]
                log.debug("%s %s %s", peer_ip, method, url)

                if method == "OPTIONS":
                    reply(cseq, extra={"Public": "OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, "
                                                 "TEARDOWN, GET_PARAMETER, SET_PARAMETER"})

                elif method == "DESCRIBE":
                    body = self._sdp(server_ip)
                    base = url if url.endswith("/") else url + "/"
                    reply(cseq, extra={"Content-Base": base,
                                       "Content-Type": "application/sdp"}, body=body)

                elif method == "SETUP":
                    transport = headers.get("transport", "")
                    session = self.sessions.get(session_id) or RtpSession(
                        session_id=f"{random.getrandbits(32):08X}", peer_ip=peer_ip)
                    if "RTP/AVP/TCP" in transport.upper():
                        channel = 0
                        for part in transport.split(";"):
                            if part.startswith("interleaved="):
                                channel = int(part.split("=")[1].split("-")[0])
                        session.tcp_writer = writer
                        session.tcp_channel = channel
                        resp_transport = (f"RTP/AVP/TCP;unicast;interleaved={channel}-{channel + 1};"
                                          f"ssrc={session.ssrc:08X}")
                    else:
                        client_port = None
                        for part in transport.split(";"):
                            if part.startswith("client_port="):
                                client_port = int(part.split("=")[1].split("-")[0])
                        if client_port is None:
                            reply(cseq, "461 Unsupported Transport")
                            continue
                        rtp, rtcp = self._bind_udp_pair(server_ip)
                        session.udp_socket, session.udp_rtcp_socket = rtp, rtcp
                        session.udp_addr = (peer_ip, client_port)
                        sport = rtp.getsockname()[1]
                        resp_transport = (f"RTP/AVP;unicast;client_port={client_port}-{client_port + 1};"
                                          f"server_port={sport}-{sport + 1};ssrc={session.ssrc:08X}")
                    self.sessions[session.session_id] = session
                    if session.session_id not in my_sessions:
                        my_sessions.append(session.session_id)
                    reply(cseq, extra={"Transport": resp_transport,
                                       "Session": f"{session.session_id};timeout=60"})

                elif method == "PLAY":
                    session = self.sessions.get(session_id)
                    if session is None:
                        reply(cseq, "454 Session Not Found")
                        continue
                    session.playing = True
                    session.need_keyframe = True
                    base = url.rstrip("/")
                    reply(cseq, extra={"Session": session.session_id,
                                       "Range": "npt=0.000-",
                                       "RTP-Info": f"url={base}/track0;seq={session.seq};"
                                                   f"rtptime={session.ts_offset & 0xFFFFFFFF}"})
                    log.info("streaming to %s (%s)", peer_ip,
                             "TCP" if session.tcp_writer else f"UDP {session.udp_addr[1]}")

                elif method == "PAUSE":
                    session = self.sessions.get(session_id)
                    if session:
                        session.playing = False
                    reply(cseq, extra={"Session": session_id})

                elif method == "TEARDOWN":
                    session = self.sessions.pop(session_id, None)
                    if session:
                        session.close()
                    reply(cseq, extra={"Session": session_id})

                elif method in ("GET_PARAMETER", "SET_PARAMETER"):
                    reply(cseq, extra={"Session": session_id} if session_id else None)

                else:
                    reply(cseq, "501 Not Implemented")

                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            for sid in my_sessions:
                session = self.sessions.pop(sid, None)
                if session:
                    session.close()
            writer.close()
            log.info("client disconnected: %s", peer_ip)

    async def run(self):
        self.loop = asyncio.get_running_loop()
        self.source.start()
        await asyncio.to_thread(self.source.ready.wait)
        if self.source.error:
            raise RuntimeError(self.source.error)

        server = await asyncio.start_server(self.handle_client, self.args.host, self.args.port)
        ips = local_ips() if self.args.host in ("0.0.0.0", "") else [self.args.host]
        for ip in ips:
            log.info("RTSP stream: rtsp://%s:%d/%s", ip, self.args.port, self.args.path)
        async with server:
            await server.serve_forever()


def local_ips() -> list[str]:
    """Best-effort list of this machine's IPv4 addresses (no traffic is sent)."""
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))   # UDP connect only selects a route
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    ips.discard("0.0.0.0")
    return sorted(ips) or ["127.0.0.1"]


def parse_bitrate(text: str) -> int:
    text = text.lower().strip()
    if text.endswith("k"):
        return int(float(text[:-1]) * 1000)
    if text.endswith("m"):
        return int(float(text[:-1]) * 1_000_000)
    return int(text)


def main():
    p = argparse.ArgumentParser(description="Simple RTSP server streaming a local camera (H.264).")
    p.add_argument("--camera", type=int, default=0, help="camera index (default 0)")
    p.add_argument("--test-pattern", action="store_true", help="stream a test pattern instead of a camera")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=480)
    p.add_argument("--fps", type=int, default=25)
    p.add_argument("--bitrate", type=parse_bitrate, default="1500k", help="e.g. 800k, 2M")
    p.add_argument("--host", default="0.0.0.0", help="address to listen on")
    p.add_argument("--port", type=int, default=8554)
    p.add_argument("--path", default="stream", help="path shown in the printed URL")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    try:
        asyncio.run(RtspServer(args).run())
    except KeyboardInterrupt:
        pass
    except RuntimeError as exc:
        log.error("%s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
