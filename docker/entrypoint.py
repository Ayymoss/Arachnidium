#!/usr/bin/env python
"""
  Prepares the container before starting Arachnidium:

  - defaults.json is written from the shipped defaults, with any setting
    overridden by an environment variable of the same name (for example
    IMAGE_QUALITY=40). The GUI is always disabled, as there is no display.
  - wg-keys.json is generated on first start, giving every install its own
    WireGuard keys instead of the ones committed to the repository.
  - mitmproxy keeps its CA in /data/mitmproxy, so devices don't need to
    reinstall the certificate when the container is recreated.
"""

import json
import os
import sys

import mitmproxy_rs

DATA = "/data"

def prepare_defaults():
  with open("/app/docker/defaults.json", "r") as shipped_file:
    defaults = json.load(shipped_file)
  for key in defaults:
    if key not in os.environ: continue
    try:
      defaults[key] = json.loads(os.environ[key])
    except json.JSONDecodeError:
      sys.exit(f"Invalid value for {key}: {os.environ[key]!r} (expected JSON, e.g. true or 40)")
  defaults["ENABLE_GUI"] = False
  with open("/app/defaults.json", "w") as defaults_file:
    json.dump(defaults, defaults_file, indent=2)

def prepare_wireguard_keys():
  path = os.path.join(DATA, "wg-keys.json")
  if os.path.exists(path): return
  keys = {
    "server_key": mitmproxy_rs.wireguard.genkey(),
    "client_key": mitmproxy_rs.wireguard.genkey(),
  }
  with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as keys_file:
    json.dump(keys, keys_file, indent=4)
  print("Generated new WireGuard keys in", path)

def main():
  os.makedirs(os.path.join(DATA, "mitmproxy"), exist_ok=True)
  prepare_defaults()
  prepare_wireguard_keys()
  os.execvp(sys.argv[1], sys.argv[1:])

if __name__ == "__main__":
  main()
