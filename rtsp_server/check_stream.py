#!/usr/bin/env python3
"""Connect to an RTSP URL, decode a few frames and report what arrived.

    python check_stream.py rtsp://127.0.0.1:8554/stream [--tcp] [--frames 50]
"""
import argparse
import time

import av


def main():
    p = argparse.ArgumentParser()
    p.add_argument("url")
    p.add_argument("--tcp", action="store_true", help="use RTP over TCP instead of UDP")
    p.add_argument("--frames", type=int, default=50)
    args = p.parse_args()

    options = {"rtsp_transport": "tcp" if args.tcp else "udp", "fflags": "nobuffer"}
    t0 = time.monotonic()
    with av.open(args.url, options=options, timeout=10) as container:
        stream = container.streams.video[0]
        print(f"codec={stream.codec_context.name} size={stream.codec_context.width}x"
              f"{stream.codec_context.height}")
        n = 0
        for frame in container.decode(stream):
            if n == 0:
                print(f"first frame after {time.monotonic() - t0:.2f}s")
            n += 1
            if n >= args.frames:
                break
    dt = time.monotonic() - t0
    print(f"decoded {n} frames in {dt:.2f}s")


if __name__ == "__main__":
    main()
