# SpeedBrainrotDev Client Performance Study

Date: 2026-09-22

Project: SpeedBrainrotDev

Place: +1 Speed DEV, place ID 116587108840614

Scope: read-only study of client FPS, memory, rendering load, and likely causes affecting PC, phone, and tablet. Console remains secondary because its telemetry is already healthier.

No gameplay source files were changed during this study. This report is the only new project artifact.

## Executive result

Highest-value work should target graphics and replicated content before general script micro-optimization:

1. Reduce replicated kart/showcase geometry.
2. Add device-specific particle budgets.
3. Cull remote trail visuals by distance and quality tier.
4. Reduce world texture and decorative-instance count.
5. Profile Heartbeat, RenderStepped, and UI animation work after those reductions.

Current data does not prove one single FPS cause. It does show several large, measurable budgets that affect every low-end client.

Gameplay note: Tsunamis are a core gameplay requirement.

## Production telemetry

Source folder:

    C:/Users/glenn/Downloads/Performance Stats

Telemetry window: 2026-09-21T00:30:00.000Z through 2026-09-22T00:30:00.000Z. Frame rate and memory contain 49 half-hour samples per platform.

### Client frame rate

| Platform | Mean FPS | P50 FPS | P90 FPS | Minimum | Maximum |
|---|---:|---:|---:|---:|---:|
| Computer | 41.39 | 41.72 | 43.96 | 34.57 | 47.35 |
| Phone | 46.42 | 46.61 | 49.00 | 41.47 | 51.49 |
| Tablet | 51.05 | 51.51 | 54.18 | 45.48 | 56.30 |
| Console | 54.97 | 54.87 | 56.47 | 52.75 | 57.48 |
| Total | 51.43 | 51.45 | 52.47 | 48.96 | 53.02 |

TV telemetry is not useful for this comparison: mean 4.30 FPS with zero-valued samples. VR mean was 62.64 FPS.

### Client memory

Values below are the telemetry memory unit reported by the export, treated as GB for comparison.

| Platform | Mean | P50 | P90 | Minimum | Maximum |
|---|---:|---:|---:|---:|---:|
| Computer | 2.20 | 2.20 | 2.29 | 1.93 | 2.41 |
| Phone | 1.05 | 1.04 | 1.10 | 0.94 | 1.13 |
| Tablet | 1.09 | 1.09 | 1.14 | 1.02 | 1.14 |
| Console | 1.99 | 2.00 | 2.11 | 1.80 | 2.19 |
| Total | 1.75 | 1.76 | 1.86 | 1.61 | 1.93 |

Unexpected out-of-memory export contains two nonzero Phone rows, at 2026-09-21T17:00:00Z and 17:30:00Z. The Total row is 1 for every interval, so it should not be counted as 49 independent OOM exits without clarifying export semantics.

Computer crash rate reached 0.09 in one half-hour sample. This is an alert signal, not proof of a rendering or memory cause.

### Client CPU telemetry

| Category | Mean | P50 | P90 | Maximum |
|---|---:|---:|---:|---:|
| Total | 4.09 | 3.57 | 3.97 | 31.14 |
| Miscellaneous | 1.53 | 0.94 | 1.10 | 28.05 |
| Physics | 0.96 | 0.99 | 1.12 | 1.29 |
| Scripts | 0.76 | 0.75 | 0.92 | 1.12 |
| Networking | 0.44 | 0.37 | 0.65 | 2.15 |
| Animation | 0.39 | 0.37 | 0.45 | 0.69 |

One Miscellaneous outlier dominates the maximum. Treat P50/P90 as steady-state and investigate spikes separately.

## Studio MCP profiling

Roblox Studio MCP can run MicroProfiler analysis through execute_luau and LibMP. There is no dedicated MCP command named Start MicroProfiler.

Captures completed:

| Capture | Frame range | Notes |
|---|---:|---|
| normal_live | 120061-120188 | Normal loaded client |
| loaded_live | 140590-140677 | Loaded client after initialization |

Capture method used:

    local LibMP = require("@rbx/LibMP")
    local Control = LibMP.Control

    Control:SetFrameLimit(128)
    Control:EnableProfiler(true)
    Control:EnableCapture(true)
    task.wait(3)

    local snapshot = Control:CaptureToBufferSync()
    local session = LibMP.Session.OpenFromBuffer(snapshot)
    print(session:GetFrameIdMin(), session:GetFrameIdMax())

Snapshot capture is preferred for execute_luau because it avoids relying on a live session while the command is running. Frame limit can be increased up to 256 when a longer sample is needed.

### Inclusive timer signal

A three-second Studio snapshot produced these inclusive timer totals:

| Timer | Total time | Calls | Interpretation |
|---|---:|---:|---|
| Sleep | 2,187.4 ms | 856 | Scheduler wait; not gameplay cost |
| TS::ArbiterStep | 106.9 ms | not retained | Engine scheduling |
| TS::JobStep | 102.1 ms | not retained | Engine job scheduling |
| Heartbeat | 65.9 ms | not retained | Broad per-frame work |
| deferredThreads | 58.4 ms | not retained | Deferred task execution |
| Event | 54.8 ms | not retained | Inclusive event dispatch |
| Script_WorldManager | 45.0 ms | 67 | Candidate for focused follow-up |
| PreRender | 13.7 ms | not retained | Rendering preparation |
| Simulation | 13.5 ms | not retained | Simulation work |

These totals are inclusive across the capture and can overlap. Sleep, engine scheduler timers, and broad Heartbeat totals are not direct proof of a single bottleneck. Script_WorldManager is a useful follow-up target after graphics reductions, not a confirmed FPS cause.

### Studio memory tags

Observed loaded-client tags:

| Tag | Approximate value |
|---|---:|
| Total Studio memory | 3,235 MB |
| LuaHeap | 1,046.6 MB |
| Script | 281.1 MB |
| Gui | 145.3 MB |
| GraphicsTexture | 172.7 MB |
| GraphicsParticles | 15.3 MB |
| Instances | 172.2 MB |

These values include Studio and engine overhead. They are diagnostic evidence, not production phone or tablet memory limits.

## Runtime scene evidence

Read-only Client queries during Play found:

| Location | Descendants | Parts | Models | Textures | Emitters | Trails | GUI objects |
|---|---:|---:|---:|---:|---:|---:|---:|
| Workspace | 12,322 | 2,739 | 354 | 4,749 | 63 | 1 | 1,612 |
| Workspace.Worlds | 11,837 | 2,635 | 350 | 4,749 | 54 | 0 | 1,608 |
| ReplicatedStorage | 5,262 | 2,530 | 57 | 0 | 46 | 8 | 12 |

Counts vary slightly while dynamic effects, UI, and showcase objects are created or removed.

One workspace particle query found 60 enabled emitters with configured rate sum 3,169. The local character contained 9 emitters, 6 enabled, with configured rate sum 176. Configured rate is not equivalent to visible particles in every container; templates in ReplicatedStorage are included separately.

UI audit output found approximately:

    Text: 400
    UIStroke: 744
    Images: 407
    UICorner: 197
    Eligible UI instances: 1,766

UI is large, but current evidence ranks world graphics and effects above UI as first optimization targets.

## Source findings

### 1. Replicated kart and showcase geometry

Runtime ReplicatedStorage.KartModels contained 4,999 descendants, 2,521 parts, and 57 models.

WorldManager.server.luau line 2263 clones kartTemplate into KartShowcaseModel for kart buttons. The runtime contained approximately 15 showcase models with about 1,218 descendants and 1,199 parts.

KartCatalog.luau and KartButtonStatus.client.luau read ReplicatedStorage.KartModels. Moving the folder directly to ServerStorage would break current client assumptions.

Safer architecture:

- Replicate kart metadata and names separately.
- Keep full templates server-side where possible.
- Replicate only active player karts and required preview assets.
- Use low-detail showcase models for distant or hidden buttons.
- Avoid cloning full showcase geometry for every button when a shared preview is sufficient.

### 3. World texture and decoration count

Workspace contained 4,749 Texture instances. Most were in World1, including Terrain, Decorations, VIPRooms, Roads, and EventBoard.

ClientCullingService.luau culls BillboardGui, SurfaceGui, ParticleEmitter, Light, Beam, and Trail. Its configured skip list includes EquippedKarts, TutorialNotificationSystem, and ClientTrailVisual_ objects.

The culling service does not distance-disable Texture, Decal, or general decorative BasePart objects. Normal frustum culling still applies, but distant decoration remains part of the replicated/renderable scene.

Recommended:

- Merge repeated decorative textures where art allows.
- Replace distant decoration groups with low-detail or texture-free variants.
- Add distance tiers for decorative Texture and Decal instances.
- Prefer model-level enable/disable over thousands of individual toggles.

### 3. Particle scaling risk

CoreConfig_Client.luau line 20 sets positionUpdateFps to 15. The default particle visual size is 512.

BloodmoonParticleService.luau lines 151-162 scale emission rate by target area. Source template size is 128, so target size 512 multiplies rate by 16.

Static template estimates:

| Effect | Source rate sum | Approximate scaled rate |
|---|---:|---:|
| BloodmoonParticle | 200/sec | 3,200/sec |
| NeonrushParticle | 350/sec | 5,600/sec |
| FrostbiteRallyParticle | 3,000/sec | 48,000/sec |

FrostbiteRallyParticle is the largest mobile/tablet risk. Its 3-5 second lifetimes can retain roughly 144,000-240,000 living particles at the scaled rate if fully active. This is a static estimate and must be confirmed during the live event.

Recommended device tier test:

- Phone: 0.25 rate multiplier or event-specific simplified effect.
- Tablet: 0.50 multiplier.
- PC and console: current quality baseline.
- Cap lifetime and rate independently; reducing only visual size does not guarantee enough particle reduction.

### 4. Observed trail visuals

PlayerClientHandler.client.luau lines 763-825 clone Trail and ParticleEmitter descendants for observed players. Lines 1766-1787 periodically update observed trail visuals. A Heartbeat connection drives broader kart and visual work around line 2289.

Current test player had 9 character emitters and 1 Trail. ClientTrailVisual_ objects were not present in that exact sample, so multiplayer scaling remains unmeasured.

Because ClientCullingService skips the ClientTrailVisual_ prefix, remote trail clones need their own distance and quality budget.

Recommended:

- Full trail only for local player.
- Reduced rate for nearby remote players.
- Disable remote trails outside a distance threshold.
- Enforce a maximum visible remote trail count.
- Profile with multiple players or controlled trail clones before selecting limits.

### 5. Script and UI follow-up

FramerateManager.luau maintains Heartbeat and RenderStepped update connections. VisualFunctions.luau updates rainbow UI gradients through that manager and has additional RenderStepped handlers.

This work can matter on weaker CPUs, but telemetry and scene counts point first toward graphics, effects, and replicated content. Re-profile after graphics reductions so script costs are not hidden by larger rendering work.

## Prioritized work plan

### P0: mobile and tablet quality tiers

Apply separate particle, trail, shadow, and decorative-distance budgets. Keep console quality independent so console FPS does not regress for no reason.

### P1: world decoration and textures

Reduce Texture and Decal count in World1. Test visual difference at normal camera distance and during movement.

### P1: remote trail budget

Measure with multiple players. Add distance and maximum-count rules before increasing other effect quality.

### P2: kart replication and previews

Split catalog metadata from full kart templates. Reduce showcase model geometry and replication scope.

### P2: Heartbeat and UI profiling

Use MicroProfiler timer scopes after P0/P1 changes. Optimize only handlers that appear in repeated frame-critical samples.

## Validation criteria

Repeat same capture after each isolated change:

1. Fresh Play session, loaded normal gameplay.
2. Active event particle scenario.
3. Multiple-player trail scenario.
4. At least 128 MicroProfiler frames per scenario.

Record:

- P50, P90, and worst frame time.
- GraphicsTexture, GraphicsParticles, Gui, Instances, LuaHeap, and Script tags.
- Workspace descendant, part, texture, emitter, trail, and GUI counts.
- Configured particle rate and visible remote trail count.
- Phone/tablet OOM and crash telemetry after deployment.

Success target:

- Improve PC mean FPS by at least 10 percent.
- Improve Phone and Tablet P90 stability without new OOM rows.
- Keep Console mean FPS within 1 FPS of current baseline.
- Reduce peak memory and graphics counters, not only average FPS.

## Limits and interpretation

- Studio MCP profiling used a simulated PC client. No physical phone, tablet, or console capture was available.
- Studio memory totals include editor and engine overhead.
- Daily telemetry aggregates identify platform symptoms, not exact code ownership.
- Runtime counts change during dynamic effects, UI transitions, respawns, and showcase reconciliation.
- MicroProfiler timers are inclusive and can overlap. A timer name alone does not prove exclusive frame cost.
- No source optimization was implemented in this study. Results are evidence for isolated A/B changes.

## Final conclusion

PC is weakest by FPS, while Phone and Tablet show the clearest memory-risk and graphics-budget need. Console has enough headroom for a separate higher-quality tier.

First test mobile particle budgets. In parallel, reduce world texture/decorative count and add remote trail culling. General script cleanup should follow, guided by a new MicroProfiler capture after each graphics budget change.

## References

- Roblox LibMP: https://github.com/Roblox/libmp/blob/main/README.md
- Roblox performance optimization: https://create.roblox.com/docs/performance-optimization
