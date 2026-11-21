# quickseek: working guide

One Quickshell search window for Hyprland. Talk to the owner in Russian; repository prose,
UI strings and code comments are English. Keep comments sparse and explain why.

## Start here
- Read `README.md` for current behavior, settings, IPC, keyboard handling and measured cost.
- Read `docs/agent-decisions.md` before changing product behavior: it preserves all decisions,
  constraints and implementation history previously kept in dotfiles task 13.
  Historical completion and test marks are not evidence about today's checkout.
- For plugin work read `docs/plugins.md`. Use `examples/settings.json` for settings shape.
- For this user's Hyprland, stow, glass and theme integration, read `~/dotfiles/AGENTS.md`
  and the relevant section of `~/dotfiles/docs/agent-reference.md`.

## Working agreements
- Commit and push only when asked. Keep the owner's existing work separate from new changes.
  Commit messages describe the change and contain no assistant attribution or Co-Authored-By.
- Preserve agreed behavior: files require the `f ` prefix by default, Esc closes one level at
  a time, and the window holds keyboard focus until pressed keys are released.
  Idle means no polling timers or unnecessary wakeups; free large result data after closing.
- Keep machine-specific paths, commands and services in settings or dotfiles. Core behavior
  must work for other users. Preserve settings symlinks when saving files.
- Confirm behavior against the current code; don't silently reintroduce superseded shortcuts,
  rofi integration or the removed index timer from the historical tracker.

## Safe validation
- The owner's desktop runs this directory with live QML reload. Use an isolated copy/worktree
  for UI changes and separate XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_CACHE_HOME.
  Check how QUICKSEEK_APPID is used before launching a dev instance; address IPC by its PID.
- Test outside the live compositor. Never create/remove headless outputs on the owner's
  Hyprland without explicit approval. The isolated stand procedure is in dotfiles guidance.
- Validate query/results and real interaction through supported IPC (`rows`, `key`, `type`);
  test arrows, Enter, Space, Esc, folder navigation, action menus, prompts and previews as relevant.
  Verify both the main window and child prompts/dialogs; report untested real keyboard behavior.
- Preserve idle CPU and wakeups; compare CPU, RSS and wakeups for changes that affect them.
  Clean up all processes started for testing and verify their exit before finishing.
- At the end update relevant history in `docs/agent-decisions.md` and describe validation limits.
