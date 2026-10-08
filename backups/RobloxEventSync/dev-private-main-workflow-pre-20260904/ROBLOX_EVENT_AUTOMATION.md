# Roblox Event Automation

## Purpose

This document describes how in-game live events can automatically create and
maintain matching Roblox Experience Events, such as:

`https://www.roblox.com/events/4040806533699863314`

The in-game event and Roblox platform event are separate systems. The game
controls gameplay, rewards, lighting, waves, and UI. The platform event controls
public event page, event schedule, event thumbnail, RSVP, and Roblox
notifications.

There is no game-native setting that automatically converts an in-game
schedule into a platform Experience Event. Automation requires small external
scheduled task using Roblox Open Cloud. Current tool uses generic event
definitions and schedule kinds matching `LiveEventSchedule`.

## Roblox API Support

Roblox currently exposes an experimental Game Events API:

```text
GET    /virtual-events/v3/universes/{universeId}/game-events
GET    /virtual-events/v3/game-events/{eventId}
POST   /virtual-events/v3/universes/{universeId}/game-events
PATCH  /virtual-events/v3/game-events/{eventId}
DELETE /virtual-events/v3/game-events/{eventId}
```

The create, update, list, and delete operations require an Open Cloud API key
or OAuth 2.0 authentication. An API key needs the `universe.event:write`
permission for creation, updates, and deletion. The synchronizer also needs
`universe.event:read` because it lists and verifies events before and after a
mutation. For this group-owned experience, the payload includes group ID
`13706307`; the authenticated account must have group event configuration
permission. Roblox currently rejects event ID `GET`, `PATCH`, and `DELETE`
requests when `Restrict by Experience` is enabled, even when the key has the
event read/write operations. Use a dedicated event key with `Restrict by
Experience` disabled, limited to `universe.event` read/write operations. The
key remains limited by the authenticated account's group permissions.

The current OpenAPI definition marks these endpoints as `Experimental` and
does not mark them as usable through Roblox in-game `HttpService`. Treat them
as external Open Cloud operations, not as game-server requests.

Official references:

- [Roblox Game Events API](https://create.roblox.com/docs/cloud/reference/domains/apis)
- [Roblox API scopes](https://create.roblox.com/docs/cloud/reference/scopes)
- [Experience events](https://create.roblox.com/docs/production/promotion/experience-events)
- [Open Cloud API keys](https://create.roblox.com/docs/cloud/auth/api-keys)

The API is experimental, so Roblox may change request fields or behavior. The
automation should validate responses and fail safely instead of deleting or
recreating events when a response is unexpected.

## Recommended Architecture

```text
LiveEventSchedule / CoreConfig.liveEvents
        |
        v
External generic event synchronizer
        |
        | Open Cloud API, secured API key
        v
Roblox Experience Event
        |
        +--> Public event page, RSVP, Roblox notifications

Game server
        |
        +--> LiveEventSchedule / LiveEventService
        +--> Blood Moon gameplay and rewards
        +--> EventBoard display and RSVP prompt
```

The external synchronizer and game should use same UTC schedule rules. Neither
system should use the other as gameplay authority.

## Sequential Publishing

DEV configuration uses `publishPolicy.mode = "one-per-event-key"`. Synchronizer
selects one current window plus one staged next window for every enabled event
key. Blood Moon and 2X Weekend can therefore coexist. It never creates a second
window for same event key beyond that pair.

For recurring events, final visibility is configured as `public`, while the
next window is created as `private`. Once the previous active window ends, the
next event is patched to `public`. This prepares Roblox event pages and RSVP
notifications without exposing next occurrence early. When no previous window
is active, next scheduled occurrence is public immediately. Different event
keys do not block each other.

Each recurring window has separate state key:

```text
eventKey|windowStartUtc
```

This prevents reusing ended platform event ID for new cycle. Existing event IDs
are only seed mappings for matching window; future windows create once, then
reuse stored ID for later updates.

Adding future event still needs one `events[]` entry with stable `eventKey`,
title, metadata, and schedule kind. Dates need not be manually entered for
recurring schedules. Platform event IDs cannot be inferred before Roblox
creates them, so returned IDs are stored in ignored `event-state.json`.

## Generic Event Example

Assume Blood Moon cycle has:

- `3 days` active
- `3 days` grace period
- Blood Moon gameplay begins at the active start time
- The public platform event covers only the active period

Example UTC schedule:

```text
Start: 2026-09-05T00:00:00Z
End:   2026-09-08T00:00:00Z
```

The synchronizer would:

1. Calculate next active window in UTC.
2. Check whether the managed event already exists.
3. Update it with `PATCH` if the timing or metadata changed.
4. Create it with `POST` if no event exists for that cycle.
5. Store the returned Roblox `eventId` externally.
6. Never create a second event merely because a scheduler run was retried.
7. Wait until current event ends before publishing next managed event.

The next cycle might be:

```text
Grace:  2026-09-08T00:00:00Z to 2026-09-11T00:00:00Z
Active: 2026-09-11T00:00:00Z to 2026-09-14T00:00:00Z
```

These dates are only an example. The production schedule should be defined in
one configuration file and converted to RFC 3339 UTC timestamps.

## Illustrative API Request

The exact request schema must be checked against Roblox's current OpenAPI
definition before production use. The following shows the intended flow and
does not contain a real secret:

```http
POST https://apis.roblox.com/virtual-events/v3/universes/9824719186/game-events
x-api-key: ${ROBLOX_EVENT_API_KEY}
Content-Type: application/json

{
  "title": "BLOOD MOON",
  "subtitle": "SURVIVE THE BLOOD MOON",
  "description": "Survive the Blood Moon and earn exclusive rewards.",
  "startTime": "2026-09-05T00:00:00Z",
  "endTime": "2026-09-08T00:00:00Z",
  "visibility": "public",
  "groupId": 13706307,
  "placeId": 86681121894203,
  "categories": [
    { "category": "newContent", "rank": 0 }
  ],
  "thumbnails": [
    { "mediaId": 97220360470213, "rank": 0 }
  ],
  "config": {
    "notificationAudience": "rsvp"
  }
}
```

`4040806533699863314` is an event ID, not a thumbnail ID. The reference Blood
Moon event from universe `9824719186` uses category `newContent` at rank `0` and
thumbnail media ID `97220360470213`. The reference `2X WEEKEND` event
`1346050110383063660` uses thumbnail media ID `75145457809023`. Thumbnail must
be approved Roblox media asset, not an in-game image field.
`visibility` uses lowercase `public` or `private`. Still verify the response
because the endpoint is experimental and thumbnail processing can be
asynchronous.

## Idempotency and Duplicate Protection

The scheduler must be safe to run repeatedly. Recommended external state:

```json
{
  "version": 2,
  "events": {
    "Bloodmoon|2026-09-04T23:00:00.000Z": {
      "eventId": "4040806533699863314",
      "startTime": "2026-09-04T23:00:00.000Z",
      "endTime": "2026-09-07T23:00:00.000Z"
    }
  }
}
```

Rules:

- Use deterministic `eventKey|windowStartUtc` state key.
- Store the Roblox event ID outside the Roblox game source tree.
- `PATCH` stored event for same window instead of creating duplicate.
- If the stored ID returns `404`, list current events and verify before creating.
- Do not delete unrelated events.
- Do not match by title alone because multiple events can have the same title.
- Keep a log of every create, update, failure, and returned event ID.
- Policy limits synchronizer to one active/upcoming managed event per event key.

Roblox currently documents a maximum of 10 ongoing or upcoming events, so
keeping old cycles tidy is important.

## Where the Scheduler Can Run

Possible choices:

| Option | Cost profile | Notes |
| --- | --- | --- |
| GitHub Actions | Usually free for a small personal/public workflow | Good for an occasional daily sync; store the API key as an encrypted repository secret. |
| Cloudflare Worker plus scheduled trigger | Often free within the provider's free tier | Good for a small always-on scheduler; verify current limits. |
| Existing VPS or backend | Depends on the server | Best if another service already runs continuously. |
| Local computer/task scheduler | No hosting fee | Not reliable if the computer is off or asleep. |
| Manual Creator Dashboard | No automation setup | Safest fallback while the API remains experimental. |

For this game, daily scheduler is enough. Events do not need per-minute creator
API loop. Run after each event ends, or every 15-60 minutes, plus manual retry.

## Do I Need to Pay?

There is no separate Roblox fee documented for:

- Creating an Open Cloud API key.
- Calling the Game Events create/update/list endpoints.
- Creating the Experience Event itself.
- Hosting the event page or accepting RSVPs.

You may still pay for optional services:

- External hosting after exceeding a provider's free tier.
- Paid advertising or promotion.
- Custom external monitoring or database services.
- Asset production, if using paid tools or contractors.

For a small daily Blood Moon synchronizer, GitHub Actions or a provider's free
tier should normally be sufficient. Check the provider's current limits before
depending on it for production. Roblox API rate limits still apply, so the
scheduler should back off on HTTP `429` responses instead of retrying rapidly.

## API Key Security

Never put the event-management API key in:

- `ReplicatedStorage`.
- A client LocalScript.
- `ServerScriptService` source committed to the project.
- A public Git repository.
- A Roblox place attribute or StringValue.
- A screenshot, log, or shared chat message.

Use an encrypted external secret. Restrict the key to:

- Only the required universe.
- Only `universe.event:write` and any separately required read permission.
- A fixed IP range when the hosting provider supports a stable outbound IP.
- An expiration date when there is a key-rotation process.

The key is effectively a password. If it is exposed, revoke or regenerate it
immediately.

## Thumbnail Handling

The platform event thumbnail is separate from the in-game EventBoard image.
The scheduler should use an approved Roblox asset ID and verify the returned
event object after creation.

If Roblox rejects or delays the thumbnail, the event may show a placeholder or
the experience's primary thumbnail. The scheduler should log the returned
thumbnail fields and should not silently replace the event with a duplicate.

## Failure Behavior

If the external scheduler fails:

- Existing in-game Blood Moon gameplay continues using the server schedule.
- Existing Roblox platform events remain unchanged.
- The scheduler retries with exponential backoff for temporary failures.
- Authentication failures stop retries and produce an operator alert.
- HTTP `429` responses respect `Retry-After` when provided.
- A malformed response never triggers deletion or mass recreation.

This keeps marketing/event-page synchronization from becoming a gameplay
dependency.

## Recommended First Version

Start with a small external command or scheduled workflow that:

1. Reads `ROBLOX_EVENT_API_KEY` from a secret store.
2. Reads DEV universe ID `9799168239` and DEV place ID `116587108840614` from configuration.
3. Computes next window for generic configured events.
4. Selects current event plus one staged next event per event key.
5. Lists existing events.
6. Updates matching managed events or creates missing event per event window.
7. Stages next recurring window privately, then publishes it after previous
   window ends.
8. Verifies title, schedule, place, privacy, and thumbnail in response.
9. Writes per-window event ID state.

Do not connect this directly to player-triggered game code. The game should
continue using its existing live-event schedule, while the external task
handles Roblox platform-event publishing.

## First Version In This Project

The generic synchronizer is located outside `src`:

```text
tools/RobloxEventSync/Sync-BloodMoonEvent.ps1
tools/RobloxEventSync/config.example.json
tools/RobloxEventSync/config.github-dev.json
.github/workflows/roblox-event-sync.yml
```

Setup:

```powershell
Set-Location C:\RobloxProjects\SpeedBrainrotDev\tools\RobloxEventSync
Copy-Item config.example.json config.json
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
```

Put the API key in the local `.env` file as
`ROBLOX_EVENT_API_KEY=your-key`. The `.env` file is ignored by this project and
is loaded only by the external PowerShell tool. Process environment variables
take priority over `.env`, so CI systems can continue using secret variables.
The `.env` file is plain text on the local computer and must still be protected
like a password.

Review `events[]`, metadata, and schedule definitions in `config.json`. The
script is dry-run by default:

```powershell
.\Sync-BloodMoonEvent.ps1
```

Only after reviewing the printed payload should it be allowed to mutate Roblox:

```powershell
.\Sync-BloodMoonEvent.ps1 -Apply
```

The script lists and verifies events, enforces one-window-per-event-key
publishing, stages one next window privately when configured, avoids reusing
ended event IDs, retries temporary `429`/`5xx` failures, verifies the returned
title/schedule/place/visibility, and writes per-window IDs to ignored
`event-state.json`. It has no delete operation. Use `-NowUtcOverride` for a
deterministic dry-run without making API requests.

## GitHub Actions Setup

Workflow is included at:

```text
.github/workflows/roblox-event-sync.yml
```

First workflow targets DEV only:

```text
Universe: 9799168239
Place:    116587108840614
Config:   tools/RobloxEventSync/config.github-dev.json
```

Setup steps:

1. Commit and push workflow, synchronizer, and DEV config to GitHub. Never
   commit `config.json`, `.env`, `event-state.json`, or any API key.
2. Open GitHub repository `Settings` > `Secrets and variables` > `Actions`.
3. Select `New repository secret`.
4. Set name exactly to `ROBLOX_EVENT_API_KEY`.
5. Paste Roblox API key value, then save. GitHub masks secret in workflow logs.
6. Confirm Roblox key has `universe.event:read` and `universe.event:write`,
   targets DEV universe `9799168239`, and authenticated account has required
   group event permission. Keep `Restrict by Experience` disabled if Roblox
   rejects event ID reads or patches.
7. Open GitHub `Actions` > `Roblox Experience Event Sync` > `Run workflow`.
8. Review output. It must show DEV universe, selected windows, visibility, and
   successful response verification.

Workflow runs every 15 minutes in UTC. GitHub scheduled workflows can be
delayed during load, so manual dispatch remains available. `concurrency` keeps
overlapping runs queued instead of allowing duplicate create attempts.

Local dry-run examples:

```powershell
Set-Location C:\RobloxProjects\SpeedBrainrotDev
pwsh -NoProfile -File .\tools\RobloxEventSync\Sync-BloodMoonEvent.ps1 `
  -ConfigPath .\tools\RobloxEventSync\config.github-dev.json

# Simulate Weekend2x active. Still no API request.
pwsh -NoProfile -File .\tools\RobloxEventSync\Sync-BloodMoonEvent.ps1 `
  -ConfigPath .\tools\RobloxEventSync\config.github-dev.json `
  -NowUtcOverride 2026-09-05T16:00:00Z
```

Second dry-run should show active `Weekend2x` public plus its next window
private. Upcoming Blood Moon remains public because no prior Blood Moon window
is active in that simulation. Do not use `-Apply` until API key scope and
printed payloads are reviewed.

For production, copy `config.github-dev.json` to separately reviewed
production config with main universe/place IDs, then use separate GitHub
environment and secret. Do not make workflow target production by changing DEV
IDs casually.

## Bottom Line

Automatic live-event Experience Events are possible through Open Cloud, but
require external scheduler and secure credentials. There is no Roblox charge
documented for event API itself. Simplest low-cost production design is daily
GitHub Actions or Cloudflare scheduled task that syncs generic event catalog,
keeps next same-key windows private until current windows end, and leaves
gameplay server-authoritative.
