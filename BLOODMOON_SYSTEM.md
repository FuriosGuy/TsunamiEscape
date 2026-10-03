# Blood Moon System

Current implementation summary for the Blood Moon event in SpeedBrainrotDev.
Runtime configuration is defined in `src/ServerScriptService/Modules/Shared/CoreConfig_Server.luau`.

## Schedule And State

- The server owns event state through `LiveEventService`.
- State is replicated through the `ReplicatedStorage.LiveEventState` folder.
- Production rotation transition is anchored at `1790809200` (2026-09-30
  23:00 UTC / 2026-10-01 07:00 Asia/Manila). Its first window preserves the
  in-progress Blood Moon for 3 active days, then uses the new 2-day grace.
- Later Blood Moon windows use 2 active days and 2 grace days. Minor event
  windows use 1 active day and 2 grace days. Major/Minor pair spans 7 days.
- Pre-event countdown remains 24 hours.
- Studio debug overrides are disabled; production rotation is configured in
  the server-only `CoreConfig_Server` module.
- Schedule refreshes live, so already-running servers receive event changes
  without restarting.
- A new Blood Moon cycle resets `BloodmoonWins` to zero. Owned rewards remain
  permanent and are not removed.

## Environment

- The client uses `EnvironmentService` to transition between `Default` and
  `Bloodmoon` profiles.
- Atmosphere transitions first, followed by the remaining supported lighting
  properties during the transition.
- The full transition takes about 6.5 seconds with the current lead setting.
- Players joining during an active event receive the Blood Moon environment
  immediately rather than replaying the rise animation.
- Blood Moon rise audio uses asset `89079094196786` and plays once after the
  live transition completes.
- Unsupported or RobloxScript-only lighting properties are not written by the
  runtime environment applier.

## Event UI

- `LiveEventBannerUI` uses `EventFrameTemplate` and creates one card per event.
- Multiple events can appear at the same time, such as Blood Moon and 2X
  Weekend.
- Event names are automatically displayed in uppercase with rich-text color.
- Active Blood Moon displays `BLOOD MOON` and its ending countdown.
- Before activation, the card displays the event name with `LIVE IN:` and a
  pre-event countdown.
- During the environment transition, the card displays
  `THE BLOOD MOON RISES...` in red.
- At the end of the active countdown, it displays `ENDING...` until the
  environment transition has finished, then removes the active card.
- 2X Weekend intentionally has no long countdown on its active card.

## Gameplay Effects

- Normal movement and treadmill XP receives a `1.5x` Blood Moon multiplier.
- The effective player WalkSpeed and maximum speed are reduced to 75 percent
  while the event is active.
- Saved speed values are not permanently changed.
- Custom speed UI uses the effective event-adjusted maximum.
- Normal final-stage WinButton rewards continue to work.
- Valid WinButton completions grant Bloodmoon Wins by stage: stages 16-17 grant
  1, stages 18-19 grant 2, and stage 20 grants 3 before applicable win
  multipliers.
- Teleporting or reaching the end area without a valid server-side completion
  cannot grant Bloodmoon Wins.
- Bloodmoon-specific wins use the normal `WinMultiplier` and temporary win
  boost, but do not use treadmill, rebirth, dev-product, or 2X Weekend reward
  multipliers.
- The stage-based Bloodmoon win amounts are identical in Studio and published
  servers when awarded through a WinButton.

## Compensation Campaign

- `DataRecoveryCompensation_20260830` is available from Unix `1788019200`
  through (exclusive) `1788624000`.
- Window is `2026-08-30 00:00` through `2026-09-06 00:00` PHT, seven days.
- Each player receives one automatic, persisted claim after successful data
  load: 30 minutes of temporary 2X Speed and 30 minutes of temporary 2X Wins.
- `CompensationClaimedCampaigns` stores claim state. Failed forced saves roll
  the grant back, so failed persistence does not consume claim.

## Blood Moon Progress

- `EventProgress` replaces `StageProgressFrame` while an event with progress UI is active.
- It is hidden at zero Bloodmoon Wins and restored when the event ends.
- `CurrentWins` displays the player's Bloodmoon Wins.
- `NextUnlock` displays the next reward or `ALL REWARDS UNLOCKED`.
- Progress markers are generated from the configured unlock list, including the
  final marker.
- Marker positions account for the rounded UI track corner.
- Progress and marker images use configured reward assets with safe fallbacks.
- The UI refreshes when wins, event state, or layout changes.

## Free Rewards

| Reward | Requirement | Value |
|---|---:|---:|
| Eclipse Trail | 5 Bloodmoon Wins | 7x XP multiplier |
| Crimson Runner | 20 Bloodmoon Wins | 25,000 Speed per step |
| Night Glider | 50 Bloodmoon Wins | 55,000 Speed per step |
| Moonfang | 100 Bloodmoon Wins | 80,000 Speed per step |

Free Blood Moon kart cards are event-only and are permanently owned after
unlocking. They use the Blood Moon red styling and normal equip validation.

## Paid Blood Moon Karts

| Kart | Developer Product | Value |
|---|---:|---:|
| Crimson Cell | `3710412649` | 100,000 Speed per step |
| Blood Dragon | `3710413009` | 160,000 Speed per step |
| Siege Tank | `3710413231` | 225,000 Speed per step |

- Paid karts are permanent after a successful server receipt.
- They can only be purchased while Blood Moon is active.
- Product purchases are granted through `ProductServerService` receipt
  processing and cannot be finalized by the client.
- Blood Moon kart products can appear in `PromptBuyProductsFrame` only while
  the event is active.
- Prompt selection currently gives Blood Moon kart products a selection weight
  of 3.
- Blood Moon karts use NeonRacing's engine sound except Siege Tank, which uses
  Advanced Tank's engine sound.
- Blood Moon showcase karts do not receive the gamepass showcase tilt unless
  explicitly configured.

## Physical Event Shop

- `EventBlock` disables collision and its normal billboard displays outside the
  event.
- During Blood Moon, the event billboard is shown and the shop becomes usable.
- Server-side checks also reject event kart interaction and purchases when the
  event is inactive.
- Free event kart buttons use the normal affordability colors based on
  Bloodmoon Wins.

## Visual Effects And Tsunami Changes

- `BloodmoonParticle` is a client visual that follows the player's grounded
  position.
- Current particle footprint is 512 by 512 studs and updates at 15 FPS.
- It stays locked to the last ground position while the player is airborne.
- It cleans up on event end, death, respawn, player removal, and script cleanup.
- Tsunami visuals use the Extremely Fast tsunami color during Blood Moon.
- Existing tsunami visuals update when the event state changes, and original
  colors return after the event ends.

## Badges And Notifications

- Blood Moon badges are awarded server-side at 5, 20, 50, and 100 wins.
- Badge awarding is cross-experience aware and retry-backed.
- Studio badge awarding is skipped by configuration.
- Newly unlocked rewards notify the player with an uppercase Blood Moon unlock
  message and are immediately saved when possible.
- Bloodmoon Win floating rewards move toward the progress counter without the
  normal win pop sound.

## Prompt Buy Studio Preview

`CoreConfig.promptBuy.studioShowOwnedProducts` is now a configurable Studio-only
debug switch. When enabled together with Studio execution, Prompt Buy includes
already-owned permanent offers for preview, including owned:

- Trails.
- Gamepass karts.
- Blood Moon paid karts.
- Treadmill gamepasses.
- Starter Pack and other permanent gamepasses.

This bypasses only the client-side ownership filter used to populate the debug
prompt. It does not bypass Blood Moon activity checks, product exclusions,
Roblox purchase prompts, server receipt validation, or live-server behavior.
Set the value to `false` to restore normal Studio ownership filtering. Published
servers never enable this behavior because the gate also requires
`RunService:IsStudio()`.

## Main Source Modules

- `src/ReplicatedStorage/Modules/Config/CoreConfig.luau`
- `src/ServerScriptService/Modules/LiveEventService.luau`
- `src/ServerScriptService/Modules/LiveEventSchedule.luau`
- `src/ReplicatedStorage/Modules/EnvironmentService.luau`
- `src/ReplicatedStorage/Modules/UI/MainGUI/LiveEventBannerUI.luau`
- `src/ReplicatedStorage/Modules/UI/MainGUI/EventProgressUI.luau`
- `src/ReplicatedStorage/Modules/BloodmoonParticleService.luau`
- `src/ReplicatedStorage/Modules/TsunamiVisualService.luau`
- `src/ReplicatedStorage/Modules/ProductService.luau`
- `src/ServerScriptService/WorldManager.server.luau`
- `src/ServerScriptService/PlayerAttributeManager.server.luau`
