# RecommendationService and Notification Audit

Updated: 2026-09-04

## Executive Summary

Roblox `RecommendationService` is an in-experience recommendation engine. It can register content, return personalized recommendation items, and record impressions/actions. It is not a replacement for `ExperienceNotificationService`, Roblox experience notifications, EventBoard RSVP, or product-prompt logic.

Recommended use for SpeedBrainrot: an optional in-game carousel such as "PLAY NEXT" after a race or in a menu. Do not connect it directly to reward eligibility, notification readiness, purchases, or server-authoritative progression.

Official references:

- [RecommendationService API](https://create.roblox.com/docs/reference/engine/classes/RecommendationService)
- [Recommendation systems guide](https://create.roblox.com/docs/production/recommendation)
- [RecommendationPages response format](https://create.roblox.com/docs/reference/engine/classes/RecommendationPages)
- [RecommendationActionType enum](https://create.roblox.com/docs/reference/engine/enums/RecommendationActionType)
- [Experience notifications](https://create.roblox.com/docs/production/promotion/experience-notifications)

## Current Notification Eligibility Audit

### Group reward: safe against false positives

`ExperienceNotificationManager` checks all of the following before `GroupRewardReady` can be sent:

1. Player is still present and `Data_Loaded == true`.
2. `VerifyRewardNextClaimUnix <= os.time()`.
3. Server-side `player:IsInGroup(13706307)` succeeds and returns `true`.
4. `ExperienceNotificationService` accepts the allowlisted message ID and the Roblox API returns HTTP 200.

The claim path in `LevelingService` uses the same group ID, server membership check, data-load requirement, and cooldown attribute. `VerifyRewardClaimed` is not required because this reward is recurring; cooldown is its eligibility source of truth.

A group-membership API failure is treated as not eligible. This can miss a notification, but cannot create a notification for a confirmed non-member. Joining the group while already in-game is not observed automatically, so the player may need to rejoin or trigger a later readiness evaluation.

Relevant files:

- `src/ServerScriptService/ExperienceNotificationManager.server.luau`
- `src/ServerScriptService/Modules/LevelingService.luau`
- `src/ReplicatedStorage/Modules/Config/CoreConfig.luau`

### Daily reward: safe during valid configuration

The manager requires `Data_Loaded == true` and `DailyRewardNextClaimUnix <= os.time()`. The claim service applies the same cooldown rule. Current daily reward configuration supplies the reward definitions.

Remaining weakness: the notification manager does not independently confirm that `DailyRewardsConfig.GetReward(currentDay)` returns a valid reward. A damaged or incomplete configuration could produce a ready notification while the claim path has nothing to grant. This is a configuration failure, not a client exploit. A future shared readiness API should make both notification and claim use the same `CanClaim` result.

### Spin wheel: eligibility is valid, message semantics need tightening

The manager requires either:

- `SpinWheelSpins > 0`, or
- `SpinWheelNextFreeSpinUnix <= os.time()`.

The server spin service also validates `Data_Loaded`, consumes spins server-side, and creates a free spin when its free timer is due.

Current weakness: `SpinWheelSpins` is one aggregate count containing free spins, rewarded-ad spins, and developer-product spins. Therefore `SpinWheelReady` can be true while the available spin did not originate from the free timer. The player is still allowed to spin, but wording such as "free Wheel spin" can be inaccurate. Split free and paid/ad balances, or change the message to "A Wheel spin is ready!" before relying on this notification.

### Live events: no per-player eligibility is expected

Blood Moon, Admin Abuse, and 2X Weekend notifications are based on the replicated server `LiveEventState.ActiveEventIds`. They are broadcast to players when an event becomes newly active. They do not claim rewards and therefore do not need group, inventory, or progression checks.

Current behavior intentionally suppresses the initial baseline and does not send an event-live notification to a player who joins after the event is already active. This prevents join spam but can cause a missed notice.

### Shared notification safety

`ExperienceNotificationService` adds these protections:

- Server-only caller.
- Player-parent validation.
- Allowlisted notification keys.
- Required configured message ID.
- Launch-data type and 200-byte limit.
- One send per message key per player session.
- Configurable total session send budget.
- API response must be HTTP 200 before recording a successful send.

Current config uses `maxSendsPerPlayerSession = 1`. If several rewards are ready together, evaluation order is Daily, Spin, then Group; later notices can be suppressed. This is under-notification, not an eligibility leak. The order or budget should be changed only after deciding notification frequency and moderation limits.

## RecommendationService: What It Does

`RecommendationService` supports a developer-owned content catalog:

- `RegisterItemAsync` registers content with a stable developer `ReferenceId`.
- `GenerateItemListAsync` returns personalized items in `RecommendationPages`.
- `GetRecommendationItemAsync` retrieves one item by Roblox `ItemId`.
- `LogImpressionEvent` records that a served item was viewed.
- `LogActionEvent` records a real action such as `Play` or `Purchase`.
- `LogPreferenceEvent` records preference signals such as follow, mute, or unmute.
- `UpdateItemAsync` changes visibility/tags.
- `RemoveItemAsync` removes an item.

Important IDs:

- `ReferenceId`: developer-owned stable ID used to find rendering metadata.
- `ItemId`: Roblox-generated ID. Use this for logging.
- `TracingId`: recommendation-session ID returned by `GenerateItemListAsync`. Use it for correlated logging.

Never pass a raw product ID, raw reference ID, or dummy tracing ID to impression/action logging. Roblox specifically warns that this corrupts recommendation metrics.

## Best Fit for This Game

### Good first surface

Use a small "PLAY NEXT" carousel after a completed race or from an optional menu. Candidate content can be:

- Race minigame.
- A future alternate race mode.
- A future challenge mode.
- A future world or event activity with a real playable destination.

Do not add an item until it has a real destination and stable UI metadata. One available activity gives the recommendation model little value.

### Poor first surfaces

- EventBoard live-state announcements.
- RSVP or `PromptRsvpToEventAsync`.
- Daily, group, or spin reward readiness.
- PromptBuyProductsFrame.
- Forced product recommendations.
- Blood Moon reward unlock checks.

These systems need deterministic eligibility or direct messaging. Recommendation ranking must not decide whether a player may receive a reward or purchase an item.

## Non-Invasive Integration Plan

### Phase 1: catalog and adapter

Create one server-owned adapter, for example `RecommendationCatalogService`, with a small API:

- Register/update/remove catalog items.
- Fetch a bounded recommendation page.
- Resolve returned `ReferenceId` through a server-owned catalog.
- Record impression/action using returned `ItemId` and `TracingId`.
- Wrap every yielding API call in `pcall` with bounded retry/fallback behavior.

Keep content definitions in a dedicated config module. Keep image IDs, titles, descriptions, destinations, and eligibility rules outside the Roblox recommendation payload where possible, matching Roblox's metadata separation guidance.

### Phase 2: one UI surface

Add one optional carousel controller for the post-race or menu surface. Fetch only when opened or after the result screen appears. Cache the current page for that session instead of polling. Hide the surface cleanly if the API is unavailable or returns no items.

### Phase 3: clean analytics

- Log one `View` impression when a card is fully visible, not every render.
- Use `Duration = 1` for static cards unless real viewing duration matters.
- Log `Play` only after the player actually enters the recommended activity and passes a quality threshold, such as 60 seconds.
- Log `Purchase` only after a confirmed purchase, never on button press alone.
- Use only IDs returned by `GenerateItemListAsync` for recommendation logs.
- Review Creator Hub at Engagement > Recommendation Service.

### Phase 4: eligibility reconciliation

Before display, filter recommendation results against current server-owned catalog state. Recheck eligibility when the player clicks. A recommendation is not permission to buy, equip, teleport, claim, or receive rewards.

## Runtime and Testing Notes

`RegisterItemAsync` can return HTTP 403 in Studio even when called by a server script because Studio is not issuing the request from a Roblox server. Register and update content from a published experience using the Roblox client/server environment. Use Studio only for UI fallback, catalog mapping, and logging-shape tests.

Recommendation API calls yield. Do not call them every frame, inside hot paths, or from every player repeatedly. Use a bounded request, cache, cleanup-aware task, and graceful empty-state UI.

## Current Follow-Up Issues

1. Split or rename spin availability state so `SpinWheelReady` cannot describe paid/ad inventory as a free spin.
2. Share daily/group/spin readiness functions between notification evaluation and claim services to prevent future rule drift.
3. Decide whether live-event notifications should support a separate JIP policy.
4. Update `src/ServerScriptService/OpenCloud/V2/UserNotification.luau` to use project `DebugModule` instead of raw `print`, replace deprecated `wait`, and fix its error-decode boolean typo. These do not currently create eligibility false positives, but they weaken diagnostics and error handling.
5. Do not implement `RecommendationService` until there are at least two meaningful playable recommendation candidates and a UI surface with measurable user choice.
