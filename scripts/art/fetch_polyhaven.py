"""Fetch the exact CC0 texture files in the checked-in provenance manifest."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets/operator/textures/hd/sources.json"


def valid(path, entry):
    return (path.is_file() and path.stat().st_size == entry["bytes"]
            and hashlib.md5(path.read_bytes()).hexdigest() == entry["md5"])


def main():
    for entry in json.loads(MANIFEST.read_text()):
        destination = ROOT / entry["file"]
        if valid(destination, entry):
            print("Verified", entry["file"])
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".download")
        subprocess.run(["curl", "--fail", "--location", "--retry", "3",
                        "--output", str(temporary), entry["source"]], check=True)
        if not valid(temporary, entry):
            raise ValueError("Download checksum mismatch: " + entry["file"])
        temporary.replace(destination)
        print("Downloaded", entry["file"])


if __name__ == "__main__":
    main()
