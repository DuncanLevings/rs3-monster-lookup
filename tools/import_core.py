"""Refresh the embedded library from a local Monster Data Core checkout."""
from pathlib import Path
import hashlib
import json
import re
import sys

project = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else None
if not source or not (source / "src/api.lua").is_file():
    raise SystemExit("Usage: python tools/import_core.py PATH_TO_MONSTER_DATA_CORE")

manifest = json.loads((source / "plugin.json").read_text(encoding="utf-8"))
target = project / "src/data/library"
if not target.resolve().is_relative_to(project) or target.resolve() == (source / "src").resolve():
    raise SystemExit("Source and target must be separate directories inside the intended project.")

files = list((source / "src").rglob("*.lua"))
hashes = {}
for original in files:
    relative = original.relative_to(source)
    destination = target / original.relative_to(source / "src")
    data = original.read_bytes()
    hashes[relative.as_posix()] = hashlib.sha256(data).hexdigest()
    text = re.sub(r"([\"'])src/", r"\1src/data/library/", data.decode("utf-8"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8", newline="\n")

snapshot = {
    "library": "Monster Data Core",
    "version": manifest["version"],
    "source": "https://github.com/DuncanLevings/rs3-monster-data-core",
    "transformation": "src/ module paths relocated to src/data/library/",
    "source_sha256": hashes,
}
(project / "tools/library_snapshot.json").write_text(
    json.dumps(snapshot, indent=2) + "\n", encoding="utf-8"
)
(project / "tools/MONSTER_DATA_CORE_NOTICES.txt").write_bytes(
    (source / "THIRD_PARTY_NOTICES.txt").read_bytes()
)
print(f"Imported {len(files)} Lua files from Monster Data Core {manifest['version']}.")
print("Review notices, removed upstream files and types, then rerun the plugin checks.")
