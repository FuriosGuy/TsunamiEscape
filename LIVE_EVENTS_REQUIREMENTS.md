# Live Event Requirements

This document is the checklist for adding or changing a live event. Update it
with the implementation whenever an event changes so configuration, gameplay,
world UI, and shop UI do not drift apart.

## Current Events

### Bloodmoon

- Event ID: `Bloodmoon`
- Rotation tier: `Major`
- Display name: `BLOOD MOON`
- Environment: `Bloodmoon`
- Event wins attribute: `BloodmoonWins`
- Stage awards: stage 16 = 1 win, stage 18 = 2 wins, stage 20 = 3 wins
- Kart wins: 20, 50, and 100
- Paid karts: Crimson Cell, Blood Dragon, Siege Tank
- Progress colors: red background and red gradient
- Win popup image: `128959525567285`
- Event block: `BLOOD MOON KARTS` and `BLOOD MOON WINS REQUIRED`

### NeonRush

- Event ID: `NeonRush`
- Rotation tier: `Minor`
- Display name: `NEON RUSH`
- Environment profile: `NeonRush` (blue neon Lighting profile)
- Event wins attribute: `NeonRushWins`
- Blood Moon gameplay modifiers: none
- Stage awards: stage 16 = 1 win, stage 18 = 2 wins, stage 20 = 3 wins
- Kart wins: 20 and 50
- Free karts: `1_SparkBuggy`, `2_TurboRunner`
- Paid kart: `3_VoltVIper`
- Paid product ID: `3712635731`
- Kart images: Spark Buggy `111899124648289`, Turbo Runner `119199314964183`,
  Volt Viper `114735487114166`
- Progress colors: background `RGB(88, 216, 255)`, gradient `RGB(0, 81, 255)`
- Win popup image: `76077537030305`
- Event block: `NEON RUSH KARTS` and `NEON RUSH WINS REQUIRED`
- Win popup image remains `76077537030305`

### FrostbiteRally

- Event ID: `FrostbiteRally`
- Rotation tier: `Minor`
- Display name: `FROSTBITE RALLY`
- Environment profile: `Default` until a dedicated Frostbite environment is authored
- Event wins attribute: `FrostbiteRallyWins`
- Blood Moon gameplay modifiers: none
- Stage awards: stage 16 = 1 win, stage 18 = 2 wins, stage 20 = 3 wins
- Progress colors: background `RGB(204, 238, 255)`, gradient `RGB(115, 173, 255)`
- Event block: `FROSTBITE RALLY KARTS` and `FROSTBITE RALLY WINS REQUIRED`
- Kart unlocks and kart buttons: intentionally not configured yet
- Frostbite Rally is enabled for live and Studio rotation testing without adding
  any event kart models, catalog entries, or buttons.

## Required Configuration

Every enabled event must define or intentionally omit these fields:

- `id`: stable identifier used by `ActiveEventIds`, attributes, and UI filters
- `displayText` and `displayColor`: banner and event theme
- `environmentName`: environment to apply while active
- `effects`: only modifiers that belong to this event
- `progressUi`: background color, gradient color, wins attribute, maximum wins,
  and unlock definitions
- `stageWinAwards`: authoritative event-win rewards by minimum stage
- `kartWinsAttribute`: authoritative event-kart currency
- `kartRequirementLabel`: event-specific requirement wording
- `eventBlockUi`: billboard title, `InfoLabel` text, and colors
- `winPopupImageAssetId`: event-specific reward popup image
- `schedule`: published timing configuration
- Studio debug fields when manual lifecycle testing is needed

Do not copy Blood Moon effects into a simpler event. Reuse only the systems the
new event actually needs.

## UI Wiring

- `EventProgress` must consume the active event payload, including colors,
  unlock markers, event wins, and unlock names.
- `EventBillboard.TextLabel` is the dynamic event or kart title.
- `EventBillboard.InfoLabel` is the dynamic requirement or status text and
  remains white unless a separate design decision says otherwise.
- `EventBlock` uses its SurfaceGui `CountdownLabel` for the event countdown.
- `EventKartButtons` must show only the folder for the active event.
- `KartFrame` must contain every event kart in its catalog, with the matching
  source folder, event ID, display name, image, colors, and product key.
- Owned event karts remain equippable after the event ends.
- Unowned paid event karts are visible and purchasable only while their event is
  active.
- Unowned win-unlocked event karts are displayed through the event's normal
  world/progress unlock flow and appear in `KartFrame` after ownership.
- Event end must remove event-only world buttons, restore normal UI, and restore
  the normal environment and gameplay modifiers.

Source audit note: this checkout currently has an empty
`Workspace.Worlds.World1.EventKartButtons` folder and no
`ServerStorage.EventKartButtons` template folder. The event button models must
be resynced into those intended source locations before the physical event
buttons can be tested or shipped.

## Lifecycle Test Checklist

Test each event in Studio without waiting for the published schedule:

1. Startup before the event: event block, countdown, and normal UI are correct.
2. Activation: active event state, environment, progress frame, billboard,
   system chat, and event colors update.
3. Kart availability: only the active event's buttons are present; KartFrame
   lists the active paid kart and owned event karts correctly.
4. Progress: event wins, stage awards, unlock markers, and requirement text
   use the active event rather than hardcoded Blood Moon values.
5. Reward popup: the active event's popup image and colors are used.
6. Ending: active state clears, event-only effects and buttons are removed,
   and normal state returns.
7. Grace period: the next event block and countdown appear without leaving
   stale event buttons, colors, or highlights behind.
8. Rejoin and respawn: active event state is reconstructed correctly for a
   player joining late or respawning during a transition.

## Studio Debug Rules

- `debugStudioEventId = "Random"` starts with a random enabled `Major` event.
- When a Major event ends, Studio selects a random enabled `Minor` event; when
  that Minor event ends, it selects a random enabled Major event.
- The selector avoids repeating the previous event and falls back to any enabled
  debug event only when the requested tier has no candidate.
- Studio debug timing must be short enough to test, but long enough to verify
  activation, gameplay, ending, and cleanup.
- Published servers must continue using the configured live schedules.

## Live Rotation

- Tiered events use `CoreConfig.liveEvents.rotation` instead of independent
  recurring start times while rotation is enabled.
- The rotation begins at `rotationStartUnix` with a deterministic random Major,
  then alternates to a deterministic random Minor and back to a Major.
- Each event's `schedule.activeDurationSeconds` and
  `schedule.graceDurationSeconds` define its live active and transition times.
- The initial rotation event uses the full first-event countdown, matching the
  original Blood Moon launch behavior. This is a one-time global exception;
  the first Minor event after it is not treated as a first event.
- After the initial event, the in-game `EventFrameList` shows only the first
  upcoming rotation event, and only during its final 24-hour pre-event window.
  The immediate next window is resolved while the current event is active so
  the countdown can appear without waiting for the handoff.
- The `version` value is part of the rotation identity; bump it when changing
  the event pool or selection rules intentionally.
- Untiered events such as `Weekend2x` remain independently scheduled, and
  disabled events are not candidates. Frostbite Rally is an enabled Minor
  candidate, but its kart catalog remains intentionally empty.
