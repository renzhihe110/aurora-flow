# Aurora Flow v1.0.1

- Draws the border inside the display's usable area, excluding the current menu bar and Dock.
- Uses rounded corners on all four sides, with a default 6 px core and 40 px glow radius.
- Includes the standalone Universal App and the complete Codex Skill archive with the updated App.
- Retains the existing hook installation, session ownership and cleanup behavior.

Requires macOS 13+ and a Metal-capable Mac. The Skill additionally needs Python 3.9+ and a local Codex installation with hooks support. Review and enable the five hooks in Codex Settings > Hooks or CLI `/hooks` after installation.

The prebuilt App is ad-hoc signed and is not Developer ID notarized. It reuses the previously compiled and visually verified Universal App; the distribution copy's version metadata has been updated and signed again.
