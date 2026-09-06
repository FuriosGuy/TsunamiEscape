# Experience Notifications Implementation Plan

Status: implemented adapter, readiness routing, live-event routing, join
opt-in prompt, and separate offline readiness sync. Live delivery is enabled
only for main universe `9824719186`; Studio and DEV remain disabled.

## Roblox System Findings

Experience Notifications are separate from:

- In-game `NotificationFrame` messages.
- EventBoard `SocialService:PromptRsvpToEventAsync`.
- `FunnelAnalytics` and `EconomyAnalytics`.
- Roblox platform Experience Events.

Roblox requires a notification string created in Creator Dashboard. The string's
message ID is sent from a server-side request. The request currently supports
`type = "MOMENT"`, parameters, optional `joinExperience.launchData`, and
`analyticsData.category`.

Example payload shape:

```lua
{
    payload = {
        messageId = "notification-string-asset-id",
        type = "MOMENT",
        analyticsData = {
            category = "BloodMoon",
        },
        joinExperience = {
            launchData = "event=Bloodmoon&source=notification",
        },
    },
}
```

`analyticsData.category` is the stable reporting group shown in the Creator
Dashboard. Use categories such as `BloodMoon`, `AdminAbuse`, `Race`, and
`Update`, not unique timestamps or platform event IDs. Separate notification
strings are needed for meaningful A/B tests.

The dashboard reports opted-in users, impressions, clicks, CTR, turn-off rate,
and dismiss rate. Statistics require enough impressions. Delivery is not
guaranteed: users must be eligible and opted in, and each user has a daily
per-experience throttle plus broader spam prevention.

Notifications must be personalized and actionable. Do not use them as generic
advertising, false urgency, purchase pressure, or a gameplay requirement. Do not
send one notification for every `LiveEventService.Refresh` call.

## Approved Trigger Policy

Experience Notifications should be limited to meaningful return-to-game actions:

| System | Use notification? | Rule |
| --- | --- | --- |
| Daily Reward | Yes | Send once when a claimable reward becomes available. |
| Spin Wheel | Yes | Send once when configured free-spin cooldown finishes. Never notify for the five-minute ad cooldown. |
| Group Reward | Yes | Send once when the player is eligible and the reward remains unclaimed. |
| Blood Moon | Yes | Major-event notification; higher priority than 2X Weekend. |
| Admin Abuse | Yes | Major-event notification when explicitly configured. |
| Blood Moon rewards | No | The player is already in-game; use the existing in-game notification UI. |
| Playtime Rewards | No | Session timers are not useful after the player leaves. |
| Temporary Boosts | No | Expiry and purchase-related timers are too frequent and commercial. |
| Prompt Buy | No | Do not use platform notifications as product advertising. |
| Race timers | No | Keep race countdowns inside the game. |
| Spin ad cooldown | No | Five-minute reminders would be spammy. |

The configured Spin Wheel free-spin cooldown and Daily Reward triggers use a
priority order: Daily Reward, Spin Wheel, then eligible Group Reward. The game
adapter accepts at most one notification per player per UTC day, matching
Roblox's delivery limit. Group Reward notifications require server-verified
eligibility and an unclaimed reward; never imply that a reward is available
when another required action is still pending.

Official reference:

- https://create.roblox.com/docs/production/promotion/experience-notifications

## Permission Prompt

The permission prompt is separate from both notification delivery and EventBoard
RSVP. Current implementation checks eligibility once after each join, with a
short loading delay. Roblox suppresses the prompt when the player is ineligible,
already opted in, or recently saw it. It never attaches the prompt to EventBoard
or a reward frame.

Recommended flow:

1. The client waits for the configured post-join delay.
2. The client calls `ExperienceNotificationService:CanPromptOptInAsync()` inside
   `pcall()`.
3. If eligible, the client calls
   `ExperienceNotificationService:PromptOptIn()`.
4. No custom permission result is assumed.

Do not show it after a Daily Reward, after a Spin Wheel reset, after a Group
Reward check, during Prompt Buy, or from EventBoard. Those systems may produce
eligible platform notifications, but they do not own permission prompting.

## Recommended Architecture

### 1. Add one server-only adapter

`src/ServerScriptService/Modules/ExperienceNotificationService.luau` is the
only project adapter allowed to call Roblox's Open Cloud notification package.
It should be the only project module allowed to call the Roblox Open Cloud
notification package.

Responsibilities:

- Validate `Player.UserId`, message ID, category, and launch-data length.
- Construct the `MOMENT` payload.
- Call the server-side `OpenCloud.V2.UserNotification` package.
- Return structured success/error information.
- Rate-limit locally before calling Roblox.
- Log failures through `DebugModule`, never raw `print` or `warn`.

Keep the package in `ServerScriptService`. Never place an API key in source,
`CoreConfig`, `ReplicatedStorage`, or a published place. If an external Open
Cloud workflow is later used for offline audiences, keep its key in the existing
GitHub Actions secret system and keep that workflow separate from gameplay code.

### 2. Add narrow configuration

Extend the existing analytics configuration area in
`src/ReplicatedStorage/Modules/Shared/CoreConfig_Shared.luau` only with
notification settings:

- Master enabled flag.
- Studio disabled by default.
- Per-event message IDs.
- Stable analytics categories.
- Local notification budget, deduplication keys, and allowed trigger names.
- Separate trigger settings for Daily Reward, configured Spin Wheel readiness,
  eligible unclaimed Group Reward, major live events, and major unlocks.

Do not put schedules, user lists, or secrets in this configuration. The existing
`LiveEventService` and `LiveEventSchedule` remain the only event schedule source
of truth.

### 3. Integrate on event transitions only

The smallest event integration is a transition signal or snapshot callback from
`src/ServerScriptService/Modules/LiveEventService.luau`. It must fire only when
the active event set changes. `LiveEventManager.server.luau` remains the boot and
shutdown owner.

`ExperienceNotificationManager.server.luau` evaluates readiness when player
data becomes loaded and when Daily Reward, configured free Spin Wheel, or Group Reward
cooldowns reach their stored Unix timestamps. Live-event notifications fire
only on `ActiveEventIds` transitions, never on refresh polling. Local session
budget remains one successful send per player to reduce spam.

Blood Moon and Admin Abuse can use separate categories and message IDs. 2X
Weekend should not compete with a major-event notification unless an explicit
priority policy is configured.

### 4. Keep EventBoard RSVP separate

`src/StarterPlayer/StarterPlayerScripts/EventBoard.client.luau` owns the current
in-game RSVP prompt. Do not replace RSVP with Experience Notifications. RSVP is a
platform event action; Experience Notifications are a separate opted-in delivery
channel. The EventBoard is not a permission-prompt entry point or a replacement
for the server notification adapter. Its existing `NOTIFY ME` action remains
RSVP-only.

If a notification later includes `joinExperience.launchData`, add a small
namespaced join-data router. `ReferralService.luau` already reads
`Player:GetJoinData()`, so the router must ignore unrelated keys and never alter
referral handling. It may route a player to an event location only after
validating the event ID against the current server schedule.

### 5. Offline readiness sync

`TsunamiEscape-Automation/tools/RobloxNotificationSync/Sync-RewardNotifications.ps1`
handles players who are not currently in the main experience. The hourly
`Main Reward Notifications` workflow:

- Reads `PlayerStats_v1` through Open Cloud without changing player data.
- Uses the Presence API and skips players active in the target universe.
- Checks group membership only when Group Reward is otherwise ready.
- Selects one reward by the same priority as the in-game manager.
- Sends no Blood Moon reward, event, race, product, or promotional reminders.
- Uses bounded pages, users, notifications, retries, and request delays.

Roblox enforces one notification per user per experience per day. The scanner
also sends at most one candidate notification per user per run. DEV config is
disabled, so private DEV state cannot leak notifications.

### 6. Keep existing analytics focused

Do not route notification impressions or clicks through `FunnelAnalytics`; Roblox
already owns those metrics in the Experience Notifications dashboard.

Use `FunnelAnalytics` for in-game actions such as opening an event panel,
starting RSVP, joining a race, or completing a reward flow. Use
`EconomyAnalytics` only for authoritative Wins and XPSpeed sources and sinks.

The adapter may log send-result diagnostics, but a successful API response must
not be treated as proof that a notification was delivered, viewed, or clicked.

## Files

Expected implementation scope:

- New: `src/ServerScriptService/Modules/ExperienceNotificationService.luau`
- New: `src/ServerScriptService/ExperienceNotificationManager.server.luau`
- New: `src/StarterPlayer/StarterPlayerScripts/ExperienceNotificationPrompt.client.luau`
- Existing: `src/ReplicatedStorage/Modules/Shared/CoreConfig_Shared.luau`
- Required external package: `ServerScriptService.OpenCloud.V2.UserNotification`

Do not modify datastore, reward, race, or RSVP logic unless testing proves a
direct notification integration defect.

## Security and Reliability

- Server-only delivery; clients cannot request arbitrary notifications.
- Allowlist message IDs, categories, and trigger names.
- Validate all user IDs and payload lengths.
- Apply per-user and per-trigger cooldowns.
- Never expose API keys to the client or published place.
- Use `pcall`, structured errors, and `DebugModule` diagnostics.
- Treat Roblox throttling and non-delivery as normal outcomes.
- Never gate gameplay or rewards on notification permission or delivery.

## Verification

1. Keep Studio delivery disabled by default.
2. Install official `OpenCloud.V2.UserNotification` package under
   `ServerScriptService`.
3. Test one controlled published-server recipient.
4. Record status code, error code, category, and local cooldown behavior.
5. Verify malformed or unrelated `launchData` is rejected before API call.
6. Compare dashboard category results against local send diagnostics.
7. Confirm no duplicate sends during repeated live-event refreshes.
8. Confirm Spin Wheel notification never fires for the five-minute
   ad cooldown.
9. Confirm Group Reward notification requires server-verified eligibility and an
   unclaimed reward.
10. Confirm EventBoard RSVP and existing in-game notifications remain unchanged.

Do not claim delivery from a successful API request. Only Roblox dashboard data
can confirm impressions and engagement.

## Current Rollout

1. Keep Studio delivery disabled by default.
2. Install the official `OpenCloud.V2.UserNotification` package under
   `ServerScriptService`.
3. Validate one controlled published-server recipient, API errors, throttling,
   cooldowns, and dashboard reporting.
4. Configure `ROBLOX_NOTIFICATION_MAIN_API_KEY` in the private
   `FuriosGuy/TE-Automation` repository with Data Store read and User
   Notification create permissions restricted to main universe.
5. Run the scanner without `-Apply` first. Add `-Apply` only after dry-run
   results and one controlled live recipient are verified.
6. Add more categories only after first categories have useful metrics.

This is a low-coupling server feature. It does not require a datastore,
movement, reward, EventBoard, or event-schedule rewrite.
