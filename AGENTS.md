# Contributor instructions

Read DEVELOPMENT.md before making changes. Preserve the branch's intended feature set;
PLUGIN_API.md or WIKI_CACHE.md describes a feature branch when present.

Write for a junior developer reviewing the implementation: descriptive names, short purpose
comments and blank lines between logical steps. Avoid repeated tutorials and forwarding layers.
Verify native API details. Retain documented client-crash and lifetime safeguards.

Monster Data Core is embedded under src/data/library; do not restore the plugin dependency.
Main has no public plugin API or HTTP/cache path. Optional GEPL prices remain supported.
Use tools/package.ps1 for releases. Review/test in game before pushing; do not push without
the user's explicit authorization.
