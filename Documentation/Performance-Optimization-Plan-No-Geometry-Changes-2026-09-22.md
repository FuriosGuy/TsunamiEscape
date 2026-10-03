# Performance Optimization Plan: No Geometry Reduction

Date: 2026-09-22

Scope: improve client FPS and effect-related memory without deleting, merging, or replacing BaseParts, MeshParts, models, kart geometry, or world geometry.

Gameplay note: Tsunamis are a core gameplay requirement. This plan does not reduce tsunami count or escape pressure.

No source changes are included in this document. It is an implementation plan and validation checklist.

## Out of scope

- Removing parts.
- Merging parts into MeshParts.
- Reducing kart model geometry.
- Rebuilding world sections.
- Changing gameplay-critical collision or interaction behavior.

## Current evidence

Read-only Client profiling found:

| Area | Observed load |
|---|---:|
| Workspace descendants | 12,322 |
| Workspace parts | 2,739 |
| Workspace textures | 4,749 |
| Workspace particle emitters | 63 |
| Enabled workspace emitters | 60 |
| Enabled workspace configured rate | 3,169/sec |
| Local character emitters | 9 |
| Local character enabled emitters | 6 |
| Local character configured rate | 176/sec |
| GUI objects | 1,612 |

Configured particle rate is not identical to visible particles. ReplicatedStorage contains effect templates that may be enabled as templates but are not rendered until cloned into Workspace.

Static effect risks:

- BloodmoonParticle: approximately 3,200 particles/sec after current area scaling.
- NeonrushParticle: approximately 5,600 particles/sec after current area scaling.
- FrostbiteRallyParticle: approximately 48,000 particles/sec after current area scaling.

FrostbiteRallyParticle needs first live-event validation on Phone and Tablet.

## 1. Device particle budgets

Add device quality multipliers to the existing client configuration. Candidate starting values:

| Device tier | Particle rate multiplier | Effect intent |
|---|---:|---|
| Phone | 0.25 | Strong reduction; preserve readability |
| Tablet | 0.50 | Medium reduction |
| Computer | 1.00 | Current baseline |
| Console | 1.00 | Preserve current quality |

Apply multiplier when effect is initialized or enabled. Do not multiply Rate every frame.

Important implementation rule:

- Store original emitter rate.
- Apply area normalization once.
- Apply device multiplier once.
- Restore original rate when effect is disabled or quality changes.

This prevents repeated enable/disable cycles from multiplying an already-scaled rate.

Primary source:

- ReplicatedStorage/Modules/BloodmoonParticleService.luau, lines 151-162 and 372-405.
- ReplicatedStorage/Modules/Shared/CoreConfig_Client.luau, lines 15-24.

Recommended first test:

1. Keep all effect objects and gameplay behavior.
2. Reduce only emitter Rate on Phone and Tablet.
3. Compare GraphicsParticles, frame P50/P90, and visual readability.
4. Test Bloodmoon, Neonrush, and Frostbite separately.

## 2. Expand client effect culling

Reuse ClientCullingService. Do not destroy instances. Toggle visibility or enabled state, then restore the original state when the object returns to range.

Current service handles:

- BillboardGui.
- SurfaceGui.
- ParticleEmitter.
- Light.
- Beam.
- Trail.

Current configuration includes:

- Update interval: 0.25 seconds.
- Mobile distance multiplier: 0.65.
- Particle distance: configured in CoreConfig_Client.

There are duplicate particle-distance defaults in CoreConfig_Client and ClientCullingService. Verify resolved runtime configuration before changing either value.

Primary sources:

- ReplicatedStorage/Modules/ClientCullingService.luau, lines 377-386 and 464-586.
- ReplicatedStorage/Modules/Shared/CoreConfig_Client.luau, lines 41-55.

Suggested distance tiers:

| Tier | Normal client | Phone/Tablet |
|---|---:|---:|
| Full effects | 0-120 studs | 0-80 studs |
| Reduced effects | 120-260 studs | 80-170 studs |
| Disabled effects | over 260 studs | over 170 studs |

These are test values. Tune against camera visibility and gameplay readability.

## 3. Cull Texture and Decal visibility without removing parts

Current culling does not distance-disable Texture or Decal instances. Add them as optional decorative cullables.

Rules:

- Cull only objects tagged or attributed as decorative.
- Preserve gameplay signs, hazards, buttons, roads, and required navigation markers.
- Store original Transparency before changing it.
- Use a single periodic pass, not a per-frame GetDescendants scan.
- Keep culling disabled for a short distance around the camera to avoid visible pop-in.

This can reduce render work, but it will not reduce instance count or base geometry memory. It is an FPS/render-budget optimization.

Highest-value groups for testing:

- World1/Terrain.
- World1/Decorations.
- World1/VIPRooms.
- World1/Roads.
- World1/EventBoard.

## 4. Remote trail budget

PlayerClientHandler clones Trail and ParticleEmitter descendants for observed players. Current ClientCullingService skips the ClientTrailVisual_ prefix, so remote trail effects need an explicit budget.

Primary source:

- StarterPlayer/StarterCharacterScripts/PlayerClientHandler.client.luau, lines 763-825 and 1766-1787.
- ReplicatedStorage/Modules/ClientCullingService.luau, lines 377-386.

No geometry reduction required:

- Keep local player trail at full quality.
- Reduce Rate for nearby remote trails.
- Disable remote trail emitters outside distance.
- Limit maximum visible remote trail owners.
- Disable low-priority Trail objects before high-priority player effects.

Suggested first test:

- Local player: full.
- Nearest 3 remote players: medium.
- Remaining remote players: disabled.

Validate with multiple players before selecting final limits.

## 5. Decorative lights and shadows

Use device quality to reduce lighting cost without removing objects:

- Disable decorative PointLight, SpotLight, and SurfaceLight instances at distance.
- Disable CastShadow for low-priority decorative parts on Phone and Tablet.
- Preserve shadows for local kart, hazards, key landmarks, and gameplay-readable objects.
- Keep console quality separate from Phone and Tablet.

Measure Graphics and frame P90 after each change. Shadow reduction can improve GPU time without lowering LuaHeap or instance count.

## 6. Script scheduling and event-driven work

Reduce CPU work without removing visual objects:

- Gate Heartbeat work when feature is disabled, hidden, or outside relevance range.
- Run low-priority visual refreshes at 10-30 Hz instead of every RenderStepped.
- Avoid rebuilding tables or instance references when values did not change.
- Replace repeated polling with property, ancestry, and visibility signals where possible.
- Keep expensive descendant scans limited to setup or controlled refresh points.
- Batch non-urgent follow-up work with task.defer.

PlayerClientHandler has a broad Heartbeat path around line 2289. This should be profiled after particle and culling changes, then gated by actual visibility and quality tier.

## 7. Memory lifetime, cleanup, and pooling

Lower memory growth without reducing parts:

- Reuse particle, trail, light, tween, and effect containers where practical.
- Do not repeatedly clone and destroy the same short-lived effect.
- Cancel spawned threads when character, player, or effect lifetime ends.
- Disconnect RunService and instance connections during cleanup.
- Clear per-player, per-character, and per-effect table entries after removal.
- Ensure cloned effects do not remain parented or referenced after visibility changes.
- Keep one authoritative state source instead of duplicating state in Attributes, ValueObjects, and Lua tables.

Run a ten-minute memory soak test with movement, respawn, equip, unequip, and event transitions. Record whether LuaHeap, Instances, Gui, and GraphicsParticles continue rising after each cycle.

## 8. Replication and streaming

Reduce memory and networking work while leaving geometry intact:

- Keep Workspace.StreamingEnabled enabled.
- Measure StreamingTargetRadius and StreamingMinRadius against gameplay visibility.
- Avoid replicating large temporary tables or redundant attribute updates.
- Batch high-frequency cosmetic state changes.
- Replicate lightweight metadata before full cosmetic assets.
- Load full preview assets only when a player opens the relevant UI.
- Keep server-only templates and unused event assets out of client replication when architecture permits.
- Do not change client kart lookup contracts without updating KartCatalog and KartButtonStatus together.
- Keep gameplay authority server-side; optimize only cosmetic replication.

ReplicatedStorage.KartModels currently contains 57 models and approximately 2,521 parts. This section permits reducing replication and lifetime, not changing model geometry.

## 9. Physics and query budget without removing parts

Parts can remain present while unnecessary engine work is disabled:

- Use collision groups for decorative objects that never interact with gameplay.
- Set CanTouch false for non-interactive decoration.
- Set CanQuery false for objects that should never be raycast targets.
- Preserve CanQuery and CanTouch for buttons, hazards, characters, roads, and navigation markers.
- Avoid unnecessary Touched connections on decorative objects.
- Keep static decoration anchored.
- Review network ownership for moving gameplay objects.
- Do not change collision behavior until gameplay raycasts and interaction tests pass.

This reduces physics, touch, and query work. It does not reduce BasePart count.

## 10. Audio and animation budgets

Audio and animation are smaller than current texture and particle risks, but cheap controls exist:

- Stop distant looping sounds.
- Keep one engine sound per active kart where possible.
- Reuse sound instances for repeated one-shot effects.
- Avoid starting the same sound repeatedly during rapid state updates.
- Lower animation update frequency for distant cosmetic characters.
- Disable cosmetic animation when the owning object is hidden or outside relevance range.
- Keep local kart, gameplay feedback, and accessibility audio active.

Studio AudioMemory was approximately 5.6 MB during profiling. Treat this as secondary optimization, not first target.

## 11. Texture and asset memory without geometry changes

Texture culling lowers active render work. Additional memory controls:

- Avoid preloading every cosmetic asset on startup.
- Preload only current gameplay, nearby UI, and immediate event assets.
- Release temporary references after UI or event completion.
- Reuse identical texture and sound asset IDs.
- Reduce oversized UI and effect textures where visual review permits.
- Avoid duplicate cloned assets with identical content.
- Keep texture-quality tiers separate from geometry tiers.

Texture culling can improve FPS and active graphics memory. It does not reduce parts.

## 12. Logging and diagnostic overhead

Performance diagnostics must not become runtime cost:

- Gate verbose logs behind a debug attribute or configuration flag.
- Do not print inside Heartbeat, RenderStepped, particle loops, or per-player loops.
- Sample counters at fixed intervals instead of logging every change.
- Keep one concise warning per failure category during a session.
- Disable temporary profiling logs before production measurement.

Use MicroProfiler and Stats counters for measurement. Use console output for sparse failure context only.

## Implementation order

1. Add particle rate multipliers.
2. Validate Frostbite, Bloodmoon, and Neonrush separately.
3. Enable distance culling for existing emitters, lights, beams, trails, and GUIs.
4. Add decorative Texture and Decal culling.
5. Add remote trail distance and owner-count limits.
6. Gate Heartbeat, RenderStepped, and polling work.
7. Verify cleanup and memory behavior through a soak test.
8. Tune replication and streaming budgets.
9. Review physics queries, audio, animation, and logging.
10. Re-profile before combining changes.

## Validation checklist

For each isolated change, capture at least 128 MicroProfiler frames:

1. Normal loaded gameplay.
2. Phone-quality simulation.
3. Tablet-quality simulation.
4. Bloodmoon active.
5. Neonrush active.
6. Frostbite active.
7. Multiple-player trail scenario.
8. Movement through multiple streamed regions.

Record:

- Frame P50, P90, and worst sample.
- GraphicsParticles.
- GraphicsTexture.
- Gui.
- LuaHeap.
- Script.
- Workspace emitter count and configured rate.
- Enabled remote trail count.
- Visible decorative Texture and Decal count.
- Remote and cosmetic replication volume.
- Active sound and animation count.
- OOM and crash telemetry after deployment.

## Expected benefit and limits

Particle-rate reduction and effect culling should reduce GPU particle work and improve low-end FPS.

Texture, light, trail, and UI culling should reduce active rendering work. They will not materially reduce replicated instance count or base geometry memory.

Script scheduling, cleanup, streaming, replication, physics-query, audio, animation, and logging changes can reduce CPU, memory, and network cost without reducing parts.

This plan intentionally leaves geometry optimization for a later, separate project because part reduction requires visual review, collision review, and gameplay regression testing.
