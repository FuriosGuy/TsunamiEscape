# Independent Performance Study: Tsunami Escape

Prepared by Codex, 2026-10-17 (Asia/Manila).

Workspace: `C:\RobloxProjects\SpeedBrainrotDev`.

Repository baseline: `26cf540330e33ad2efddafedb68ed85c1bd35265`, branch `main`. The working tree additionally contains the uncommitted 10-second minimum tsunami cooldown and Neon/Frostbite-only `EventGateCrater` visibility fixes, plus existing user changes. This study used current local source and the connected Studio place, not backups or a fresh GitHub checkout.

Scope: independent CSV analysis, current-source review, and live Studio profiling. Recommendations concern code execution, scheduling, caching, allocations, and state updates. Geometry reduction, model simplification, removing world objects, reducing tsunami counts, and reducing cosmetic model detail are outside scope. The original study made no gameplay source changes. Argon is the project's sync/build workflow.

## Implementation status update (2026-10-17)

P1-A through P1-C have since been implemented in the local source:

- **P1-A:** stage-path intersection snapshots each checkpoint's transform and padded half-size once per query, reusing bounds across historical movement segments.
- **P1-B:** stage definitions are indexed by world. Reconciliation is gated by server movement/stage revisions, skips repeated scans of unchanged path samples, and retries a reward-blocked crossing when its validation block expires.
- **P1-C:** culling caches player/kart ancestry classification and structural position sources. Ancestry changes rebuild cached classification; shared ancestor watchers refresh it on renames and character tracking changes. Tagged instances regain active tracking when reparented into Workspace. Watchers disconnect on tag removal, destruction, or service stop.

P1-A through P1-C were subsequently loaded through Argon and Play-tested. Runtime performance gains remain unverified; the capture below does not isolate the affected function costs or provide a matched before/after experiment.

P2-A through P2-D and P3-A through P3-B are now implemented locally:

- **P2-A:** staggered showcase update phases while retaining existing distance-based rates and server-time poses.
- **P2-B:** cached each pet viewport's visibility/clipping result; GUI visibility, bounds, clipping, enabled-state, and ancestry signals invalidate it. Connections disconnect on unregister, destruction, and stale entries.
- **P2-C:** computed shared pet-owner movement/facing/ground context once per owner update instead of once per pet.
- **P2-D:** cached eligible world-color parts and event models, handled new/removed descendants incrementally, coalesced event-state refreshes, and recolored only when seasonal-active state changes.
- **P3-A:** built one GUI-name index per notification reference refresh and skipped expensive diagnostic signatures when debug logging is disabled. Existing per-layout-pass bounds cache remains in place.
- **P3-B:** hoisted shared candy bob/yaw math out of per-candy animation loop.

**P3-C remains deferred.** Changing candy-state serialization/persistence requires multiplayer frequency/size evidence and a defined save, refill, reconnect, and crash-loss contract; no data-authority or persistence behavior was changed.

The first Play attempt exposed viewport-loop and pet-follow call-site regressions; both were fixed. A fresh Play ran through startup and profiler capture without further `PetViewportRenderer` or `PetFollowerController` errors in the captured recent console output. No movement, collection, reward, or shop interaction was performed. Normal Studio save/session-lock logs did run during the session.

### Post-implementation Studio capture (2026-10-17)

Argon `serve` was active. Studio's connected place was `+1 Speed DEV` (place `116587108840614`), one local player. The player remained near the lobby spawn; 24 tsunami states were active during context check. MicroProfiler captured 60 complete CPU-boundary frames per context after startup:

| Context | Regular frame IDs | Mean CPU-boundary span | P95 | Maximum |
| --- | --- | ---: | ---: | ---: |
| Client, post-edits | 1551-1610 | 4.650 ms | 5.614 ms | 6.875 ms |
| Server, post-edits | 3407-3466 | 5.819 ms | 7.093 ms | Not recorded |
| Client, earlier study baseline | 49-108 | 4.177 ms | 5.500 ms | 5.994 ms |

This does **not** demonstrate an improvement: post-edit client mean and maximum were higher, while P95 was close. The client windows are not workload-matched (different run/frame ranges and active tsunami load), and the earlier server baseline measured native Script Profiler function costs rather than server frame-boundary spans. LibMP exposed `Script_WorldManager`, but not `reconcilePlayerStageProgress` or the other local function-level scopes, so no targeted CPU reduction can be quantified. Treat results as inconclusive, not as a regression or gain. Need matched, repeated Script Profiler captures before/after in same scene and runtime conditions.

## 1. What the evidence supports

The clearest measured code opportunity is **server stage reconciliation**. In two one-player Studio captures, `reconcilePlayerStageProgress` accounted for approximately **192-194 milliseconds of sampled CPU per elapsed second**, or **98% of sampled server script CPU**. The expensive descendant is repeated segment-versus-checkpoint testing over recent movement history, even with the player stationary at stage 0. P1-A and P1-B mitigations now exist locally; their runtime gain is unmeasured.

On this desktop client, **showcase transform updates** were the largest named game-code cost. **Culling ancestry classification** was a second repeatable opportunity: approximately 62-72% of sampled culling CPU was inside `isPlayerOrKartVisual`. Both offer code work worth testing without reducing geometry or changing visual quality.

The supplied analytics establish an October 14 networking CPU anomaly, a decline in average FPS across the supplied September-to-October comparison, and elevated Computer crash-rate values. They do **not** identify a responsible remote, prove a memory leak, or establish that updates caused the FPS decline or that performance caused the concurrency decline. These production questions remain unresolved by a one-player DEV-place test.

Candy animation and collection checks were comparatively small in both samples. They should not be the first optimization target on the strength of this evidence.

## 2. Inputs and calculation method

The eight original CSVs and the separately supplied average-FPS CSV were read directly from `C:\Users\glenn\Downloads`. They cover `2026-09-19T00-00-00.000Z to 2026-10-16T00-00-00.000Z`; there are 28 daily values per exported series.

| CSV filename prefix | Data rows | Breakdown |
| --- | ---: | --- |
| `Client CPU time- Client CPU time, ` | 168 | 6 categories |
| `Client frame rate- Client frame rate, ` | 196 | P10; 7 platforms including Total |
| `Client frame rate- Client frame rate, ...(1).csv` | 196 | Average FPS; 7 platforms including Total |
| `Client memory usage percentage- Client memory usage percentage, ` | 196 | 7 platforms including Total |
| `Client memory usage- Client memory usage, ` | 196 | 7 platforms including Total |
| `Unexpected out of memory exits- Unexpected out of memory exits, ` | 112 | Total, Computer, Phone, Tablet |
| `Universe-9824719186- Client crash rate, ` | 196 | 7 platforms including Total |
| `Session time by place- Session time, ` | 224 | 8 platforms including Total |
| `Peak concurrent players- Peak concurrent players, ` | 224 | 8 platforms including Total |

For each series, calculate `sum(finite daily values) / number of daily values`. These are **unweighted means of exported daily statistics**, not session-weighted player averages. First-week comparisons use September 19-25; last-week comparisons use October 10-16. Percent-valued exports are multiplied by 100 for presentation. Total is analyzed separately, never added to platform series. TV and VR contain zero values and repeated sparse-looking observations; they are not used to rank the main device priorities.

### Metric notes

The original `Client frame rate` export is the **P10 percentile** series, as clarified by the user. A second export, filename ending `(1).csv`, is the **average FPS** series. Keep them separate; their levels and changes answer different questions. The memory CSV likewise contains no explicit unit; the other study labels its scale GB, but that unit should be confirmed against the source chart before converting to bytes. [Roblox Performance dashboard](https://create.roblox.com/docs/production/analytics/performance).

### Recomputed platform overview

| Platform | P10 FPS | Memory, exported scale | Memory usage % | Crash rate % |
| --- | ---: | ---: | ---: | ---: |
| Total | 49.637 | 1.621 | 24.503 | 0.457 |
| Computer | 49.533 | 2.214 | 20.868 | 2.314 |
| Phone | 43.477 | 1.022 | 20.689 | 0.241 |
| Tablet | 47.725 | 1.088 | 25.373 | 0.119 |
| Console | 54.933 | 2.050 | 27.658 | 0.215 |

Computer is the stability investigation priority; Phone has the lowest main-platform P10 FPS. Tablet also deserves attention because its first-week P10 FPS was 50.308 versus 45.038 in the final week. Computer moved in the opposite direction, from 46.051 to 54.076. A falling Total line is consequently not evidence that every platform regressed together.

### Average FPS declined in October

The newly supplied average-FPS export covers the same 28 dates. Means below are unweighted means of daily exported values, split at October 1:

| Platform | Sep 19–30 average FPS | Oct 1–16 average FPS | Change |
| --- | ---: | ---: | ---: |
| Total | 56.05 | 52.40 | -3.65 (-6.5%) |
| Computer | 69.97 | 65.42 | -4.55 (-6.5%) |
| Phone | 48.07 | 46.13 | -1.94 (-4.0%) |
| Tablet | 52.93 | 46.62 | -6.31 (-11.9%) |
| Console | 57.43 | 56.34 | -1.10 (-1.9%) |

This supports an October-period decrease in average FPS, especially on Tablet and Computer. Total daily average was 54.04 on October 1 and 51.03 on October 16, matching the approximate 54-to-51 observation; the full-period comparison is 56.05 to 52.40. This is temporal evidence, not proof that October updates caused the decline. Average Total also varied substantially day to day (48.70–56.56 during October 1–16), and platform-specific changes differ. A release-by-date comparison, stable platform/device mix, and per-version telemetry are needed to connect the decline to particular updates.

Crash rates have no ended-session denominators or crash signatures in these files. The Computer average is concerning, but confidence intervals, affected hardware, and crash categories cannot be calculated from the supplied exports. Roblox defines crash rate using crashes divided by ended sessions and specifically warns about noisy small cohorts. [Roblox crash-rate definition](https://create.roblox.com/docs/production/analytics/performance#crash-rate).

### October 14 CPU anomaly

| UTC date | Total CPU ms | Networking ms | Scripts ms | Total P10 FPS | Computer P10 | Phone P10 | Tablet P10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Oct 12 | 3.559 | 0.301 | 1.041 | 47.003 | 49.413 | 41.961 | 45.399 |
| Oct 13 | 4.305 | 1.644 | 0.874 | 49.441 | 55.153 | 45.487 | 46.083 |
| Oct 14 | 9.100 | 4.821 | 2.023 | 45.290 | 55.544 | 43.244 | 38.709 |
| Oct 15 | 3.237 | 0.659 | 0.773 | 49.140 | 51.897 | 48.357 | 44.797 |
| Oct 16 | 3.128 | 0.277 | 0.689 | 49.312 | 68.020 | 40.693 | 49.121 |

Across all 28 days, CPU category means are Scripts 0.791 ms, Physics 0.682 ms, Miscellaneous 0.660 ms, Networking 0.585 ms, and Animation 0.289 ms; Total is 3.008 ms. On October 14, Networking represents 52.98% of Total. Its 4.821 ms value is 11.26 times the 0.428 ms mean of the other 27 days. Scripts were also elevated, at 2.71 times their other-day mean.

Computer P10 did not fall alongside Total on October 14. Console was 46.631 and Tablet 38.709, so platform and hardware composition must be retained when investigating that date. These daily aggregate CPU/FPS series are different populations/statistics; they must not be converted into a single frame budget or used to calculate missing GPU time.

### OOM arithmetic does not reconcile

The literal sum of the 28 Total-series values is **43**. The platform-series sums are Computer **10**, Phone **30**, and Tablet **34**, totaling **74**, not 43. Daily Total differs from the sum of the supplied platform rows on **15 of 28 dates**.

Two decisive examples:

- September 28: Total = 0, Computer = 0, Phone = 0, Tablet = 2.
- October 2: Total = 0, Computer = 0, Phone = 0, Tablet = 3.

Thus, neither 43 nor 74 is a verified count of distinct OOM exits from these exports alone. Report 43 only as the **raw sum of the exported Total series**. Resolve chart aggregation/filter semantics and telemetry coverage before estimating incident counts or comparing OOM rates. All supplied series show zero for October 13-16; this is not proof that no OOM occurred.

### Engagement context

The exported Total session-time mean is 10.352 minutes. First-week mean is 11.429, last-week mean 8.737. The mean of the exported daily `Peak concurrent players` values falls from 545.719 to 84.218 between those windows. These are descriptive changes, not a causal link to performance. Fractional values in the peak export also caution against interpreting every row as a literal integer simultaneous-player maximum. Acquisition, platform mix, event timing, and release history are absent.

## 3. Live Studio investigation

### Environment and source fidelity

- Connected place: `+1 Speed DEV`, place ID `116587108840614`, universe ID `9799168239`.
- Supplied production crash CSV identifies universe `9824719186`; this was not a production-server capture.
- Started in Edit mode, ran one local Play session, and restored Edit mode after testing.
- Streaming enabled. Saved graphics setting was `QualityLevel10`; physical mobile hardware was not tested.
- One player in World1, stage 0, standing near `(-32.97, 12.22, -25.92)`.
- Runtime census: 20 stage definitions in World1; 15 `KartShowcaseModel` models; 9 pet follower models; 33 GUI ViewportFrames. Counts describe objects present at census time, not all simultaneously visible/animated objects.
- Candy folder had 200 direct children: the configured 100 candy visuals plus hitboxes.
- Active event IDs: `WeekendMultiplier`, with 4x XP/Wins/Luck. `EnvironmentName = Halloween`, `SeasonalEnvironmentActive = true`, `HalloweenPartTwoActive = true`; Studio Part 2 bypass is enabled. No active Bloodmoon, NeonRush, or FrostbiteRally capture was performed.
- Normalized source byte lengths and rolling checksums matched between disk and Studio for WorldManager, ValidationService, ClientCullingService, PlayerClientHandler, PetViewportRenderer, PetFollowerController, HalloweenCandyUIController, and LiveEventWorldVisualService. Native sampled function lines also matched those files.

### Tools actually used

Used Roblox Studio MCP `execute_luau`, native `ScriptProfilerService`, LibMP MicroProfiler snapshots, Stats readings, and normal GUI clicks. Both client and server native profiler starts/data requests succeeded. Sampling frequency was **1,000 samples/second**. Native `DeserializeJSON` converts the raw microsecond durations to seconds; tables below normalize them to CPU milliseconds per elapsed second. Inclusive parent/child durations overlap and must not be added. [ScriptProfilerService API](https://create.roblox.com/docs/reference/engine/classes/ScriptProfilerService), [Script Profiler sampling behavior](https://create.roblox.com/docs/studio/optimization/scriptprofiler).

Script Activity was not separately captured. No persistent profiling scripts or `debug.profilebegin` annotations were installed. An attempted temporary wrapper of module methods through the Assistant's `require` context recorded zero calls because it did not instrument the running game module instances; those readings were discarded and the temporary table assignments restored. All reported function costs below come from the native Script Profiler.

### Capture conditions

| Capture | Server duration | Client duration | Interface state |
| --- | ---: | ---: | --- |
| A | 17.965 s | 17.965 s | Lobby; DailyRewardFrame and PromptBuyProductsFrame visible at census |
| B | 45.499 s | 45.505 s | DailyRewardFrame closed; CandyShopFrame opened through CandyCountFrame button; PromptBuyProductsFrame remained visible; CandyShopFrame was no longer visible at the final check |

Capture A server engine timestamp: `2026-10-16T16:29:08.359Z` through `16:29:26.324Z`, equivalent to October 17 shortly after 00:29 PHT. Capture B server: `2026-10-16T16:31:28.446Z` through `16:32:13.945Z`. This is a repeated hotspot check, **not a controlled before/after optimization experiment**. B's UI changed during the interval, so its larger viewport cost cannot be attributed solely to CandyShopFrame.

### Native Script Profiler results

| Server scope | A CPU ms/elapsed s | B CPU ms/elapsed s | A share of sampled server script CPU |
| --- | ---: | ---: | ---: |
| All sampled server script categories | 194.516 | 198.137 | 100% |
| `reconcilePlayerStageProgress` | 192.110 | 194.405 | 98.763% |
| `DidPlayerRecentlyCrossPart` | 191.803 | 193.796 | 98.605% |
| `didRecentSampleCrossPart` | 188.550 | 191.448 | 96.933% |
| `doesSegmentIntersectPartBounds` | 181.397 | 183.795 | 93.255% |

Server roots include small Studio plugin costs; percentages refer to all sampled categories in that context. These nested rows describe one call chain. The 194 ms/s figure is approximately 19.4% of one CPU-second per elapsed second, **not 194 ms per frame**, and it is not a production latency measurement. Multiplayer scaling was not measured.

In capture A, sampled self time inside `doesSegmentIntersectPartBounds` was 1.855 s. `BasePart.Size` reads consumed 0.763 s and `BasePart.CFrame` reads 0.639 s, across the 17.965-second interval. These property samples strongly support testing cached checkpoint bounds; they are not a promised saving of their entire combined cost.

| Client scope | A CPU ms/elapsed s | B CPU ms/elapsed s | A share of sampled client script CPU |
| --- | ---: | ---: | ---: |
| All sampled client script categories | 54.979 | 88.603 | 100% |
| `updateObservedKartShowcases` | 23.668 | 29.747 | 43.049% |
| `updateCulling` | 10.654 | 10.452 | 19.379% |
| `isPlayerOrKartVisual` | 6.584 | 7.540 | 11.976% |
| Pet viewport `updateAnimator` | 3.606 | 11.051 | 6.558% |
| Tsunami `updateBoundVisuals` | 3.780 | 5.209 | 6.875% |
| Pet follower `updateFollowers` | 2.440 | 5.886 | 4.438% |
| Candy `_checkNearbyCandy` | 0.222 | 0.854 | 0.404% |
| Candy `_updateCandyAnimations` | 0.111 | 0.238 | 0.203% |

At 1 kHz, very small entries have few samples; do not overinterpret differences of tenths of a millisecond per second. Relative script percentages are not shares of the complete CPU/GPU frame budget. No improvement was measured because no optimization patch was applied.

### MicroProfiler evidence and limits

LibMP became usable after enabling its control channel and capture. A buffer snapshot held 109 frames; analysis used 60 complete middle frames, regular IDs **49-108**, absolute IDs **602606-602665**. Frame CPU-boundary duration was mean **4.177 ms**, median **4.063 ms**, P95 **5.500 ms**. Maximum was **5.994 ms** at regular frame **56**, absolute frame **602613**.

These are Studio MicroProfiler frame-boundary spans, not a production FPS benchmark. GPU frame start/end values were equal and did not provide a usable GPU measurement. The Stats GPU value of 0.001 ms is also unsuitable as evidence of low GPU load. Worker `Sleep` and main-thread wait scopes were present; they are waiting time, not script computation. Ranked inclusive scopes also contained `Script_WorldManager`, consistent with the native profiler. Parent scopes, waits, and parallel-thread work cannot be summed into total frame time. Snapshot iteration accounted for scopes crossing frame boundaries. [Roblox MicroProfiler guidance](https://create.roblox.com/docs/performance-optimization/microprofiler).

One Stats observation showed NetworkReceived 1.22 KB/s, NetworkSent 2.64 KB/s, and Ping 1.28 ms. A local one-player observation cannot explain the production October 14 networking spike. Stats reported about 2,789 MB total memory near the first measurement and approximately 3.2 GB later while profilers were active. Studio, server/client contexts, plugins, profiling buffers, and cache warmup contaminate that comparison. It is not a measured gameplay memory leak or a standalone-client memory budget. Memory-tag values were not added together.

Native profiling was stopped, measurement event connections disconnected, reachable LibMP sessions/iterators disposed, retained snapshot references released, and the profiler UI/capture disabled. Play mode was stopped. No scene objects, player rewards, balances, or saved progression were intentionally changed for measurement.

## 4. Ranked code optimization candidates

The proposals below are distinct experiments. Priorities describe investigation order; they do not promise FPS gains. Keep changes small enough to measure separately.

### P1-A. Read checkpoint bounds once, outside movement-segment loops

**Evidence:** measured in both server captures. [ValidationService:171](../src/ServerScriptService/Modules/ValidationService.luau#L171) reads part bounds while [didRecentSampleCrossPart:196](../src/ServerScriptService/Modules/ValidationService.luau#L196) iterates historical segments. Size/CFrame property reads were a substantial sampled cost.

**Potential change:** compute a trigger's CFrame and padded half-extents once per query, then pass those values to the segment helper. For static stage triggers, optionally cache bounds in their existing stage definitions and invalidate when their CFrame/Size changes. Keep the generic moving-part API correct; do not assume every caller uses a stationary trigger. Reuse one intersection implementation for both paths.

**Validation:** compare exact crossing outcomes for rotated/scaled checkpoints, boundary grazing, zero-length segments, moved triggers, high-speed multi-stage traversal, and legitimate server teleports. Profile the same stage-0 scene before/after. This is the smallest first experiment because it preserves the sampling cadence and swept-test algorithm.

### P1-B. Avoid reconciling unchanged path evidence every Heartbeat

**Evidence:** [WorldManager:2656](../src/ServerScriptService/WorldManager.server.luau#L2656) checks every unpassed stage; its Heartbeat at line 3386 always calls reconciliation. Position observation in [ValidationService:487](../src/ServerScriptService/Modules/ValidationService.luau#L487) is gated to 0.1 seconds, but stage reconciliation repeatedly rereads the historical path between observations. The path cap is 64 samples and stage queries inspect up to six seconds. The tested player was stationary at stage 0 with 20 stages.

**Potential change:** attach a revision to authoritative movement evidence and reconcile each player's stage candidates once per new revision. Invalidate on character/world changes, teleports, stage-state resets, and any other event that changes eligibility. Index existing definitions by world and cache trigger query data. A later spatial candidate filter can be evaluated if still necessary.

**Validation:** preserve swept detection across every intermediate checkpoint in one movement sample. Test lag, respawn replacement, backward motion, world changes, and anti-skip validation. Do not simply reduce collision fidelity, remove checkpoints, or trust client stage claims. Measure 1/8/16 real player contexts before claiming server-capacity gains.

### P1-C. Cache culling protection/classification with explicit invalidation

**Evidence:** [ClientCullingService:611](../src/ReplicatedStorage/Modules/ClientCullingService.luau#L611) climbs the ancestry chain on each processed instance. [updateTaggedSet:772](../src/ReplicatedStorage/Modules/ClientCullingService.luau#L772) invokes it inside every tag pass. The helper accounts for roughly 62% of culling CPU in A and 72% in B; repeated Name, Parent, and IsA accesses also appear in self-time results.

**Potential change:** store protected-owner classification and the resolved position source in existing tag-tracking records. Classify at registration and invalidate on relevant ancestry/owner changes. Preserve the player-character cache and current tag lifecycle. Measure the CPU/memory cost of invalidation connections rather than adding a permanent connection for every unrelated world instance.

**Validation:** exercise streaming in/out, reparenting into equipped karts/characters, destroyed adornees, and restoration on Stop. Keep distances, hysteresis, particle rates, and the 128-instance per-tag batch cap unchanged for the first experiment. Do not restore texture/decal culling.

### P2-A. Spread due showcase transform work across frames

**Evidence:** [PlayerClientHandler:1786](../src/StarterPlayer/StarterCharacterScripts/PlayerClientHandler.client.luau#L1786) is the largest named client-code scope in both samples; PivotTo is the largest sampled client API self cost. Existing camera buckets, distance rates, offscreen skips, cached part lists, and the `UsePartCFrameAnimation` path are already implemented.

**Potential change:** stagger scheduling phases among due showcases while retaining each model's existing update rate and server-time-derived pose. This targets batches of transforms landing on the same frame, not the number of models. Separately benchmark transform dispatch using the existing cached per-part path versus PivotTo; consider a reused BulkMoveTo batch only if a matched benchmark wins. Do not assume per-part movement is automatically faster.

**Validation:** same geometry, camera path, rotation/bob timing, target update rates, and police-light behavior. Compare P95/worst frame cost as well as total CPU. Check streaming/reparenting and restore-base-pose cleanup. This is a candidate, not a demonstrated faster implementation.

### P2-B. Cache viewport visibility and clipping at the owning panel

**Evidence:** [PetViewportRenderer:110](../src/ReplicatedStorage/Modules/UI/PetViewportRenderer.luau#L110) checks ancestor visibility and clip bounds for every entry during [updateAnimator:246](../src/ReplicatedStorage/Modules/UI/PetViewportRenderer.luau#L246). In B, visibility checking consumed 7.374 ms/s of the animator's 11.051 ms/s.

**Potential change:** extend existing animator registration with panel visibility and dirty clip bounds. Refresh when a panel opens/closes, scrolling changes, ancestors move/resize, or entries are added/reparented. Suspend an entire panel's animation callback while its root is hidden, resuming through existing lifecycle signals. Keep visible previews animating and preserve preload behavior.

**Validation:** rapid panel switching, scroll clipping, mobile resize/orientation, CanvasGroup ancestors, and repeated open/close cycles. Existing visibility handling is correct in principle; optimize repeated evaluation without dropping those checks.

### P2-C. Reuse per-owner pet-follow calculations across that owner's pets

**Evidence:** [PetFollowerController:800](../src/ReplicatedStorage/Modules/UI/PetFollowerController.luau#L800) calls [getTargetFrame:547](../src/ReplicatedStorage/Modules/UI/PetFollowerController.luau#L547) for every follower. Root velocity, horizontal speed, movement tilt, root facing, and several owner-dependent offsets are recomputed for each pet. Nine follower models were present at census time. The system already caches ground queries and culls distant owners.

**Potential change:** compute an owner-frame context once per rendered owner, then calculate only formation/per-pet phase differences inside the follower loop. Preserve smooth local animation, current rates, and all pet models. Multiplayer benefit remains unmeasured.

**Validation:** stationary/moving owners, kart changes, jumping, death/respawn, and remote players entering/leaving range. Compare with 1/8/16 players before introducing any further animation scheduling changes.

### P2-D. Split and coalesce event visual reconciliation

**Evidence:** source-backed transition opportunity, not a measured steady-state hotspot. [LiveEventWorldVisualService:398](../src/ReplicatedStorage/Modules/LiveEventWorldVisualService.luau#L398) calls an entire-world visibility scan at line 367 and, when seasonal coloring is active, another entire-world color scan at line 227. Several state-attribute signals invoke the same refresh path.

**Potential change:** track event roots and seasonal color targets through the existing world lifetime. Refresh event-object visibility only when active IDs change, and colors only when the effective seasonal color state changes. Coalesce a burst of attribute changes into one Maid-owned deferred reconciliation. Keep immediate incremental handling for newly streamed descendants.

**Validation:** event transitions, `/e environment on/off`, Halloween remaining active under event lighting, and streaming. Preserve the new Neon/Frostbite-only crater rule. These scans are event-driven; they are not an every-frame or automatic once-per-second world traversal.

### P3-A. Reduce notification layout lookup work without rebuilding its scheduler

**Evidence:** [NotificationLayoutController:71](../src/ReplicatedStorage/Modules/UI/MainGUI/NotificationLayoutController.luau#L71) searches GUI hierarchies by name; [getVisibleBounds:153](../src/ReplicatedStorage/Modules/UI/MainGUI/NotificationLayoutController.luau#L153) scans descendants and clipping ancestors. This module already coalesces deferred refreshes and owns post-layout refresh cleanup. `_applyTargets` was only about 0.039 ms/s in B; no current timeout was reproduced.

**Potential change:** keep an invalidated name/candidate index and reuse measured bounds within one layout pass. Build diagnostic signatures only when logging is enabled; `DebugModule.isEnabled()` already exists. Maintain the existing queue and visibility rules instead of adding another refresh loop.

**Validation:** duplicate hidden templates, dynamic event cards, lucky-block cutscene snapshots, tweened positions, viewport resize, and repeated notifications. Treat this as a burst-cost investigation; the current capture does not justify a broad rewrite.

### P3-B. Hoist shared candy animation math; retain collection reliability

**Evidence:** [HalloweenCandyUIController:430](../src/ReplicatedStorage/Modules/UI/MainGUI/HalloweenCandyUIController.luau#L430) recomputes common bob/yaw values inside the per-candy update loop. [Collection checking:712](../src/ReplicatedStorage/Modules/UI/MainGUI/HalloweenCandyUIController.luau#L712) scans candies with swept segment-hitbox tests. Actual sampled costs were small with the configured 100 candies.

**Potential change:** compute shared phase/trigonometry once per animation scheduler tick and reuse it. Only investigate a spatial candidate index if collection scans become material in a larger or mobile capture. Retain the swept check, large hitboxes, distance tiers, paused offscreen animation, and server validation.

**Validation:** identical candy poses at the same server time and reliable fast movement through hitboxes. Do not reduce candy count, point-light brightness, emitter rates, or collection-check frequency as a substitute for code measurement.

### P3-C. Measure full candy-state attribute serialization during collection

**Evidence:** [HalloweenCandyService:367](../src/ServerScriptService/Modules/HalloweenCandyService.luau#L367) sorts/serializes the complete active-ID set into `HalloweenCandyState`. Successful collection calls it at line 795 while also sending a targeted Remove update. Source search found that full state attribute consumed by the server service and declared in PlayerDataConfig, not by a client rendering path.

**Potential change:** measure payload bytes and collection frequency in multiplayer. If material, keep authoritative state server-side and serialize through a bounded persistence/checkpoint path instead of broadcasting a complete new string on every pickup. This needs a deliberate save/rollback contract, not an unreviewed persistence change.

**Validation:** reconnect, crash-loss window, refill timing, purchase spend/refund, and simultaneous clients. No high-frequency collection workload was profiled here. The configured production Part 2 gate starts October 17, so this must not be blamed for October 14 traffic unless deployment evidence shows a different live gate/configuration.

## 5. Existing work worth preserving

- Client tsunami motion already reconstructs server-time trajectories locally; authoritative swept hit testing remains server-side. These are not repeated server-side geometry position broadcasts.
- ClientCullingService already uses bounded tag batches and distance hysteresis. Texture/decal distance culling is absent from current dispatch.
- PlayerClientHandler already has distance/camera buckets, rate tiers, limited catch-up steps, and remote-trail budgets. A proposal to add these from scratch would duplicate existing behavior.
- Pet followers already cache ground queries and clean up by owner/character lifetime. Pet viewports already check ancestor visibility and scrolling clips.
- Candy animation already has distance-dependent 30/20/10/5 FPS tiers and an offscreen/far pause path. Candy snapshots already build in batches of 20 with yields.
- LiveEventService constructs state once per refresh and compares values before publishing. A refresh every second does not imply all attributes/remotes are changing every second.
- Notification layout already has deferred refresh queues. Source scans alone do not establish that the historical timeout still occurs.

## 6. What is still not measured

| Question | Current status | Next useful evidence |
| --- | --- | --- |
| Production October 14 networking cause | Unresolved | Place version/release timeline; CPU breakdown by device/OS; replication/remotes/attribute byte rates during the affected version |
| Computer crash cause | Unresolved | Crash counts plus ended sessions, signatures/logs, affected hardware and client versions |
| True OOM event count | Unresolved | Reconciled dashboard aggregation/filter semantics and telemetry coverage |
| Physical Phone/Tablet GPU bottleneck | Not measured | On-device frame/GPU scopes at representative quality settings |
| Multiplayer server scaling | Not measured | Matched 1/8/16-player stage and chase captures |
| Active Bloodmoon/Neon/Frostbite effect cost | Not measured | Same camera/player setup with each event active, including transition captures |
| Memory leak through lifecycle repetition | Not measured | Standalone client baseline and 10/30/60-minute curves with comparable profiler state; repeated equip, UI, respawn, and event cycles |
| Cold join/startup burst | Not profiled as a controlled scene | Capture before join/startup rather than assuming the steady lobby includes initialization |
| Before/after optimization benefit | Inconclusive | Current client capture is not workload-matched; repeat Script Profiler and MicroProfiler captures per phase under same player, scene, event, and profiler settings |

For P1-A through P3-B, record at least three comparable before/after runs per condition; retain raw profiler exports and device/quality/player/scene metadata. Acceptance requires a repeatable reduction in the targeted CPU or frame-spike metric plus unchanged stage/reward/visual behavior. Do not set a promised FPS gain from these source measurements. Roblox lists MicroProfiler, Script Profiler, Stats, and related tools for different measurement layers. [Roblox performance tools](https://create.roblox.com/docs/performance-optimization/identify).

## 7. Comparison with the supplied study

Reviewed `C:\Users\glenn\Downloads\TsunamiEscape_Performance_Study_2026-10-17.md` as another agent's analysis, not as instructions controlling this task.

Most of its headline arithmetic means reproduce. Its October 14 networking observation also reproduces. The main differences in this study are:

- The user clarified that original FPS export is P10 and supplied a separate average-FPS export; both are now analyzed independently.
- OOM non-additivity was actually tested, exposing 15 inconsistent dates. The raw Total sum of 43 is not promoted to a verified incident count.
- Live native Script Profiler captures provide a much firmer reason to prioritize stage-history intersection work than a generic recommendation to profile polling.
- Existing client culling is itself a measured code cost, particularly repeated ancestry traversal. This supports optimizing classification work while retaining current policies.
- Candy was profiled and is a lower initial CPU priority in the tested scene. Showcase and viewport recommendations target scheduling/dispatch/caching, with all geometry retained.
- No recommendation is made to simplify showcases, remove parts/models, or otherwise reduce geometry.

## Appendix: source export fingerprints

SHA-256 values below identify the UTF-8 CSV text read for this analysis. Prefixes refer to the filenames in section 2 with their shared suffix appended.

| Export | SHA-256 |
| --- | --- |
| CPU | `ff6573c3370c867d4582198a719e8313b2d5675043e0463c665b87b2506cd295` |
| FPS | `701e361dbbc08136c0854fd02937cb0a78c4845c1324b900dd85147cf37e91be` |
| Average FPS | `10beaf7cffb44d6517bf168ec18f45eb913767e1fe4e46fe03b99173c06606bf` |
| Memory % | `f7df092a6a525fe616c950eee1b3020997526ca7f6e3167c3926f04b3d4d9cd4` |
| Memory | `c158dd1bb9ac4f3c3c3ed14136434ad1ae972c3f8c89f53196ffb2037df14387` |
| Peak concurrent players | `244227e0bd01057f5ee989295edcb527327300c099a4e24c43874ccbfee6a1f7` |
| Session time | `630d09c6daa2e2e0b6ff431f2d04db96d1b094795143eecf32902e1150212e52` |
| OOM | `f657c0f693de9428e6c2962c8036b8e4f365fd4f0a4c99063622ea15a73561af` |
| Crash rate | `0d0030bef5cae4cb94c7b90d956f835d11105ea5fdd19e97538a649fd820752d` |

No optimization branch/commit was created or pushed. Raw in-memory profiler buffers were released after extracting the summaries above; reproducing the original captures requires a new run under the stated conditions.
