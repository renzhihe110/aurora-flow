# Aurora Flow v1.0.0

First open-source release of the native macOS border and Codex desktop indicator skill.

- Swift/AppKit/Metal real-screen glow, transparent center, click-through windows, rounded top and square bottom corners.
- Start, success, error, cancel and stop transitions; live settings and display selection.
- Codex skill and session controller for computer-use, CUA, agent-desktop and mac-input.
- Opt-in lifecycle hooks, shared-session ownership and normal completion/interruption cleanup.
- Relocatable installer/uninstaller, bilingual documentation and MIT license.

## Choose a download

- **AuroraFlow-1.0.0-macOS-universal.zip**: standalone App for Apple Silicon and Intel.
- **aurora-desktop-indicator-1.0.0.zip**: complete Skill with the same App, Python controller and installer.
- **SHA256SUMS.txt**: SHA-256 checksums of both archives.

For the Skill, extract its ZIP and run `python3 aurora-desktop-indicator/scripts/install.py --enable-hooks`, then review/enable the five Aurora hooks in Codex Settings > Hooks or CLI `/hooks`.

Requires macOS 13+, Metal, and Python 3.9+ for the Skill. The App itself needs no Accessibility or Screen Recording permission. Desktop tools keep their own permission requirements.

Prebuilt Apps are ad-hoc signed, not Developer ID notarized. This release reuses the locally validated Universal App with embedded Metal source metadata stripped; it was not automatically rebuilt for publication. See the repository's validation notes for coverage and remaining hardware checks.
