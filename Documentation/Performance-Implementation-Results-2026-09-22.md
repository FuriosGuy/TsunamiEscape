# Performance Implementation Results: No Geometry Changes

Date: 2026-09-22

Project: SpeedBrainrotDev

Scope: client particle, culling, shadow, and remote-trail budgets. BaseParts, MeshParts, models, kart geometry, world geometry, UI animation, and tsunami count stayed out of scope.

Gameplay note: Tsunamis are a core gameplay requirement.

## Implemented

### Device profile

Added `ReplicatedStorage/Modules/ClientDeviceProfile.luau`.

It reads `StudioDeviceSimulatorService` when running in Studio, then falls back to normal `UserInputService` detection in production. This avoids a Studio Device Simulator edge case where Phone input flags can later report keyboard or mouse support even though the selected device is mobile.

Used by:

- `ClientGraphicsService` for mobile shadow policy.
- `ClientCullingService` for Phone and Tablet distance scaling.
- `BloodmoonParticleService` for local event-particle rate scaling.
- `PlayerClientHandler` for remote-trail distance scaling.

### Particle budgets

- Tagged decorative particles use a reduced rate of `0.65` after `140` studs.
- Tagged decorative particles disable after `260` studs.
- Mobile distance thresholds scale by `0.65`.
- A `24` stud hysteresis margin prevents rapid enable/disable flicker.
- Original `ParticleEmitter.Rate` values are restored when effects return to range or culling stops.
- Local Bloodmoon, Neonrush, and Frostbite event visuals apply a conservative `0.75` rate multiplier on Phone and Tablet after area normalization.
- No emitter is destroyed.

### Remote trails

Remote trail clones now use a client-only budget:

- Local-player trails stay full quality.
- Nearby remote trails within `120` studs stay full quality.
- Remote trails from `120` to `360` studs use `0.5` emitter rate.
- Remote trails beyond `360` studs are disabled.
- At most `6` remote trail owners remain visible.
- Quality checks run every `0.25` seconds.
- Phone and Tablet distance thresholds scale by `0.65`.

This budget is radius-based, plus a nearest-player cap. It does not remove trail source assets or player geometry.

### Shadows

Existing `ClientGraphicsService` policy remains active:

- Phone and Tablet: `Lighting.GlobalShadows=false`.
- PC and Console: global shadows remain enabled.

The new device profile makes the policy reliable under Studio Device Simulator.

### Decorative Texture and Decal culling

`ClientCullingService` now distance-culls decorative `Texture` and `Decal` instances without deleting them:

- Candidate groups are limited to `Terrain`, `Decorations`, and `VIPRooms`.
- Event boards, kart buttons, treadmills, roads, spawn markers, player characters, and tsunami visuals are protected.
- Final `textureDistance` is `600` studs, scaled by the existing `0.65` mobile distance multiplier.
- Culling uses `LocalTransparencyModifier` and restores the original local value when the visual returns to range or the service stops.
- Runtime validation found `3,610` tagged textures, with `612` culled in one normal client sample and `0` protected textures tagged.
- This reduces active render work; it does not reduce replicated texture or instance count.

### Decorative per-part shadow culling

`ClientCullingService` now distance-culls `BasePart.CastShadow` only for safe decorative candidates:

- Candidate groups are limited to `Terrain`, `Decorations`, and `VIPRooms`.
- Gameplay roads, stages, hazards, interaction groups, equipped karts, tsunami visuals, and player characters are protected.
- Final `shadowDistance` is `400` studs, scaled by the existing mobile distance multiplier.
- Original `CastShadow` values are restored when parts return to range or culling stops.
- Runtime validation found `873` tagged candidates, `419` currently shadow-culled parts, and `0` protected parts tagged.
- Global shadows remained enabled on the PC test profile; this is separate from the existing Phone/Tablet global-shadow override.

## Validation

### Argon

Argon `2.0.29` build passed after the final changes:

```text
Successfully built project: C:\RobloxProjects\SpeedBrainrotDev\SpeedBrainrotDev.project.json
```

No Rojo build was used.

### Studio Device Simulator through MCP

Tested with Roblox Studio MCP and reset Device Simulator to `default` afterward.

| Device | Resolved kind | Mobile tier | Global shadows |
|---|---|---:|---:|
| `hd_1080` | Desktop | No | On |
| `iphone_17_pro` | Phone | Yes | Off |
| `ipad_pro_M5_13in` | Tablet | Yes | Off |
| `xbox` | Console | No | On |

Phone and Tablet visual checks retained the 3D world, kart, trails, and gameplay HUD. No geometry-removal behavior occurred.

### Temporary culling behavior test

A temporary runtime-only emitter was created, tested, then destroyed. It did not modify project geometry.

Tablet profile results:

```text
NEAR|d=20.0|enabled=true|rate=100.0
REDUCED|d=100.0|enabled=true|rate=65.0
FAR|d=180.0|enabled=false|rate=100.0
RESTORED|d=20.0|enabled=true|rate=100.0
```

This confirms full quality, reduced rate, full culling, and original-rate restoration.

### Eight-client remote-trail validation

Used Studio's `StudioTestService:ExecuteMultiplayerTestAsync(8, ...)` with a temporary harness. Each client locally assigned `GalaxyTrail` for rendering only; no server-owned trail attributes or DataStore values were changed. The harness arranged test characters, emitted per-client visual-state rows, restored local attributes, and was removed after the test.

Results from Roblox client logs:

- Server reached `8` players by teardown; `7` client logs captured rows with `8` replicated players.
- `GalaxyTrail` base emitter rate: `176.0`.
- Reduced remote rate: `88.0`, confirming the configured `0.5` multiplier.
- Full, reduced, and disabled states appeared across clients.
- The six-remote-owner cap was observed: a remote trail inside the radius was disabled when it ranked beyond the six nearest remote owners.
- Hard-distance disable appeared at roughly `481` to `487` studs. Rows around `122` to `358` studs showed reduced quality as expected.
- Seven rows were still missing visuals while characters were joining or settling. One row sampled at `396` studs remained reduced during that unstable layout window, so exact hard-radius behavior should be repeated after character positions are stable.

The multi-client pass validates the remote-trail budget and rate multiplier. It does not yet represent real-player trail variety or production network conditions.

### MicroProfiler through MCP

MicroProfiler was captured through `execute_luau` and `@rbx/LibMP`. Each result below used `128` frames. These are Studio CPU frame-time samples, not production FPS measurements and not a controlled before/after A/B run.

| Device simulation | P50 ms | P90 ms | Max ms | Average ms |
|---|---:|---:|---:|---:|
| PC `hd_1080` | 0.261 | 4.890 | 6.070 | 1.498 |
| Phone `iphone_17_pro` | 3.169 | 5.002 | 5.501 | 2.488 |
| Tablet `ipad_pro_M5_13in` | 0.306 | 4.523 | 5.791 | 1.690 |

Studio frame timing includes editor, simulator, scheduler, and idle behavior. Use production telemetry and active-event captures before claiming a percentage FPS improvement.

After decorative Texture/Decal and per-part shadow culling, a fresh PC Studio snapshot captured `128` frames (`428082` through `428209`). The snapshot confirms the measurement path is still working, but it is not a controlled before/after A/B comparison and does not establish a production FPS percentage.

### Studio-only debug event scheduling

The existing `LiveEventService` Studio scheduler was used for an active-event pass. Argon temporarily synced fixed debug targets for Bloodmoon, NeonRush, and FrostbiteRally; the debug target and all event debug flags were restored to their original values afterward. Published-server scheduling was not changed.

Active-event pass results:

| Event | Device | Emitters total/enabled | Sum of emitter rates | Graphics particles MB | CPU sample |
|---|---|---:|---:|---:|---|
| Bloodmoon | Phone | 94 / 83 | 6,019.5 | 15.73 | p50 4.066 / p90 5.029 / max 6.026 / avg 4.152 ms; 53 frames |
| NeonRush | Phone | 72 / 69 | 2,803.7 | 15.81 | p50 0.871 / p90 3.500 / max 4.360 / avg 1.403 ms; 128 frames |
| FrostbiteRally | Phone | 75 / 72 | 38,803.7 | 16.35 | p50 0.863 / p90 3.718 / max 4.817 / avg 1.400 ms; 128 frames |
| FrostbiteRally | Tablet | 75 / 72 | 38,846.8 | 16.31 | p50 1.328 / p90 2.971 / max 4.687 / avg 1.536 ms; 128 frames |
| FrostbiteRally | PC | 75 / 72 | 51,645.5 | 16.36 | p50 0.561 / p90 3.235 / max 4.704 / avg 1.174 ms; 128 frames |

Frostbite confirms mobile event-rate scaling: Phone and Tablet run at roughly `0.75` of the PC configured rate while keeping the same visible emitter set. Graphics-particle memory stayed near `16 MB` in this Studio session. These are not real-device FPS measurements and do not prove a production percentage gain.

## Findings

1. Implementation is behaving conservatively and does not make the game visually low-quality by default.
2. Mobile shadows now disable reliably through device emulation; PC and Console retain shadows.
3. Particle culling and rate reduction work without deleting objects and restore original rates correctly.
4. Active-event samples show conservative rate reduction working: FrostbiteRally is about `38.8k` total configured rate on Phone/Tablet versus `51.6k` on PC, with visible nearby emitters retained.
5. Eight-client validation confirmed remote-trail full/reduced/disabled states, the `0.5` reduced rate, and the six-owner cap. One unstable layout row means exact hard-radius behavior still deserves a settled-position repeat.
6. No geometry optimization is required to validate this phase. No production parts were removed, merged, or replaced.

## Decision

No immediate budget tweak is justified from these Studio captures. Current event budgets are conservative enough to preserve visible effects, but FrostbiteRally remains the highest particle-rate case and deserves real-device/production telemetry before further reduction.

Geometry work can proceed as a separate next phase because this implementation leaves geometry unchanged. Before changing geometry, capture active Phone and Tablet events and multiplayer trails so geometry gains can be separated from effect-budget gains.

## Remaining validation

1. Capture `GraphicsTexture`, `LuaHeap`, `Script`, `Gui`, and OOM behavior during active events.
2. Repeat remote-trail capture after all characters finish spawning and positions settle; include Phone/Tablet if Studio applies device emulation to all simulated clients.
3. Repeat key captures on real Phone/Tablet hardware or production telemetry.
4. If mobile event performance remains weak after these budgets, begin geometry review by category, starting with distant showcase and decorative assets. Keep collision and tsunami gameplay geometry protected.
