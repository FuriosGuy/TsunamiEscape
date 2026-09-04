# Roblox Event Automation

## Purpose

This document describes how Blood Moon can automatically create and maintain a
Roblox Experience Event, such as:

`https://www.roblox.com/events/4040806533699863314`

The in-game Blood Moon event and the Roblox platform event are separate
systems. The game controls gameplay, rewards, lighting, waves, and UI. The
platform event controls the public event page, event schedule, event thumbnail,
RSVP, and Roblox notifications.

There is no game-native setting that automatically converts an in-game
schedule into a platform Experience Event. Automation requires a small
external scheduled task using Roblox Open Cloud. The current OpenAPI schema
also exposes an optional cron recurrence block, but the six-day Blood Moon
cycle should be tested externally before relying on Roblox recurrence instead
of explicit event windows.

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
Blood Moon schedule
        |
        v
External scheduler
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

The external scheduler and the game should use the same UTC schedule rules.
Neither system should use the other as the gameplay authority.

## Blood Moon Example

Assume one cycle has:

- `3 days` active
- `3 days` grace period
- Blood Moon gameplay begins at the active start time
- The public platform event covers only the active period

Example UTC schedule:

```text
Start: 2026-09-05T00:00:00Z
End:   2026-09-08T00:00:00Z
```

The scheduler would:

1. Calculate the next Blood Moon start and end in UTC.
2. Check whether the managed event already exists.
3. Update it with `PATCH` if the timing or metadata changed.
4. Create it with `POST` if no event exists for that cycle.
5. Store the returned Roblox `eventId` externally.
6. Never create a second event merely because a scheduler run was retried.
7. Calculate the next cycle after the active event ends.

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
POST https://apis.roblox.com/virtual-events/v3/universes/9799168239/game-events
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
  "placeId": 116587108840614,
  "thumbnails": [
    { "mediaId": 1234567890, "rank": 1 }
  ],
  "config": {
    "notificationAudience": "rsvp"
  }
}
```

`thumbnails[].mediaId` is the approved Roblox thumbnail/media asset ID, not an
in-game image field. `visibility` uses lowercase `public` or `private`. Event
categories are optional; the current synchronizer leaves them out until their
server-side validation contract is confirmed. Still verify the response because
the endpoint is experimental and thumbnail processing can be asynchronous.

## Idempotency and Duplicate Protection

The scheduler must be safe to run repeatedly. Recommended external state:

```json
{
  "eventKey": "bloodmoon-2026-09-05T00:00:00Z",
  "eventId": "4040806533699863314",
  "startTime": "2026-09-05T00:00:00Z",
  "endTime": "2026-09-08T00:00:00Z",
  "lastSyncStatus": "success"
}
```

Rules:

- Use a deterministic `eventKey` based on event type and UTC start time.
- Store the Roblox event ID outside the Roblox game source tree.
- `PATCH` the stored event instead of creating a new event.
- If the stored ID returns `404`, list current events and verify before creating.
- Do not delete unrelated events.
- Do not match by title alone because multiple events can have the same title.
- Keep a log of every create, update, failure, and returned event ID.
- Limit the scheduler to one managed upcoming event unless more are needed.

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

For this game, a daily scheduler is enough. Blood Moon does not need a
per-minute creator API loop. A run at least once per day, plus a manual retry,
can keep the next event synchronized.

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
2. Reads the DEV universe ID `9799168239` and DEV place ID `116587108840614` from configuration.
3. Computes the next Blood Moon UTC window.
4. Lists existing events.
5. Updates the known managed event or creates one if it is missing.
6. Verifies title, schedule, place, privacy, and thumbnail in the response.
7. Writes a short sync result to its log.

Do not connect this directly to player-triggered game code. The game should
continue using its existing live-event schedule, while the external task
handles Roblox platform-event publishing.

## First Version In This Project

The first synchronizer is located outside `src`:

```text
tools/RobloxEventSync/Sync-BloodMoonEvent.ps1
tools/RobloxEventSync/config.example.json
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

Review the dates, title, description, categories, and optional thumbnail in
`config.json`. The script is dry-run by default:

```powershell
.\Sync-BloodMoonEvent.ps1
```

Only after reviewing the printed payload should it be allowed to mutate Roblox:

```powershell
.\Sync-BloodMoonEvent.ps1 -Apply
```

The script lists and verifies events, updates a known event instead of creating
duplicates, retries temporary `429`/`5xx` failures, verifies the returned
title/schedule/place/visibility, and writes only the managed event ID and
schedule to the ignored `event-state.json`. It has no delete operation.

## Bottom Line

Automatic Blood Moon Experience Events are possible through Open Cloud, but
they require an external scheduler and secure credentials. There is no Roblox
charge documented for the event API itself. The simplest low-cost production
design is a daily GitHub Actions or Cloudflare scheduled task that updates one
known event ID and leaves gameplay entirely server-authoritative.
