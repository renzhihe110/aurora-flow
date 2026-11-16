# Aurora Flow v1.0.2

- Remembers brightness, line width, animation periods, direction, display selection, glow radius and corner radius across App restarts, including starts through the Codex skill and hooks.
- Restores saved settings before initializing the animation timeline and validates restored values using the existing limits.
- Reduces the default radius of all four corners from 32 to 16 physical pixels. Existing saved corner values remain in effect.
- Updates both the standalone Universal App and the complete Codex Skill archive with the same App.

The Swift Release build includes both arm64 and x86_64. The unchanged Metal library is reused from the previously verified build. Restart persistence was checked with the real App; UI controls were also exercised, and the smaller corners were visually reviewed on a two-display setup. Only Apple Silicon was run.

Requires macOS 13+ and a Metal-capable Mac. The Skill additionally needs Python 3.9+ and a local Codex installation with hooks support. Review and enable the five hooks in Codex Settings > Hooks or CLI `/hooks` after installation. Existing hook definitions and controller behavior are unchanged.

The prebuilt App is ad-hoc signed and is not Developer ID notarized.
