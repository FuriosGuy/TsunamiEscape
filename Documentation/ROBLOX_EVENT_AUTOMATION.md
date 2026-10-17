# Roblox Event Automation

## Source Of Truth

Event-page and offline-notification automation was moved out of this game
repository. The canonical automation repository is:

`https://github.com/FuriosGuy/TE-Automation`

The game remains responsible for the authoritative in-game schedule and
gameplay. The external repository is responsible for Roblox platform event
pages and offline reward notifications. Neither external workflow is required
for players to join or for gameplay rewards to work.

The old `tools/RobloxEventSync` directory and both old event workflows were
removed from this repository. Do not recreate them here or add API keys to the
game source repository.

## Current Automation

The separate repository contains:

```text
tools/RobloxEventSync/Sync-BloodMoonEvent.ps1
tools/RobloxEventSync/config.github-main.json
tools/RobloxEventSync/config.github-dev.json
tools/RobloxNotificationSync/Sync-RewardNotifications.ps1
tools/RobloxNotificationSync/config.github-main.json
tools/RobloxNotificationSync/config.github-dev.json
.github/workflows/roblox-event-sync-main.yml
.github/workflows/roblox-event-sync.yml
.github/workflows/roblox-reward-notifications-main.yml
```

The event workflows run hourly and also support manual dispatch:

- `Main Version` targets universe `9824719186` and publishes the production
  event schedule. The current window is public and the next same-event window
  is staged privately until the current window ends.
- `DEV Version` targets universe `9799168239` and keeps all platform events
  private. Its config is disabled by default as an additional safety gate.
- `Main Reward Notifications` targets the production universe only. It scans
  ready Daily Reward, Spin Wheel, and Group Reward states, skips players who
  are currently in the experience, and sends at most one notification per
  player per run.

Different event keys can run together, such as Blood Moon and 2X Weekend. The
synchronizer prevents duplicate windows for the same event key by using the
stable key:

```text
eventKey|windowStartUtc
```

Generated event IDs and local state remain in the automation repository and
are ignored there. The production notification workflow does not send Blood
Moon notifications because that event is already visible to players in-game.

## GitHub Setup

In `FuriosGuy/TE-Automation`, add these repository secrets under `Settings` >
`Secrets and variables` > `Actions`:

```text
ROBLOX_EVENT_API_KEY
ROBLOX_EVENT_MAIN_API_KEY
ROBLOX_NOTIFICATION_MAIN_API_KEY
```

Use separate keys where possible. Restrict each key to its required universe
and minimum permissions. Event synchronization needs event read/write access;
reward notification synchronization needs production Data Store read and User
Notification create access. Never place a key in a config file, Roblox source,
commit, issue, or workflow output.

The workflows are scheduled by GitHub, not by the Roblox server or a local PC.
GitHub may delay scheduled runs during load, so use `workflow_dispatch` for an
immediate run. The event script is dry-run by default; `-Apply` is required
before it can mutate a Roblox platform event. The notification script is also
dry-run by default; `-Apply` is required before it sends notifications.

Run local checks from the automation repository root:

```powershell
Set-Location C:\RobloxProjects\TsunamiEscape-Automation
pwsh -NoProfile -File .\tools\RobloxEventSync\Sync-BloodMoonEvent.ps1 `
  -ConfigPath .\tools\RobloxEventSync\config.github-main.json
pwsh -NoProfile -File .\tools\RobloxNotificationSync\Sync-RewardNotifications.ps1 `
  -ConfigPath .\tools\RobloxNotificationSync\config.github-main.json
```

Review dry-run output before adding `-Apply`. Local credentials belong in the
automation repository's ignored `.env` file or process environment only.

## Safety Model

If the external API, GitHub Actions, or an API key fails, the in-game event
system continues using the server schedule. A malformed response must never
cause mass deletion or recreation. The synchronizer only manages explicitly
configured event keys, never matches by title alone, and keeps production and
DEV universe IDs in separate configs.

Roblox platform events and notifications are separate from the in-game
`LiveEventSchedule`, `LiveEventService`, and `EventBoard`. Keep the in-game
schedule as the gameplay authority and treat platform automation as a
best-effort publishing layer.

## API References

- [Roblox Experience Events](https://create.roblox.com/docs/production/promotion/experience-events)
- [Roblox User Notifications](https://create.roblox.com/docs/cloud/guides/experience-notifications)
- [Roblox Open Cloud API Keys](https://create.roblox.com/docs/cloud/auth/api-keys)
