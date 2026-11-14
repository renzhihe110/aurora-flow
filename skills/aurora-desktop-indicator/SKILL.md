---
name: aurora-desktop-indicator
description: Show a transparent Aurora Flow screen-edge indicator on macOS while performing real desktop operations with computer-use, unified-computer-use/cua_repl, agent-desktop or mac-input. Start before the first desktop tool call, keep it visible across consecutive operations, and release it when the desktop phase completes, fails or is cancelled. Do not activate for ordinary coding, computation or discussion of these tools.
---

# Aurora Desktop Indicator

Use the bundled `assets/AuroraFlow.app`. It draws a click-through, nonactivating blue/purple screen border with four rounded corners around the usable desktop area. Do not open its settings window during automation.

## Lifecycle

Replace `<skill-dir>` below with the directory containing this SKILL.md. Session ownership uses the existing `CODEX_THREAD_ID`. If it is unavailable, pass `--session` with the current chat ID and reuse that ID when stopping.

```bash
# Acquire the current chat's indicator before the first desktop tool call.
python3 "<skill-dir>/scripts/aurora.py" start
```

Keep the same App running across consecutive observations, clicks, typing and backend changes. When the desktop phase finishes, fails, is cancelled or hands control to a person, release ownership immediately:

```bash
# The last active chat releases and exits the managed App.
python3 "<skill-dir>/scripts/aurora.py" stop
```

Follow the desktop tool's own cleanup rules. Release held mac-input buttons before finishing; still provide CUA `completion_summary` as required. An unrelated coding phase should not keep the indicator running.

## Hooks

When installed with `scripts/install.py --enable-hooks`, the controller merges user-level Codex hooks:

- `PreToolUse` recognizes desktop MCP tools, CUA calls, and direct agent-desktop commands in shell tools.
- `PostToolUse` releases ownership after CUA `completion_summary`.
- `Stop`, `Interrupt` and `SessionEnd` provide normal lifecycle cleanup.

Manual lifecycle calls and hooks are idempotent. New or changed hook definitions require normal review in Codex Settings > Hooks or CLI `/hooks`; never bypass trust review, alter tool approval policy, replace `notify`, or rewrite MCP server commands. Until hooks are trusted, use the explicit lifecycle calls above.

Multiple chats share one managed App. Ending one chat must not close another chat's indicator. Only the verified process created by this controller may be terminated; unrelated manually launched App instances are left alone.

## Operation and limits

- `status` reports the managed PID and owning chats.
- Use `stop --all` when the user explicitly asks to close all managed indicator activity.
- `install-hooks` reinstalls hooks after relocating the skill; review changed definitions again.
- The complete release ZIP bundles the App. A source checkout needs a built App supplied to the installer with `--app`; never compile or download implicitly.
- If startup fails, briefly report that the visual indicator is unavailable and continue the already authorized desktop task. Do not deny, approve or rewrite its tool calls.
- There is no always-running watcher. Host crashes or force-killing Codex can prevent cleanup hooks; an explicit `stop --all` recovers a leftover managed instance.
