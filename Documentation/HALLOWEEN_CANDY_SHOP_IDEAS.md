# Halloween Candy Shop Ideas

## Scope

Candy collection, Lucky Block candy rolls, CandyShopFrame purchases, the physical candy shop, and a timed 2x Candy boost are wired in source. Treat this document's reward values as design targets; verify live Roblox product prices and run Studio gameplay checks before release. See **Implemented** and **Remaining Work** below.

## Exclusive Karts

Five karts, each available for candy or Robux. Kart XP Speed means base movement XP awarded per step, before player progression multipliers. Values use existing kart reward benchmarks; strongest kart gets highest price.

| Kart | Base XP Speed per step | Candy price | Robux price | Developer product ID |
| --- | ---: | ---: | ---: | ---: |
| Pumpkin Kart | 20,000 | 200 | 79 | `3718091560` |
| Coffin Kart | 35,000 | 350 | 129 | `3718091737` |
| Witch's Broom Kart | 55,000 | 500 | 199 | `3718091877` |
| Haunted Hearse | 80,000 | 700 | 299 | `3718091990` |
| Headless Horseman Kart | 110,000 | 900 | 399 | `3718092197` |

These are proposed Halloween names, base XP Speed values, and Robux prices. Candy prices and ownership entries are configured in `HalloweenCandyShopConfig.luau`; verify Robux prices against the live developer-product catalog before release. Strongest Halloween kart target is `110,000`, below Siege Tank's `225,000`. Siege Tank price was corrected to 599 Robux, while `REWARDS_AND_PRODUCTS.md` may still say 799 Robux; reconcile that separate document/catalog entry.

## Exclusive Trail

| Trail | XP Speed multiplier | Candy price | Robux price | Ownership |
| --- | ---: | ---: | ---: | --- |
| Halloween Trail | `8x` | 750 | 299 | Permanent |

`8x` sits above existing `7.5x` Demon Trail and below `15x` Galaxy Trail. `Halloween Trail` is the current working display name. Product ID `3718090969` is registered for permanent trail ownership. Candy price is configured; verify Robux price against the live developer-product catalog.

## Exclusive Halloween Lucky Block

| Block | Candy price | Robux price | PolicyService |
| --- | ---: | ---: | --- |
| Halloween Lucky Block | 150 per roll | 99 per roll; 3 rolls for 279; 5 rolls for 449 | Paid random rolls use existing PolicyService restrictions. Candy rolls use server-side candy spending and existing pet roll eligibility checks. |

Robux bundles follow `Pet-System-Design.md`: 3x is about `6.1%` off and 5x about `9.3%` off. Candy roll buttons are wired for 1x/3x/5x; confirm displayed prices match the intended balance in Studio.

Registered product IDs: `PetHalloweenLuckyBlockRoll1` = `3718091067`, `PetHalloweenLuckyBlockRoll3` = `3718091125`, `PetHalloweenLuckyBlockRoll5` = `3718091152`. Existing receipt handling grants pets from the registered Halloween pool. Shop card, pet preview, cutscene model, and candy/Robux roll buttons are wired.

Halloween environment remains available starting October 1, 2026. Part 2 content (Lucky Block, candies, and related gameplay) unlocks October 17, 2026 at 8:00 AM PHT (`2026-10-17 00:00 UTC`). Starting next October, Part 2 gate opens October 1. Part 2 uses replicated `LiveEventState.HalloweenPartTwoActive`; environment, decorations, and music remain on the October 1 seasonal schedule.

One block type, rollable with candy or Robux. Candy purchase spends are validated on the server; Robux rolls remain policy-gated.

### Lucky Block Pet Pool

Five exclusive variants are registered in `PetConfig` using existing Halloween model assets. Hacker/Glitch variants are excluded. Multipliers match Premium Lucky Block values for available rarities; Rare uses existing Tier 3 Rare value because Premium currently has no Rare pets. These are XP Speed multipliers, not Blood Moon stats. Odds use existing rarity weights and luck adjustments, not custom fixed percentages.

| Pet variant | Source model | Rarity | XP Speed multiplier | Chance | Halloween texture direction |
| --- | --- | --- | ---: | ---: | --- |
| Lava Meowl | `Halloween/01_LavaMeowl` | Rare | `2.5x` | Existing Rare weight | Black-cat silhouette, ember eyes, small pumpkin-orange accents. |
| Gold Boneca Ambalabu | `Halloween/02_GoldBonecaAmbalabu` | Rare | `2.5x` | Existing Rare weight | Antique haunted-toy gold, cracked porcelain-like markings, restrained purple glow. |
| Galaxy Dragon Cannelloni | `Halloween/03_GalaxyDragonCannelloni` | Epic | `4.5x` | Existing Epic weight | Deep violet scales, orange flame highlights, tiny starfield details. |
| Diamond Brr Brr Patapim | `Halloween/04_DiamondBrrBrrPatapim` | Legendary | `5.5x` | Existing Legendary weight | Frosted haunted-forest bark, pumpkin-orange eyes, dark moss accents. |
| Lava Strawberry Elephant | `Halloween/05_LavaStrawberryElephant` | Mythic | `13.5x` | Existing Mythic weight | Charcoal-red strawberry texture, molten orange glow, eerie green leaf accents. |

Odds use existing rarity weights and luck adjustments; they are not fixed percentages in this document. Premium references: Epic `4.5x`, Legendary `5.5x`, Mythic `13.5x`. Tier 3 Rare reference: `2.5x`.

## Proposed Robux Price Bounds

Proposed minimum shop offer: `19` Robux. Proposed maximum: `399` Robux. Karts use a stepped ladder; Halloween Trail is proposed at `299` Robux and Lucky Block at `99` per roll, with discounted 3x/5x bundles. These prices are suggestions, not current catalog entries.

## Candy Collection And Refill

- Current cap is `100` active pickups per player across World 1 roads. Pickup visuals are local to each player, so players do not compete for the same candy.
- Each pickup grants exactly `1` candy at every stage. Later stages get more pickup locations, not higher candy value or a stage multiplier.
- Spawn slots are generated across available roads with spacing and road-edge/end margins; exact per-stage distribution is not explicitly configured as 20/30/50.
- Every `2` minutes, add up to `25` pickups to replace collected ones, capped at `100` active pickups per player. Refill replenishes world pickups, not the player's wallet.
- Refill only collected slots; do not duplicate uncollected pickups. Keep each pickup single-claim per player.
- Validate pickup ownership, stage reach, distance, and claim state on the server. Local visuals do not make candy grants client-authoritative.
- After initial stock is collected, refill creates at most `12.5` new pickups per minute on average. Actual earnings depend on collection rate and available roads.

### Candy Shop Prices

| Item | Candy price |
| --- | ---: |
| Halloween Lucky Block roll | 150 |
| Pumpkin Kart | 200 |
| Coffin Kart | 350 |
| Witch's Broom Kart | 500 |
| Haunted Hearse | 700 |
| Halloween Trail | 750 |
| Headless Horseman Kart | 900 |

Prices are balance targets. Assuming 100 initial pickups collected, then collecting every refill promptly, approximate minimum time to afford one item is:

| Item | Candy | Approx. minimum after initial 100 |
| --- | ---: | ---: |
| Halloween Lucky Block roll | 150 | 4 minutes |
| Pumpkin Kart | 200 | 8 minutes |
| Coffin Kart | 350 | 20 minutes |
| Witch's Broom Kart | 500 | 32 minutes |
| Haunted Hearse | 700 | 48 minutes |
| Halloween Trail | 750 | 52 minutes |
| Headless Horseman Kart | 900 | 64 minutes |

Times assume `100` initial pickups collected, then all `25` pickups from each `2`-minute refill collected promptly. Real times will be longer. All five karts plus Halloween Trail cost `3,400` candy and take about `4 hours 24 minutes` of nonstop collection from zero, without spending candy on Lucky Block rolls. Rebalance after measuring actual collection rates and event duration.

## Candy Boost

| Product | Effect | Duration | Robux price | Developer product ID |
| --- | --- | ---: | ---: | ---: |
| 2x Candy | Doubles candy pickup rewards while active | 30 minutes; repeat purchase extends remaining time | 49 | `3718114515` |

The boost is first in Candy Shop and Robux-only. `CandyCountFrame.CountdownLabel` shows `2x for MM:SS` while active and hides when inactive. Existing candy balance is not multiplied retroactively.

## Existing Systems To Reuse

- Pet pools, rarity odds, lucky-block definitions, and pet XP multipliers: `ReplicatedStorage/Modules/Config/PetConfig.luau`.
- Existing kart model and event lookup: `ReplicatedStorage/Modules/KartCatalog.luau`.
- Existing kart XP reward benchmarks, including Siege Tank: `REWARDS_AND_PRODUCTS.md`.
- Event Kart/Trail unlock handling: `ServerScriptService/Modules/LiveEventService.luau`.
- Trail inventory and equipped-trail state: `ServerScriptService/Modules/EconomyService.luau`.
- XP Speed grant patterns: `ServerScriptService/Modules/DailyRewardsService.luau` and `ServerScriptService/Modules/PlaytimeRewardsService.luau`.

## Implemented

- Halloween-only, per-player candy pickups spawn along World 1 roads. Candy balance and collection progress persist across sessions.
- Server validates collection requests, distance, eligibility, and claim state. Active pickups are capped at `100`, with up to `25` replenished every `120` seconds.
- Candy visuals bob and rotate, with orange highlight, light, and particles. Collection plays a burst effect; distant visuals are reduced through culling.
- `CandyCountFrame` shows the player's balance and candy icon. Shared settings and player-data defaults are configured.
- Candy milestone tracking uses cumulative candy collected, not current wallet balance. Badge IDs are configured for thresholds `10`, `100`, `250`, `500`, and `1000`.
- Halloween Trail is configured at `8x`, with persistent ownership and equip support. Five Halloween kart developer products and permanent ownership receipt mappings are registered.
- Halloween Part 2 date gate and replicated active state, Lucky Block pet pool, rarity-based odds, billboard, ShopFrame card, pet preview, cutscene model, and 1x/3x/5x Robux/candy rolls are wired. Candy collection and Part 2 shop follow the gate; seasonal environment, decorations, and music follow the October seasonal schedule.
- `CandyShopFrame` opens from `CandyCountFrame.RotateImage` or the physical shop's `TouchPart`. Touching opens it; leaving touch area closes it. Physical shop model is cloned into World 1 decorations during Part 2; its `Ghost` bobs locally.
- Candy shop displays Lucky Block rolls, five karts, and Halloween Trail. Candy purchases are server-validated, spend candy, persist kart/trail ownership, and disable/darken owned cards. Robux purchases use registered developer products and receipt grants.
- Candy Lucky Block rolls support candy and Robux buttons. Existing policy restrictions apply to paid random rolls.
- First Candy Shop product card is the 30-minute 2x Candy boost. Its developer-product receipt extends the saved expiration; candy pickup rewards and cumulative candy milestone progress double while active. Its candy-purchase button is hidden.

## Remaining Work

- Run Studio end-to-end checks for pickup placement/collection, refill cadence, physical shop enter/exit behavior, ghost bobbing, candy and Robux purchases, insufficient funds, save/rejoin, and event-gate transitions. Source wiring is not runtime verification.
- Verify live developer-product prices match the Robux price targets in this document; source registers product IDs but Roblox catalog prices are set separately.
- Confirm candy-roll displayed prices, odds/luck behavior, and purchase UX in Studio; adjust balance only after playtesting actual pickup rates.
- Reconcile Siege Tank price in `REWARDS_AND_PRODUCTS.md` with the corrected 599 Robux price.

Treat listed Robux prices and XP rates as design targets until checked against live catalog/game configuration. Candy costs and feature wiring are current source configuration; rebalance only after playtesting.
