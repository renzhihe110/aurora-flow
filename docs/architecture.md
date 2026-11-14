# Architecture

## Rendering

`AuroraOverlayPanel` is a borderless, transparent, nonactivating `NSPanel`. It uses the full `NSScreen.frame`, ignores mouse events, cannot become key/main, and joins standard full-screen Spaces through public AppKit collection behavior. Each display has an independent drawable at its own backing scale.

`AuroraRenderer` shares a Metal device, queue and render pipeline. A frame uses 24 vertices covering four nonoverlapping edge bands and an 80-byte uniform. `AuroraShaders.metal` computes a signed distance to the border and actual perimeter distance: four straight lines, two top arcs, and square bottom joins. Core light and two soft falloffs are composited as premultiplied alpha; the center remains transparent.

A shared monotonic timeline drives an 8-second gradient cycle, 3-second subtle breath, and a slower highlight about 11% of the perimeter. These are independent periods; the full combined image does not have to repeat after eight seconds. Configuration changes retain animation phase.

`AuroraController` owns display selection, hot-plug reconciliation, task transitions and terminal cleanup. Idle has no overlay or continuous rendering. Sleep/session notifications pause or hide overlays.

## Skill and hooks

The skill is instruction plus a Python standard-library controller. It is separate from the native App and never requires a source build during normal use.

The controller receives Codex lifecycle JSON, checks tool names/arguments, and registers session ownership in a locally locked state file. Its own process is short-lived. It starts the bundled executable directly with `--start`, then waits for the App's initial diagnostic report. A continuous operation phase reuses the same process.

CUA completion summaries release the session immediately. Explicit skill cleanup handles desktop phases using other backends. Normal turn/session endings and interruptions provide fallback cleanup. A later stop from an older turn does not remove a newer turn's ownership.

Only the final owner sends SIGTERM, after verifying executable identity and start time. The controller does not modify desktop tool calls or their permission decisions. Unrelated manual instances are not terminated. A forced host crash can skip cleanup because no watchdog is installed.

## Installation and updates

The installer copies an App and skill into the selected Codex configuration directory. Hooks and marked AGENTS instructions are opt-in through `--enable-hooks`, merged with backups, and require normal Codex trust review. Existing unmanaged skills are not replaced.

The source repository omits App binaries. Complete release skill archives add the same App shipped in the standalone archive. Updating source alone does not update an installed binary; build/package and reinstall intentionally. The supplied package script does not compile or notarize.
