# Console Support Implementation Plan

Status: lite support implemented; full focus-controller navigation is deferred
until console runtime testing proves it is needed.

The lite implementation uses `GuiButton.Activated` and existing press visuals
only. It does not force `GuiService.SelectedObject` or global GUI navigation,
so gameplay movement remains unaffected.

## Goals

- Support Xbox, PlayStation, and Roblox Controller Emulator input reliably.
- Preserve current mouse and touch behavior.
- Add consistent focus, modal ownership, scrolling, and ButtonB behavior.
- Keep server authority, purchase validation, rewards, races, and datastores
  unchanged.
- Avoid adding more responsibility to the large `MainOrchestrator` module.

## Current Audit

Existing support is partial:

- Race join, Spin Wheel, Prompt Buy, temporary boosts, and the topbar already use
  `GuiButton.Activated` or existing gamepad logic.
- Default character movement already uses `Humanoid.MoveDirection`; no movement
  rewrite is needed.
- `Topbar/Icon/Features/Gamepad.luau` owns topbar selection and should remain
  untouched unless testing finds a real regression.
- `VisualFunctions` already handles gamepad press visuals. Those handlers should
  remain visual only.

Main gaps:

- `MainOrchestrator.bindGuiButton` still uses `MouseButton1Click` for generic
  actions.
- Daily rewards, playtime rewards, tutorial skip, and dynamic kart/trail cards
  still contain mouse-only action handlers.
- No project-owned manager controls `GuiService.SelectedObject`, focus scopes,
  focus restoration, or modal Back behavior.
- Dynamic shop cards can destroy the selected object during a rebuild.
- Custom speed TextBox behavior has not been validated with the console keyboard.

## Implementation

### 1. Add a focus controller

Create `src/ReplicatedStorage/Modules/UI/ConsoleFocusController.luau`.

Small API responsibilities:

- Register and activate focus scopes.
- Focus the first valid control when a frame opens.
- Restore the previous valid control when a frame closes.
- Repair selection when the selected object is hidden, disabled, or destroyed.
- Handle nested modal ownership.
- Rebuild dynamic selection without retaining destroyed instances.
- Disconnect all connections through the existing cleanup pattern.

Use `GuiService.SelectedObject` as the selection source of truth. Detect console
input through Roblox preferred-input/gamepad APIs, but do not force gamepad
selection onto mouse or touch users.

### 2. Migrate action signals

Update these paths to use `Activated` exactly once per action:

- `ReplicatedStorage/Modules/UI/MainGUI/MainOrchestrator.luau`
- `ReplicatedStorage/Modules/UI/MainGUI/DailyRewardsUI.luau`
- `ReplicatedStorage/Modules/UI/MainGUI/PlaytimeRewardsUI.luau`
- `ReplicatedStorage/Modules/UI/MainGUI/TutorialNotificationSystem/init.luau`

Migrate dynamically generated kart and trail card buttons during card
registration. Keep `MouseButton1Down`, `MouseButton1Up`, `InputBegan`, and
`InputEnded` only for press animation and darkening.

Do not bind both `MouseButton1Click` and `Activated`, or ButtonA can trigger a
purchase, reward, or remote twice. Preserve existing debounces, sounds,
disabled states, hover behavior, and server validation.

### 3. Define focus scopes

Create centralized scopes for HUD, Shop, Kart, Trail, Rebirth, Verify, Troll,
Daily Rewards, Playtime Rewards, Rewards, Spin Wheel, Prompt Buy, Return to
Stage, race notifications, tutorial, and Custom Speed.

Each scope selects only visible, interactable, selectable controls. Configure
stable `SelectionOrder` and directional neighbors where automatic selection is
unreliable. Modal focus must not reach controls behind it; ZIndex alone is not
sufficient.

Opening a frame focuses its first valid action. Closing it restores the opener if
valid, otherwise a safe HUD fallback.

### 4. Handle dynamic shops and scrolling

For KartFrame, TrailFrame, ShopFrame, and RewardsFrame:

- Register selection after cards are cloned.
- Preserve focus by stable kart, trail, or product ID, not the old Instance.
- Select the nearest valid item if the old item becomes unavailable.
- Scroll the selected item into view.
- Refresh focus only after list changes, not every frame.

### 5. Add scoped ButtonB behavior

Use a scoped `ContextActionService` or input binding:

- Release or cancel TextBox focus first.
- Close the deepest popup before its parent frame.
- Restore the previous selection after closing.
- Do not override Roblox's topbar/menu behavior when no project modal is active.

ButtonA actions continue through `Activated`, not a second manual ButtonA path.

### 6. Validate console text input

Test CustomSpeedTextBoxFrame with the console keyboard, including numeric
validation, confirm, cancel, reopen, respawn, and frame-close cases. Client
input remains non-authoritative; the server continues validating speed values.

### 7. Add limited diagnostics

Add a disabled-by-default `ConsoleUI` debug scope through `DebugModule` only if
needed. Log scope transitions, focus repair, invalid selections, and cleanup.
Do not log every D-pad event, render step, or frame.

## Files

Expected implementation scope:

- New: `src/ReplicatedStorage/Modules/UI/ConsoleFocusController.luau`
- Existing: `MainOrchestrator.luau`, `MainFunctions.luau`, `VisualFunctions.luau`
- Existing: `DailyRewardsUI.luau`, `PlaytimeRewardsUI.luau`,
  `TutorialNotificationSystem/init.luau`
- Optional only if required: GUI metadata for selection order and neighbors

Do not modify the topbar vendor module, datastore systems, race server logic,
reward calculation, or event systems unless testing proves a direct defect.

## Verification

- Roblox Controller Emulator plus real Xbox and PlayStation controllers.
- HUD, topbar, every modal, nested popup, and ButtonB behavior.
- D-pad and analog navigation, disabled/cooldown buttons, scrolling cards, and
  dynamic card rebuilds.
- Race join, Spin Wheel, Prompt Buy, ads, rewards, purchases, tutorial, and
  Custom Speed.
- Respawn, death, frame close during tween, streamed UI changes, and overlays.
- Mouse and touch regression.
- No duplicate remotes, sounds, purchases, rewards, or stuck selections.

## Rollout

1. Add and test the focus controller without changing notification systems.
2. Migrate mouse-only actions to `Activated`.
3. Add focus scopes, dynamic-card restoration, and ButtonB behavior.
4. Test controller, mouse, touch, respawn, and modal edge cases.

This is medium-complexity UI work. No server movement, datastore, reward, or
event-schedule rewrite is required.
