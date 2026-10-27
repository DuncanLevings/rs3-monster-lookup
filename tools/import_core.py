"""Replace the embedded snapshot from a local Monster Data Core checkout.

Read and prepare every input before changing the installed snapshot. Re-running an
interrupted import is safe: the source tree, types, notices and hashes are regenerated.
"""
from pathlib import Path
import hashlib
import json
import re
import sys
import tempfile


def import_core(project, source):
    project = project.resolve()
    source = source.resolve()
    target = project / "src/data/library"
    types = project / "types"
    if source == project or target.is_relative_to(source) or source.is_relative_to(target):
        raise ValueError("Import from a separate Monster Data Core checkout.")

    # These are generated directories, never user-selected deletion targets.
    for destination in (target, types):
        if destination.resolve() != destination or not destination.is_relative_to(project):
            raise ValueError("Generated directory must stay inside the plugin checkout.")

    manifest = json.loads((source / "plugin.json").read_text(encoding="utf-8"))
    notices = (source / "THIRD_PARTY_NOTICES.txt").read_text(encoding="utf-8")
    plugin_notices = (project / "tools/PLUGIN_NOTICES.txt").read_text(encoding="utf-8")
    files = {}
    hashes = {}
    for original in sorted((source / "src").rglob("*.lua")):
        data = original.read_bytes()
        relative = original.relative_to(source)
        hashes[relative.as_posix()] = hashlib.sha256(data).hexdigest()
        files[original.relative_to(source / "src")] = re.sub(
            r"([\"'])src/", r"\1src/data/library/", data.decode("utf-8")
        )
    type_files = {
        original.relative_to(source / "types"): original.read_text(encoding="utf-8")
        for original in sorted((source / "types").rglob("*.lua"))
    }
    if Path("api.lua") not in files or not type_files:
        raise ValueError("Source must contain src/api.lua and the library type definitions.")

    snapshot = {
        "library": "Monster Data Core",
        "version": manifest["version"],
        "source": "https://github.com/DuncanLevings/rs3-monster-data-core",
        "transformation": "src/ module paths relocated to src/data/library/",
        "source_sha256": hashes,
        "types_sha256": {
            path.as_posix(): hashlib.sha256(text.encode("utf-8")).hexdigest()
            for path, text in type_files.items()
        },
    }
    shipped_notices = (
        plugin_notices.rstrip()
        + f"\n\nEmbedded Monster Data Core snapshot ({manifest['version']})\n"
        + "Source paths in the following notices refer to the upstream data-library repository.\n"
        + "Runtime Lua files are bundled under src/data/library/.\n"
        + notices.rstrip().replace(
            "full license retained in src/vendor/json.lua",
            "full license retained in src/data/library/vendor/json.lua",
        )
        + "\n"
    )

    with tempfile.TemporaryDirectory(prefix="core-import-", dir=project / "tools") as temporary:
        stage = Path(temporary)
        for folder, contents in (("library", files), ("types", type_files)):
            for relative, text in contents.items():
                path = stage / folder / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8", newline="\n")

        # Swap prepared trees instead of overlaying files: removed upstream files disappear.
        for destination in (target, types):
            backup = stage / (destination.name + "-previous")
            if destination.exists():
                destination.rename(backup)
            try:
                (stage / destination.name).rename(destination)
            except OSError:
                if backup.exists():
                    backup.rename(destination)
                raise

        (project / "THIRD_PARTY_NOTICES.txt").write_text(shipped_notices, encoding="utf-8", newline="\n")
        (project / "tools/library_snapshot.json").write_text(
            json.dumps(snapshot, indent=2) + "\n", encoding="utf-8", newline="\n"
        )

    print(f"Imported {len(files)} Lua files from Monster Data Core {manifest['version']}.")
    print("Source, types, shipped notices and hashes updated. Review the diff and rerun checks.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tools/import_core.py PATH_TO_MONSTER_DATA_CORE")
    import_core(Path(__file__).resolve().parent.parent, Path(sys.argv[1]))
