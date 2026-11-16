# Validation and manual acceptance

## v1.0.2

Both arm64 and x86_64 Swift Release architectures were rebuilt for settings persistence and the 16-physical-pixel default corner radius. The unchanged, previously verified Metal library was reused. Only Apple Silicon was run. The real App saved a temporary configuration, exited, restarted, and retained brightness, width, period, direction and display selection when another setting was updated. Original preferences were restored afterward. Separate CUA interaction changed controls in the settings panel; after restart the saved values were present, but the tool could not reopen the settings panel for a second visual reading. The smaller corners were visually approved while real overlays ran on two displays.

## Earlier releases

The initial implementation was built and exercised on macOS 26.6 with Apple Silicon, a 3024×1964 Retina display and Xcode 27.2. Both arm64 and x86_64 Release architectures compiled; only Apple Silicon was run. The v1.0.0 release binary has rounded top corners and square bottom corners.

Observed behavior includes real screen overlays, click-through button interaction, keyboard input in an independent window, a standard full-screen Space, menu controls, configuration updates, repeated starts/stops and interrupting a terminal animation with a new task. Prior checks also exercised session sharing and real Codex hooks for mac-input, CUA completion cleanup and agent-desktop commands.

For this public release, the previously built native App is reused rather than automatically rebuilt. Embedded Metal source metadata is removed with Apple's tool and the distribution copy is ad-hoc signed. Raw machine diagnostics, display UUIDs, local paths and private desktop screenshots are intentionally not distributed.

## Manual checklist

1. Open the standalone App, Start, and observe all four edges for two gradient cycles. For current source, check four rounded corners inside the usable desktop area; the v1.0.0 download retains square bottom joins.
2. Click, type and move windows; use the menu bar and Dock. Check the center stays transparent and focus remains with the underlying app.
3. Trigger Success, Error, Stop and Cancel. Restart during feedback and repeat Start/Stop; check no duplicate overlays remain.
4. Change brightness, width, period, direction and display selection while running.
5. Install the complete skill into a chosen Codex directory, review its hooks, call a desktop tool, then finish the operation. Check startup and final process exit.
6. Exercise two chat owners; ending one must preserve the other owner's glow.
7. Test other macOS versions, Intel hardware, external displays, mixed scales/refresh rates, negative screen coordinates, sleep/wake and hot-plugging.

External multi-display hardware, older macOS/Intel runtime coverage, exhaustive input-method behavior and long-duration GPU/power profiling remain areas for additional validation. Display FPS, submission frequency and CPU/GPU utilization are different measurements; no universal 120 FPS or GPU-percentage guarantee is made.

## Public package checks

The complete release skill ZIP was extracted and installed into a temporary Codex directory. Installation, replacement, and uninstallation preserved pre-existing hook definitions and instructions, produced backups, and avoided duplicate routing blocks. The stripped, re-signed distributed App started a real transparent overlay, submitted Metal frames, and exited through its session controller. Both archive checksums, App code signatures, plist files and skill metadata passed validation. These packaging checks did not compile the native App.

## Usable-area development update

The current source uses NSScreen.visibleFrame, four rounded corners, a 6-pixel default core and a 40-pixel glow radius. In local validation, the overlay matched the reported 1512×886-point usable area, excluding a 33-point menu bar and 63-point Dock region. The drawable was 3024×1772 pixels. The four-corner rendering and larger glow were observed in a real running overlay. These changes are separate from the v1.0.0 release artifacts.
