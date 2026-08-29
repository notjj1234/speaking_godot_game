#!/usr/bin/env python3
"""Serve the Godot web export over HTTPS so the browser has a Secure Context."""

from __future__ import annotations

import http.server
import os
import socket
import ssl
import sys

PORT = int(os.environ.get("PORT", "8443"))
HOST = os.environ.get("HOST", "0.0.0.0")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
CERT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web-certs", "cert.pem")
KEY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web-certs", "key.pem")


def _local_ipv4_addresses() -> list[str]:
	addrs: set[str] = set()
	try:
		with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
			sock.connect(("8.8.8.8", 80))
			addrs.add(sock.getsockname()[0])
	except OSError:
		pass
	try:
		for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
			ip = info[4][0]
			if not ip.startswith("127."):
				addrs.add(ip)
	except OSError:
		pass
	return sorted(addrs)


def main() -> int:
	if not os.path.isdir(ROOT):
		print(f"Missing web build folder: {ROOT}", file=sys.stderr)
		return 1
	if not os.path.isfile(CERT) or not os.path.isfile(KEY):
		print(f"Missing certs. Expected:\n  {CERT}\n  {KEY}", file=sys.stderr)
		return 1

	os.chdir(ROOT)
	handler = http.server.SimpleHTTPRequestHandler
	httpd = http.server.HTTPServer((HOST, PORT), handler)
	context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
	context.load_cert_chain(certfile=CERT, keyfile=KEY)
	httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

	print("Serving Godot web build with HTTPS")
	print(f"On this Mac:  https://127.0.0.1:{PORT}/")
	lan_ips = _local_ipv4_addresses()
	if lan_ips:
		print("On your phone (same Wi‑Fi):")
		for ip in lan_ips:
			print(f"  https://{ip}:{PORT}/")
	else:
		print("Could not detect LAN IP. Find your Mac's Wi‑Fi address in System Settings → Network.")
		print(f"Then open: https://<your-mac-ip>:{PORT}/")
	print("If the browser warns about the certificate, continue anyway (self-signed).")
	httpd.serve_forever()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
