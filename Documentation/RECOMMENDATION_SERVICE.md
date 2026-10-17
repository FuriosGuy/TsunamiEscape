# RecommendationService Study

Updated: 2026-09-04

## Summary

Roblox `RecommendationService` is an in-experience recommendation engine for curated 2D/3D assets, minigames, activities, and other playable content. It is not an event scheduler, RSVP system, product-prompt system, or external notification API.

Best SpeedBrainrot use: optional `PLAY NEXT` cards after a completed race or inside a menu. Do not use recommendation results to decide reward eligibility, purchases, equipment, teleports, or progression.

References:

- [RecommendationService API](https://create.roblox.com/docs/reference/engine/classes/RecommendationService)
- [Recommendation systems guide](https://create.roblox.com/docs/production/recommendation)
- [RecommendationPages](https://create.roblox.com/docs/reference/engine/classes/RecommendationPages)
- [RecommendationActionType](https://create.roblox.com/docs/reference/engine/enums/RecommendationActionType)

## API Flow

1. Register content with `RegisterItemAsync`.
2. Fetch personalized results with `GenerateItemListAsync`.
3. Display returned items in a controlled UI.
4. Log one impression when an item becomes fully visible.
5. Log a real quality action after the player meaningfully uses the item.
6. Monitor results in Creator Hub under `Engagement > Recommendation Service`.

### Important IDs

- `ReferenceId`: stable developer-owned ID. Use it to resolve local rendering metadata.
- `ItemId`: Roblox-generated recommendation ID. Use it for impression/action logs.
- `TracingId`: recommendation-session ID returned with generated results. Send it with correlated logs.

Never log raw product IDs, raw `ReferenceId` values, or dummy tracing IDs as recommendation events. Roblox warns this creates invalid training data.

### Request fields

`GenerateItemListAsync` accepts:

- `ConfigName`: ranking configuration, such as `MaximizePlays` where supported.
- `LocationId`: developer-defined surface name, such as `PostRace` or `Lobby`; cannot be `Other`.
- `PageSize`: bounded result count.
- `BoostCustomTags`: currently supports boosting one tag.
- `CustomContexts`: optional ranking context; server requests can include the player user ID.

Returned items can include `ItemId`, `ReferenceId`, `TracingId`, creator data, attributes, and custom tags. Keep full display metadata in the local catalog rather than depending on recommendation payload text.

## Good Candidates

Start only when at least two meaningful activities exist:

- Race minigame.
- Future alternate race mode.
- Future challenge mode.
- Future playable world or event activity.

Avoid using it for:

- EventBoard or RSVP.
- Daily, group, or spin reward readiness.
- `PromptBuyProductsFrame`.
- Blood Moon unlocks.
- Forced product recommendations.

Those systems need deterministic server rules or direct UI messaging.

## Non-Invasive Implementation Plan

### 1. Server catalog adapter

Create one server-owned `RecommendationCatalogService` with methods to:

- Register, update, and remove catalog items.
- Fetch a bounded recommendation page.
- Resolve returned `ReferenceId` to a known local item.
- Record impressions/actions with returned `ItemId` and `TracingId`.
- Wrap yielding calls in `pcall` and return an empty fallback on failure.

Use dedicated recommendation config for stable IDs, content types, tags, destinations, and UI metadata. Use UUID-like stable `ReferenceId` values where practical.

### 2. One UI surface

Add one optional carousel controller for the post-race result screen or menu. Fetch on surface open, cache the page for the session, and hide cleanly when the API returns no results.

### 3. Analytics rules

- Log one `View` impression per item per session when fully visible.
- Use `Duration = 1` for static cards unless actual view duration matters.
- Log `Play` only after the player enters the recommended activity and passes a quality threshold, such as 60 seconds.
- Log `Purchase` only after a confirmed purchase.
- Do not log traffic from random picks, search, or non-recommendation UI.

### 4. Server revalidation

Filter results against the current server catalog before display. Recheck eligibility on click. Client-sent recommendation IDs must never grant rewards, unlock items, authorize purchases, or perform unrestricted teleports.

## Testing

`RegisterItemAsync` can return HTTP 403 in Studio even from a server script because Studio is not issuing the request from a Roblox server. Test registration and updates in a published experience through Roblox. Use Studio for catalog mapping, fallback UI, and local logging-shape tests.

Recommendation calls yield. Never call them every frame or from repeated player loops. Fetch on demand, bound page size, cache results, use `pcall`, and clean up any task or connection when the UI closes or player leaves.

## Decision

Do not implement yet unless the game has at least two playable recommendation candidates and a clear UI surface. First candidate should be a post-race `PLAY NEXT` carousel. Keep existing event, reward, product, and notification systems unchanged.
