#!/usr/bin/env python3
"""Serve an exported web build on localhost.

Deliberately small. Two things a bare `python -m http.server` does not guarantee:

  * `application/wasm` for `.wasm`. Python's `mimetypes` reads the Windows registry,
    so the guess varies by machine (it happens to be correct on this one). A wrong
    type costs streaming compilation - slow start, not a failure - so we pin it.
  * Binding 127.0.0.1 rather than 0.0.0.0. The build needs a *secure context*
    (W3C Secure Contexts 3.1): localhost and 127.0.0.1 qualify without TLS, a LAN
    IP does not. Binding the loopback interface makes the wrong URL unreachable
    instead of subtly broken.

No COOP/COEP headers are sent, and none are needed: the Web preset exports with
`variant/thread_support=false`, and in the shipped `godot.js` the SharedArrayBuffer
and cross-origin-isolation checks all sit inside `if (supportsThreads)`. The
"python cannot serve Godot web builds" folklore is a threads-era fact. If threads
are ever turned on, this script must grow the two headers.
"""

import argparse
import http.server
import os
import webbrowser

EXTRA_TYPES = {
    ".wasm": "application/wasm",
    ".js": "text/javascript",
    ".pck": "application/octet-stream",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        if ext in EXTRA_TYPES:
            return EXTRA_TYPES[ext]
        return super().guess_type(path)

    def end_headers(self):
        # The build is re-exported constantly; a cached 39 MB wasm is a debugging trap.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="directory holding index.html")
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()

    os.chdir(args.root)
    url = f"http://127.0.0.1:{args.port}/index.html"
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Serving {os.getcwd()} at {url}  (Ctrl-C to stop)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
