#!/usr/bin/env python3
"""Serve the Godot web export over HTTPS so a phone gets a Secure Context.

    python3 tools/web/play_in_browser.py --phone   # export, then run this
    python3 build/serve_https.py                   # serve the last export
    PORT=9000 python3 build/serve_https.py

Browsers only allow the microphone (Web Speech API) in a secure context. A phone
reaches this Mac by LAN IP, which is not localhost, so the server must speak HTTPS.
It generates its own certificate into build/phone-certs/ (gitignored) with the
addresses your phone actually uses, serves it at /cert.crt so the phone can trust
it, and prints the steps for both iOS and Android.

Ctrl+C stops the server.
"""

from __future__ import annotations

import http.server
import os
import re
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import urllib.request

PORT = int(os.environ.get("PORT", "8443"))
HOST = os.environ.get("HOST", "0.0.0.0")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
CERT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phone-certs")
FALLBACK_CERT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web-certs")
# Extra mounts from the repo (besides the web build root):
#   /extras/ -> web/extras/   vendored runtime assets (pronunciation spike model + JS)
#   /tools/  -> tools/        standalone tool pages (pronunciation spike)
REPO_ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MOUNTS = {
	"/extras/": os.path.realpath(os.path.join(REPO_ROOT, "web", "extras")),
	"/tools/": os.path.realpath(os.path.join(REPO_ROOT, "tools")),
}

# Set in main(); the handler serves it at /cert.crt.
_CERT_FILE = ""


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


def _mdns_name() -> str | None:
	"""The name a phone can use instead of the IP on the same Wi-Fi (<name>.local)."""
	name = ""
	try:
		out = subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True,
		                     text=True, timeout=5)
		name = out.stdout.strip()
	except (OSError, subprocess.TimeoutExpired):
		pass
	if not name:
		name = socket.gethostname().split(".")[0]
	name = re.sub(r"[^A-Za-z0-9-]", "-", name).strip("-")
	return f"{name}.local" if name else None


def _required_names(ips: list[str], mdns: str | None) -> set[str]:
	names = {"dns:localhost", "ip:127.0.0.1"}
	if mdns:
		names.add(f"dns:{mdns.lower()}")
	for ip in ips:
		names.add(f"ip:{ip}")
	return names


def _cert_names(cert_path: str) -> set[str]:
	"""Names a certificate covers, normalised like _required_names()."""
	if not os.path.isfile(cert_path):
		return set()
	text = ""
	for extra in (["-ext", "subjectAltName"], ["-text"]):
		try:
			out = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", *extra],
			                     capture_output=True, text=True, timeout=10)
		except (OSError, subprocess.TimeoutExpired):
			return set()
		if "Subject Alternative Name" in out.stdout:
			text = out.stdout
			break
	if not text:
		return set()
	tail = text.split("Subject Alternative Name", 1)[1]
	names = {f"dns:{m.lower()}" for m in re.findall(r"DNS:([^,\s]+)", tail)}
	names |= {f"ip:{m}" for m in re.findall(r"IP Address:([^,\s]+)", tail)}
	return names


def _cert_unexpired(cert_path: str) -> bool:
	try:
		out = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"],
		                     capture_output=True, text=True, timeout=10)
		return out.returncode == 0
	except (OSError, subprocess.TimeoutExpired):
		return False


_CERT_CONFIG = """[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = Loqui Quest Local

[v3]
subjectAltName = @alt
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash

[alt]
{alt}
"""


def _generate_cert(cert_dir: str, names: set[str]) -> tuple[str, str]:
	"""Write a self-signed cert naming exactly `names`. Returns (cert, key) paths."""
	os.makedirs(cert_dir, exist_ok=True)
	cert_path = os.path.join(cert_dir, "cert.pem")
	key_path = os.path.join(cert_dir, "key.pem")
	dns = sorted(n[4:] for n in names if n.startswith("dns:"))
	ips = sorted(n[3:] for n in names if n.startswith("ip:"))
	alt = [f"DNS.{i + 1} = {name}" for i, name in enumerate(dns)]
	alt += [f"IP.{i + 1} = {ip}" for i, ip in enumerate(ips)]
	config = _CERT_CONFIG.format(alt="\n".join(alt))
	with tempfile.NamedTemporaryFile("w", suffix=".cnf", dir=cert_dir, delete=False) as fh:
		fh.write(config)
		config_path = fh.name
	try:
		out = subprocess.run(
			["openssl", "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "365",
			 "-nodes", "-keyout", key_path, "-out", cert_path, "-config", config_path],
			capture_output=True, text=True, timeout=120)
		if out.returncode != 0 or not os.path.isfile(cert_path):
			raise RuntimeError(out.stderr.strip() or "openssl failed")
	finally:
		try:
			os.unlink(config_path)
		except OSError:
			pass
	return cert_path, key_path


def _ensure_cert(names: set[str]) -> tuple[str, str, str]:
	"""Return (cert, key, note). Reuses the generated cert when it still fits."""
	cert_path = os.path.join(CERT_DIR, "cert.pem")
	key_path = os.path.join(CERT_DIR, "key.pem")
	if (os.path.isfile(cert_path) and os.path.isfile(key_path)
			and _cert_unexpired(cert_path) and names <= _cert_names(cert_path)):
		return cert_path, key_path, "reused"
	try:
		cert_path, key_path = _generate_cert(CERT_DIR, names)
		return cert_path, key_path, "generated"
	except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
		print(f"⚠️  Could not generate a phone certificate ({exc}).", file=sys.stderr)
	fallback_cert = os.path.join(FALLBACK_CERT_DIR, "cert.pem")
	fallback_key = os.path.join(FALLBACK_CERT_DIR, "key.pem")
	if os.path.isfile(fallback_cert) and os.path.isfile(fallback_key):
		print("⚠️  Falling back to build/web-certs/ — it does not name your LAN IP, so\n"
		      "    the phone will show a certificate error. Tap through it.", file=sys.stderr)
		return fallback_cert, fallback_key, "fallback"
	print(f"❌ No usable certificate. Expected {cert_path} or {fallback_cert}.", file=sys.stderr)
	raise SystemExit(1)


def _firewall_enabled() -> bool | None:
	try:
		out = subprocess.run(["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"],
		                     capture_output=True, text=True, timeout=5)
	except (OSError, subprocess.TimeoutExpired):
		return None
	if out.returncode != 0:
		return None
	return "enabled" in out.stdout.lower() or "state = 1" in out.stdout.lower()


def _self_test(ips: list[str]) -> str:
	"""Ask the running server for its own index over the LAN address."""
	host = ips[0] if ips else "127.0.0.1"
	url = f"https://{host}:{PORT}/"
	context = ssl._create_unverified_context()
	try:
		with urllib.request.urlopen(url, context=context, timeout=5) as resp:
			if resp.status == 200:
				return f"✅ Server answers on {url}"
			return f"⚠️  {url} answered HTTP {resp.status}"
	except Exception as exc:  # noqa: BLE001 - any failure here is just a hint
		return f"⚠️  Could not reach {url} from this Mac ({exc})"


def mount_path(folder: str, url_tail: str) -> str:
	"""Map a URL tail into `folder`; anything that would escape it maps to a
	path that cannot exist (404). The server listens on the LAN, so
	`/extras//etc/passwd` or `%2e%2e` must never reach outside the mount."""
	rel = urllib.parse.unquote(url_tail).lstrip("/")
	full = os.path.realpath(os.path.join(folder, rel))
	if os.path.commonpath([folder, full]) != folder:
		return os.path.join(folder, "__outside_mount__")
	return full


class MountedHandler(http.server.SimpleHTTPRequestHandler):
	"""Serve the web build, the certificate, and repo folders at /extras/ and /tools/."""

	extensions_map = {
		**http.server.SimpleHTTPRequestHandler.extensions_map,
		".wasm": "application/wasm",
		".pck": "application/octet-stream",
	}

	def do_GET(self) -> None:  # noqa: N802 - stdlib naming
		path = self.path.split("?", 1)[0].split("#", 1)[0]
		if path in ("/cert.crt", "/cert.pem", "/cert.cer") and _CERT_FILE:
			with open(_CERT_FILE, "rb") as fh:
				body = fh.read()
			self.send_response(200)
			self.send_header("Content-Type", "application/x-x509-ca-cert")
			self.send_header("Content-Disposition", 'attachment; filename="loqui-quest-local.crt"')
			self.send_header("Content-Length", str(len(body)))
			self.end_headers()
			self.wfile.write(body)
			return
		super().do_GET()

	def translate_path(self, path: str) -> str:
		path = path.split("?", 1)[0].split("#", 1)[0]
		for prefix, folder in MOUNTS.items():
			if path.startswith(prefix):
				return mount_path(folder, path[len(prefix):])
			elif path == prefix.rstrip("/"):
				return folder
		return super().translate_path(path)

	def end_headers(self) -> None:
		# Always load the newest export after re-exporting.
		self.send_header("Cache-Control", "no-store")
		super().end_headers()


def _print_help(ips: list[str], mdns: str | None, cert_path: str, note: str) -> None:
	lan = ips[0] if ips else None
	base = f"https://{lan}:{PORT}" if lan else None
	rel_cert = os.path.relpath(cert_path, REPO_ROOT)
	label = {"generated": "newly generated", "reused": "reused", "fallback": "fallback"}.get(note, note)
	names = ", ".join(sorted(n.split(":", 1)[1] for n in _cert_names(cert_path)))

	print("\nServing the Godot web build over HTTPS")
	print(f"Certificate: {rel_cert}  ({label})")
	if names:
		print(f"Names:       {names}")
	print()
	print(f"  💻 On this Mac     https://127.0.0.1:{PORT}/")
	if base:
		print(f"  📱 On your phone   {base}/")
	if mdns:
		print(f"                     https://{mdns}:{PORT}/   (same Wi-Fi)")
	print()
	print("iPhone / iPad — Safari")
	print(f"  1. Open the phone URL. On the warning tap \"Show Details\" → \"visit this website\".")
	print("  2. Optional, removes the warning and keeps the mic happy:")
	if base:
		print(f"     open {base}/cert.crt → Allow → Close")
	print("     Settings → General → VPN & Device Management → install the profile")
	print("     Settings → General → About → Certificate Trust Settings → enable \"Loqui Quest Local\"")
	print("  3. Reload the game, tap Start, allow the microphone.")
	print()
	print("Android — Chrome")
	print("  1. Open the phone URL → \"Advanced\" → \"Proceed\".")
	if base:
		print(f"  2. Optional trust: download {base}/cert.crt, then")
	print("     Settings → Security → Encryption & credentials → Install a certificate")
	print("     → CA certificate → Install anyway → pick the downloaded file.")
	print("  3. Reload, allow the microphone.")
	print()
	if _firewall_enabled():
		print("Firewall is on — if the phone cannot connect, allow incoming for Python:")
		print("  System Settings → Network → Firewall → Options → Python → Allow")
		print()
	print("Press Ctrl+C to stop.")


def main() -> int:
	global _CERT_FILE
	try:
		sys.stdout.reconfigure(line_buffering=True)
	except AttributeError:
		pass
	if not os.path.isdir(ROOT):
		print(f"Missing web build folder: {ROOT}", file=sys.stderr)
		return 1
	for prefix, folder in MOUNTS.items():
		if not os.path.isdir(folder):
			print(f"Missing mounted folder ({prefix}): {folder}", file=sys.stderr)
			return 1

	ips = _local_ipv4_addresses()
	mdns = _mdns_name()
	cert_path, key_path, note = _ensure_cert(_required_names(ips, mdns))
	_CERT_FILE = cert_path

	os.chdir(ROOT)
	socketserver.TCPServer.allow_reuse_address = True
	httpd = http.server.ThreadingHTTPServer((HOST, PORT), MountedHandler)
	context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
	context.load_cert_chain(certfile=cert_path, keyfile=key_path)
	httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

	_print_help(ips, mdns, cert_path, note)
	threading.Timer(1.0, lambda: print(_self_test(ips) + "\n", flush=True)).start()
	try:
		httpd.serve_forever()
	except KeyboardInterrupt:
		print("\nStopped.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
