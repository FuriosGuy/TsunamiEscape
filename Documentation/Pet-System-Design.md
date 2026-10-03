# Pet System Design

Status: Pet inventory progression, server-authoritative Lucky Block grants, receipt-safe paid rolls, dynamic Luck odds, paid-random policy gating, duplicate reveal consolidation, Faster Open, the block-plus-pet reveal sequence, and equipped-pet follower visuals exist in source. Follower visuals still need Studio/device verification. This is a static source audit on 2026-10-03, not runtime verification.

## Scope

- Exactly three normal Lucky Blocks bought with spendable Wins per roll.
- One permanent Premium Lucky Block sold for Robux.
- One rotating Event Lucky Block sold for Robux during the active event.
- Pets use models from `ReplicatedStorage.BrainrotPets`, grouped by Lucky Block ID.
- Tier 1 uses Common and Rare pets; Tier 2 and Tier 3 also include Epic and Legendary pets.
- Premium and event pets use Epic, Legendary, and Mythic pets.

This produces four permanent Lucky Block entries plus one rotating event slot: three normal Lucky Blocks, one permanent Premium Lucky Block, and one Event Lucky Block whose pet pool changes for Blood Moon, Neon Rush, and Frostbite Rally. The event slot is reused instead of permanently adding three separate event Lucky Blocks.

Model lookup uses `ReplicatedStorage.BrainrotPets/<LuckyBlockId>/<model folder>` as recorded in each `PetConfig` entry. `PetViewportRenderer` clones these models into UI `ViewportFrame`s and removes scripts and particle effects from preview clones. Pack asset `Tung Sahur` displays to players as **Tung Tung Tung Sahur**.

## Rarity and multiplier rules

Use this player-facing rarity order:

**Common → Rare → Epic → Legendary → Mythic**

| Rarity | Used by | Intended role |
|---|---|---|
| Common | Tier 1, Tier 2, and Tier 3 Lucky Blocks | Basic result; fewer Common pets in higher tiers |
| Rare | Tier 1, Tier 2, and Tier 3 Lucky Blocks | Noticeable normal progression upgrade |
| Epic | Tier 2 and Tier 3 Lucky Blocks, Premium, and events | Strong normal or special result |
| Legendary | Tier 2 and Tier 3 Lucky Blocks, Premium, and events | High-value late-game or special result |
| Mythic | Premium and events | Rarest special result and collection target |

## Brainrot chance-weight system

Use global Brainrot chance weights instead of hard-coding final percentages.

Recommended balanced rarity weights:

| Rarity | Chance weight |
|---|---:|
| Common | 100% |
| Rare | 60% |
| Epic | 35% |
| Legendary | 12% |
| Mythic | 1% |

These are relative weights, not independent final percentages; a 100% weight does not guarantee the result. The server should normalize every pet's weight inside the selected Lucky Block before rolling.

Examples:

```text
Tier 1 Lucky Block: six Common pets at 100% weight and four Rare pets at 60% weight
Total weight = (6 × 100) + (4 × 60) = 840
Each Common = 100 / 840 = 11.90% — 71.43% total Common
Each Rare = 60 / 840 = 7.14% — 28.57% total Rare

Tier 2: three Common at 100%, three Rare at 60%, two Epic at 35%, two Legendary at 12%
Total weight = (3 × 100) + (3 × 60) + (2 × 35) + (2 × 12) = 574
Common = 52.26%, Rare = 31.36%, Epic = 12.20%, Legendary = 4.18%

Tier 3: two Common at 100%, three Rare at 60%, three Epic at 35%, two Legendary at 12%
Total weight = (2 × 100) + (3 × 60) + (3 × 35) + (2 × 12) = 509
Common = 39.29%, Rare = 35.36%, Epic = 20.63%, Legendary = 4.72%

Event Lucky Block: two Epics at 35% weight, two Legendaries at 12% weight, one Mythic at 1% weight
Total weight = (2 × 35) + (2 × 12) + 1 = 95
Epic = 73.68%, Legendary = 25.26%, Mythic = 1.05%

Premium Lucky Block: four Epics at 35% weight, three Legendaries at 12% weight, one Mythic at 1% weight
Total weight = (4 × 35) + (3 × 12) + 1 = 177
Epic = 79.10%, Legendary = 20.34%, Mythic = 0.56%
```

Luck adjusts these weights through a soft curve. It should not simply multiply every weight by raw luck, because that would not improve rarity odds.

Recommended pet multiplier ladder:

| Source | Rarity | Pet multiplier | Bonus over 1x |
|---|---|---:|---:|
| Tier 1 Lucky Block | Common | 1.25x | +25% |
| Tier 1 Lucky Block | Rare | 1.55x | +55% |
| Tier 2 Lucky Block | Common | 1.50x | +50% |
| Tier 2 Lucky Block | Rare | 2.00x | +100% |
| Tier 2 Lucky Block | Epic | 2.75x | +175% |
| Tier 2 Lucky Block | Legendary | 4.25x | +325% |
| Tier 3 Lucky Block | Common | 1.75x | +75% |
| Tier 3 Lucky Block | Rare | 2.50x | +150% |
| Tier 3 Lucky Block | Epic | 3.50x | +250% |
| Tier 3 Lucky Block | Legendary | 4.75x | +375% |
| Premium and Neon Rush/Frostbite Rally Lucky Blocks | Epic | 4.50x | +350% |
| Premium and Neon Rush/Frostbite Rally Lucky Blocks | Legendary | 5.50x | +450% |
| Premium and Neon Rush/Frostbite Rally Lucky Blocks | Mythic | 13.50x | +1,250% |
| Blood Moon Event Lucky Block | Epic | 5.50x | +450% |
| Blood Moon Event Lucky Block | Legendary | 7.50x | +650% |
| Blood Moon Event Lucky Block | Mythic | 16.00x | +1,500% |

Base multipliers rise by Win-priced Lucky Block tier. Premium and standard Event Lucky Blocks are stronger than Tier 3; Blood Moon is strongest. Star-upgrade bonuses remain separate and unchanged. Paid star upgrades raise standard Premium/Event Mythics to 25.50x and Blood Moon Mythics to 28.00x. Pet multipliers remain separate from the existing product multiplier ladder.

### Equipped-pet stacking

Equipped pets combine additively over 1x. Their combined contribution then multiplies the full gameplay XP multiplier. With no equipped pets, pet contribution is 1.00x.

```text
TotalPetMultiplier = 1 + sum(each equipped pet multiplier - 1)
GameplayXPMultiplier = ExistingGameplayXPMultiplier * TotalPetMultiplier
```

Examples:

```text
One Common pet at 1.25x = 1.25x pet multiplier
Common 1.25x + Rare 1.55x = 1 + 0.25 + 0.55 = 1.80x pet multiplier
36x existing gameplay XP multiplier * 1.80x pets = 64.80x final gameplay XP multiplier
Two equipped 2.00x pets = 3.00x pet multiplier; 36x existing * 3.00x = 108x final
```

Pet contributions add together, not multiply together. Other gameplay XP sources combine according to their existing implementation; the combined pet multiplier is then multiplied against that result. Reward paths remain excluded from pet bonus. Players start with three equipped-pet slots; additional slot purchases have no design cap. For example, three fully upgraded standard Premium/Event Mythics contribute 72x pet multiplier, while three Blood Moon Mythics contribute 81x. These are examples, not a team multiplier cap.

Numeric rarity IDs should remain internal implementation details. Do not show the old numeric 3–6 labels to players.

`PetMultiplier` is the pet's standalone contribution. For example, `1.25x` means a +25% pet bonus before other systems are combined.

Pets do not overwrite the ownership-derived `WinMultiplier` attribute. The server calculates pet contribution separately and applies it to gameplay XP only. Pet bonus does not apply to daily, group, or other exact reward grants.

## Normal Lucky Blocks

Each normal Lucky Block contains ten Brainrots. Tier 1 uses Normal variants. Tiers 2 and 3 mix Normal, Oro, Diamond, and Galaxy skins. Tier 2 has three Common pets; Tier 3 has two. Skin variant does not determine rarity: Normal models can be Rare or Epic, for example. Normalized chance weights make rarity outcomes vary per roll. Neither tier uses Hacker or Lava variants.

### Tier 1 Lucky Block

Cost: **100 Wins per roll**, deducted from current `WinCount`.

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---:|---:|---:|
| Tralalero Tralala | Normal | Common | 100% | 1.25x |
| Bombardiro Crocodilo | Normal | Common | 100% | 1.25x |
| Tung Sahur | Normal | Common | 100% | 1.25x |
| Ballerina Cappuccina | Normal | Common | 100% | 1.25x |
| Chimpanzini Bananini | Normal | Common | 100% | 1.25x |
| Trippi Troppi | Normal | Common | 100% | 1.25x |
| Lirili Larila | Normal | Rare | 60% | 1.55x |
| Brr Brr Patapim | Normal | Rare | 60% | 1.55x |
| Cappuccino Assassino | Normal | Rare | 60% | 1.55x |
| Cocofanto Elefanto | Normal | Rare | 60% | 1.55x |

Rarity pool: Common and Rare.

### Tier 2 Lucky Block

Cost: **5,000 Wins per roll**, deducted from current `WinCount`.

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---:|---:|---:|
| Gold La Grande Combinasion | Oro | Common | 100% | 1.50x |
| Meowl | Normal | Common | 100% | 1.50x |
| Cacto Hipopotamo | Normal | Common | 100% | 1.50x |
| Bombombini Gusini | Normal | Rare | 60% | 2.00x |
| Gold Lirili Larila | Oro | Rare | 60% | 2.00x |
| Gold Tralalero Tralala | Oro | Rare | 60% | 2.00x |
| Diamond Tung Sahur | Diamond | Epic | 35% | 2.75x |
| Diamond Ballerina Cappuccina | Diamond | Epic | 35% | 2.75x |
| Galaxy Trippi Troppi | Galaxy | Legendary | 12% | 4.25x |
| Galaxy Cacto Hipopotamo | Galaxy | Legendary | 12% | 4.25x |

Rarity pool: Common, Rare, Epic, and Legendary.

### Tier 3 Lucky Block

Cost: **50,000 Wins per roll**, deducted from current `WinCount`.

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---:|---:|---:|
| Strawberry Elephant | Normal | Legendary | 12% | 4.75x |
| 1x1x1x1 | Normal | Epic | 35% | 3.50x |
| Six Seven | Normal | Common | 100% | 1.75x |
| Gold Tung Sahur | Oro | Rare | 60% | 2.50x |
| Gold Trippi Troppi | Oro | Rare | 60% | 2.50x |
| Gold Ballerina Cappuccina | Oro | Rare | 60% | 2.50x |
| Diamond Tralalero Tralala | Diamond | Epic | 35% | 3.50x |
| Diamond Bombardiro Crocodilo | Diamond | Epic | 35% | 3.50x |
| Galaxy Lirili Larila | Galaxy | Epic | 35% | 3.50x |
| Galaxy Chimpanzini Bananini | Galaxy | Legendary | 12% | 4.75x |

Rarity pool: Common, Rare, Epic, and Legendary.

## Permanent Premium Lucky Block

Suggested acquisition: permanent Robux purchase. Recommended Premium Lucky Block price: **99 Robux per roll**, with 3 rolls for **279 Robux** (about 6.1% off) or 5 rolls for **449 Robux** (about 9.3% off). Bundle prices end in 9; rounded pricing takes priority over hitting the exact discount percentage.

The Premium Lucky Block contains eight Brainrots randomly rolled from its configured pack pool below. It should not invalidate the 50,000-win Tier 3 Lucky Block. These picks use higher pack variants, separate from fixed event themes.

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---:|---:|---:|
| Gold Chimpanzini Bananini | Oro | Epic | 35% | 4.50x |
| Diamond Cappuccino Assassino | Diamond | Epic | 35% | 4.50x |
| Galaxy Tralalero Tralala | Galaxy | Epic | 35% | 4.50x |
| Galaxy Bombardiro Crocodilo | Galaxy | Epic | 35% | 4.50x |
| Gold Meowl | Oro | Legendary | 12% | 5.50x |
| Galaxy La Grande Combinasion | Galaxy | Legendary | 12% | 5.50x |
| Galaxy Strawberry Elephant | Galaxy | Legendary | 12% | 5.50x |
| Hacker 1x1x1x1 | Hacker | Mythic | 1% | 13.50x |

Rarity pool: Epic, Legendary, and Mythic.

## Rotating Event Lucky Block

Event pets come from one rotating **Event Lucky Block**. Each event has one fixed price per roll; pets within the Lucky Block do not have separate Robux prices. Neon Rush and Frostbite Rally cost 99 Robux per roll; Blood Moon remains 129 Robux per roll.

Recommended Neon Rush and Frostbite Rally Event Lucky Block price: **99 Robux per roll**, with 3 rolls for **279 Robux** (about 6.1% off) or 5 rolls for **449 Robux** (about 9.3% off). Blood Moon remains **129 Robux per roll**, with 3 rolls for **369 Robux** (about 4.7% off) or 5 rolls for **579 Robux** (about 10.2% off). Bundle prices end in 9, so discounts are approximate.

Rarity controls the roll chance through relative weights. Each event pool has five pets: two Epic, two Legendary, and one Mythic:

| Rarity | Event Lucky Block chance weight |
|---|---:|
| Epic | 35% |
| Legendary | 12% |
| Mythic | 1% |

With two pets per common event rarity and one Mythic, normalized Event Lucky Block odds are Epic **73.68%**, Legendary **25.26%**, and Mythic **1.05%**. The Premium Lucky Block has four Epic, three Legendary, and one Mythic pet: normalized rarity odds are Epic **79.10%**, Legendary **20.34%**, and Mythic **0.56%**. Luck can modify these rarity weights, but Lucky Block's Robux price stays unchanged.

### Blood Moon

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---|---:|---:|
| Lava Bombardiro Crocodilo | Lava | Epic | 35% | 5.50x |
| Lava Ballerina Cappuccina | Lava | Epic | 35% | 5.50x |
| Lava Tralalero Tralala | Lava | Legendary | 12% | 7.50x |
| Lava Cappuccino Assassino | Lava | Legendary | 12% | 7.50x |
| Lava Tung Sahur | Lava | Mythic | 1% | 16.00x |

### Neon Rush

| Pet display name | Pack asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---|---|---:|---:|
| Neon Tralalero Tralala | Hacker Tralalero Tralala | Hacker | Epic | 35% | 4.50x |
| Neon Cappuccino Assassino | Hacker Cappuccino Assassino | Hacker | Epic | 35% | 4.50x |
| Neon Chimpanzini Bananini | Hacker Chimpanzini Bananini | Hacker | Legendary | 12% | 5.50x |
| Neon La Grande Combinasion | Hacker La Grande Combinasion | Hacker | Legendary | 12% | 5.50x |
| Neon Tung Sahur | Hacker Tung Sahur | Hacker | Mythic | 1% | 13.50x |

### Frostbite Rally

| Brainrot asset | Variant tier | Rarity | Chance weight | Pet multiplier |
|---|---|---|---:|---:|
| Diamond Lirili Larila | Diamond | Epic | 35% | 4.50x |
| Diamond Meowl | Diamond | Epic | 35% | 4.50x |
| Diamond Blueberrinni Octopusini | Diamond | Legendary | 12% | 5.50x |
| Diamond Cacto Hipopotamo | Diamond | Legendary | 12% | 5.50x |
| Diamond Dragon Cannelloni | Diamond | Mythic | 1% | 13.50x |

## Counts

| Collection | Active pet count | Notes |
|---|---:|---|
| Tier 1 Lucky Block | 10 | Normal Brainrot variants, mostly Common |
| Tier 2 Lucky Block | 10 | Normal, Oro, Diamond, and Galaxy variants; Rare, Epic, and Legendary |
| Tier 3 Lucky Block | 10 | Normal, Oro, Diamond, and Galaxy variants; Rare, Epic, and Legendary |
| Premium Lucky Block | 8 | Random roll from selected high-tier Brainrot pool |
| Each event rotation | 5 | Event-specific variants inside rotating Event Lucky Block |
| Total normal and permanent pets | 38 | 30 normal + 8 Premium |
| Total across the first three event themes | 15 | Five rotating pets per event |
| Total unique assets across current pools | 53 | No model asset is shared between pools |

## Pet backpack

The backpack stores owned pet copies, including duplicates needed for star upgrades. Equipped pets also count toward backpack capacity.

Starting capacity: **25 pets**. No maximum capacity.

| Product | Type | Effect | Price |
|---|---|---:|---:|
| PetBackpackSlotPlusFifteen | Developer product, repeatable | +15 backpack slots | 49 Robux |

Use one developer product for this upgrade. Each purchase permanently adds 15 backpack slots for 49 Robux. Keep the purchase prompt available; there is no maximum capacity.

## Pet star upgrades

Stars require identical copies of the same pet. Different pets with the same rarity cannot be combined. Maximum: **3 stars**.

| Rarity | 2-star recipe | 3-star recipe | Total base copies for 3 stars | Star bonus |
|---|---:|---:|---:|---:|
| Common | 5 identical 1-star pets | 5 identical 2-star pets | 25 | +0.50x at 2 stars, +1.00x at 3 stars |
| Rare | 4 identical 1-star pets | 4 identical 2-star pets | 16 | +0.75x at 2 stars, +1.50x at 3 stars |
| Epic | 3 identical 1-star pets | 3 identical 2-star pets | 9 | +1.25x at 2 stars, +2.50x at 3 stars |
| Legendary | 3 identical 1-star pets | 3 identical 2-star pets | 9 | +1.50x at 2 stars, +3.00x at 3 stars |
| Mythic | 3 identical 1-star pets | 3 identical 2-star pets | 9 | +5.00x at 2 stars, +10.00x at 3 stars |

Star bonuses are added to the pet's own multiplier. They do not multiply the pet's multiplier.

Example: a 1-star Tier 1 Common at 1.25x becomes 1.75x at 2 stars and 2.25x at 3 stars. A 1-star Tier 3 Epic at 3.50x becomes 4.75x at 2 stars and 6.00x at 3 stars. A 1-star Tier 3 Legendary at 4.75x becomes 6.25x at 2 stars and 7.75x at 3 stars. A 1-star standard Premium/Event Epic at 4.50x becomes 6.25x at 2 stars and 8.00x at 3 stars. A standard Premium/Event Legendary at 5.50x becomes 9.00x at 2 stars and 12.50x at 3 stars. A standard Premium/Event Mythic at 13.50x becomes 19.50x at 2 stars and 25.50x at 3 stars. A Blood Moon Mythic at 16.00x becomes 22.00x at 2 stars and 28.00x at 3 stars.

### Premium/Event star bonuses

All pets use the same rarity-based merge recipe, regardless of whether they came from a Win-priced, Premium, or Event Lucky Block. Premium and Event pets keep stronger star multiplier bonuses; those bonuses do not reduce required copies.

| Rarity | 2-star bonus | 3-star bonus |
|---|---:|---:|
| Epic | +1.75x | +3.50x |
| Legendary | +3.50x | +7.00x |
| Mythic | +6.00x | +12.00x |

For example, six 1-star Event Mythics produce exactly two 2-star Mythics. A 3-star Mythic requires nine 1-star copies: three 1-star copies create each of three 2-star copies, which then merge into one 3-star pet. Robux purchase status changes star bonuses only, not merge copy requirements.

At maximum upgrade, one standard Premium/Event Mythic pet provides 25.50x; one Blood Moon Mythic provides 28.00x. Three equipped 3-star standard Mythics provide 74.50x combined pet multiplier; three Blood Moon Mythics provide 82.00x. These totals use the additive-over-one formula above. With uncapped equip-slot purchases, there is no fixed team multiplier ceiling. This is a theoretical progression example, not an expected result from a small number of rolls.

## Pet equip slots

| Product | Type | Effect | Price |
|---|---|---:|---:|
| — | Free starting slots | 3 equipped pets | — |
| PetEquipSlotPlusThree | Repeatable developer product | +3 equipped pet slots per purchase | 79 Robux |

Use one developer product for additional equip slots. It can be purchased without a cap; each purchase permanently adds three slots for 79 Robux. Do not create separate products for each slot milestone. Actual equipped count still depends on how many pets the player owns and can store. The backpack starts with 25 slots and has no maximum, so its capacity will not impose a fixed equip limit.

## Roll system

| Roll option | Availability | Recommended price |
|---|---|---:|
| 1x roll | Available to everyone | — |
| 3x roll | Available roll option; paid blocks use 3-roll developer product | Per-block cost |
| 5x roll | Available roll option; paid blocks use 5-roll developer product | Per-block cost |
| Faster Open | Permanent gamepass | 99 Robux |

For normal Win-priced Lucky Blocks, 3x and 5x batch options are available without gamepasses and spend three or five times the per-roll Win cost. Owned Faster Open skips the meteor fall and roulette only; block lands at crater immediately, then pets jump into reveal. Server-selected results, odds, cost, and grants stay unchanged.

For Premium and Event Lucky Blocks, each roll button routes to its matching paid developer product. The 1x Premium/Event roll uses its 1x developer product. The 3x and 5x products charge for three or five results. Faster Open applies to every roll type without changing odds, cost, or rewards.

Batch rolls use the same per-result odds and do not secretly improve luck. Luck is evaluated separately for every result.

### Hatch controls

Keyboard shortcuts work only while the Lucky Block hatch UI is open. Mouse and touch users can select the matching on-screen roll button.

| Input | 1x roll | 3x roll | 5x roll |
|---|---|---|---|
| Keyboard | E | R | T |
| Mouse or touch | Click/tap 1x button | Click/tap 3x button | Click/tap 5x button |

Console gamepad: use the D-pad or left stick to select a roll button, then press **A** on Xbox or **Cross** on PlayStation to activate it. **B/Circle** backs out or closes the hatch UI. Gamepad input must use the same server-authoritative validation and purchase flow as clicking a button. Do not bind hatch controls while the hatch UI is closed; keep Roblox's normal navigation and back/cancel behavior.

### Win-roll costs

Normal Tier 1–3 Lucky Blocks spend the player's current `WinCount` balance per roll. Tier 1 costs 100 Wins, Tier 2 costs 5,000 Wins, and Tier 3 costs 50,000 Wins. Batch costs scale linearly: 3x costs three times the block's per-roll cost; 5x costs five times. These prices are costs, not lifetime unlock thresholds. Server validates request type/count, loaded player data, nearby block, active event where applicable, and Win balance. No 3x/5x gamepass is required.

The server selects and grants normal results. Win rolls check free storage and balance before spending; paid product receipts persist pet inventory or overflow claims before acknowledgement. Creator test grants remain supported for purchase-flow testing.

Premium and Event Lucky Blocks remain Robux-only and do not also subtract Wins. There are no lifetime-Win unlock thresholds or separate unlock flags in this design.

Dedicated Lucky Block roll developer-product keys already exist in `ProductCatalog`. Keep them separate from `Spin1`, `Spin3`, and `Spin5`; no 3x/5x Lucky Block gamepasses are used.

## Luck system

Luck changes rarity weighting for normal, Premium, and Event Lucky Block rolls. Server roll selection and client disclosure use same shared formula; it does not directly increase pet multiplier or guarantee a Legendary or Mythic result.

Adjusted weight is `baseChanceWeight * (1 + log10(luckMultiplier) * rarityWeightBonus)`. Bonuses: Common `0`, Rare `0.15`, Epic `0.35`, Legendary `0.70`, Mythic `3`. At 10x Luck, these become weight factors `1.00x`, `1.15x`, `1.35x`, `1.70x`, and `4.00x`; Luck improves higher-rarity weights without guaranteeing Mythic results. With current roster weights, normalized Mythic odds are:

| Luck | Event Lucky Blocks | Premium Lucky Block |
|---|---:|---:|
| 1x | 1.0526% | 0.5650% |
| 2x | 1.7567% | 0.9504% |
| 4x | 2.3064% | 1.2557% |
| 6x | 2.5754% | 1.4065% |
| 8x | 2.7475% | 1.5034% |
| 10x | 2.8715% | 1.5736% |

Tier 1–3 contain no Mythic pets, so Mythic odds remain 0% there at every Luck level. Lucky Block pet cards display current per-item probability to four decimal places; largest-remainder rounding makes displayed odds total exactly 100.0000%.

Pet luck is a **permanent progression upgrade**, saved to the player's data. It starts at 1x and advances through sequential developer products; players can buy only the next tier, so 10x cannot be purchased immediately.

| Tier | Developer product key | Price | Cumulative spend to unlock |
|---|---|---:|---:|
| 2x | `PetLuck2x` | 79 Robux | 79 Robux |
| 4x | `PetLuck4x` | 129 Robux | 208 Robux |
| 6x | `PetLuck6x` | 229 Robux | 437 Robux |
| 8x | `PetLuck8x` | 379 Robux | 816 Robux |
| 10x | `PetLuck10x` | 499 Robux | 1,315 Robux |

Each purchase permanently unlocks the next tier and replaces the previous Luck value; tiers do not stack. Server receipt handling accepts only the exact next tier. Out-of-order receipts remain unprocessed for retry after prerequisite tiers; already-owned tier receipts are consumed without changing Luck. UI offers only next tier, hides Luck purchase controls for users restricted by `PolicyService`, and updates per-item odds after successful upgrade. Roblox generally recommends passes for permanent one-time powers, but this design keeps separate developer products for the requested step-by-step ladder.

Luck applies a soft-weighting curve to rarity weights; 10x luck must not mean ten times the Mythic odds or guarantee Mythic pets. Since paid luck modifies paid-random-item odds, show the player's actual numerical odds for every possible pet before each paid roll and update them for their current luck tier. Apply Roblox's per-player paid-random-item eligibility policy before offering paid Lucky Blocks or paid luck. See [Roblox's paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items) and [developer product guidance](https://create.roblox.com/docs/production/monetization/developer-products).

## Initial equip recommendation

Start with three free equipped pet slots. Players can purchase unlimited additional slots for 79 Robux each. All equipped pet multipliers add together, and only the resulting pet total is combined with the existing server-side win multiplier.

## Performance constraints

- Prefer one MeshPart or a very small number of parts per pet.
- Keep pet collisions disabled and avoid unnecessary physics.
- Avoid continuous particle effects on normal pets.
- Use short, reusable idle animations rather than unique animation systems per pet.
- Keep pet shadows disabled by default on mobile and tablet.
- Apply distance culling to pets when the system is implemented.

## Developer products: names and prices

Use these as internal product catalog keys. Create separate Roblox developer products for each row. Store the numeric Roblox `ProductId` separately; do not use the name as the numeric ID.

Separate Premium and event product keys keep receipt handling unambiguous if an unfinished purchase is processed after the active event changes.

| Developer product key | Purpose | Price |
|---|---|---:|
| `PetTier1LuckyBlockRoll1` | 1 Tier 1 Lucky Block roll | 19 Robux |
| `PetTier1LuckyBlockRoll3` | 3 Tier 1 Lucky Block rolls | 59 Robux |
| `PetTier1LuckyBlockRoll5` | 5 Tier 1 Lucky Block rolls | 89 Robux |
| `PetTier2LuckyBlockRoll1` | 1 Tier 2 Lucky Block roll | 39 Robux |
| `PetTier2LuckyBlockRoll3` | 3 Tier 2 Lucky Block rolls | 109 Robux |
| `PetTier2LuckyBlockRoll5` | 5 Tier 2 Lucky Block rolls | 179 Robux |
| `PetTier3LuckyBlockRoll1` | 1 Tier 3 Lucky Block roll | 59 Robux |
| `PetTier3LuckyBlockRoll3` | 3 Tier 3 Lucky Block rolls | 169 Robux |
| `PetTier3LuckyBlockRoll5` | 5 Tier 3 Lucky Block rolls | 269 Robux |
| `PetPremiumLuckyBlockRoll1` | 1 Premium Lucky Block roll | 99 Robux |
| `PetPremiumLuckyBlockRoll3` | 3 Premium Lucky Block rolls | 279 Robux |
| `PetPremiumLuckyBlockRoll5` | 5 Premium Lucky Block rolls | 449 Robux |
| `PetBloodMoonLuckyBlockRoll1` | 1 Blood Moon Event Lucky Block roll | 129 Robux |
| `PetBloodMoonLuckyBlockRoll3` | 3 Blood Moon Event Lucky Block rolls | 369 Robux |
| `PetBloodMoonLuckyBlockRoll5` | 5 Blood Moon Event Lucky Block rolls | 579 Robux |
| `PetNeonRushLuckyBlockRoll1` | 1 Neon Rush Event Lucky Block roll | 99 Robux |
| `PetNeonRushLuckyBlockRoll3` | 3 Neon Rush Event Lucky Block rolls | 279 Robux |
| `PetNeonRushLuckyBlockRoll5` | 5 Neon Rush Event Lucky Block rolls | 449 Robux |
| `PetFrostbiteRallyLuckyBlockRoll1` | 1 Frostbite Rally Event Lucky Block roll | 99 Robux |
| `PetFrostbiteRallyLuckyBlockRoll3` | 3 Frostbite Rally Event Lucky Block rolls | 279 Robux |
| `PetFrostbiteRallyLuckyBlockRoll5` | 5 Frostbite Rally Event Lucky Block rolls | 449 Robux |
| `PetLuck2x` | Permanently unlock 2x pet-roll luck | 79 Robux |
| `PetLuck4x` | Permanently upgrade pet-roll luck to 4x | 129 Robux |
| `PetLuck6x` | Permanently upgrade pet-roll luck to 6x | 229 Robux |
| `PetLuck8x` | Permanently upgrade pet-roll luck to 8x | 379 Robux |
| `PetLuck10x` | Permanently upgrade pet-roll luck to 10x | 499 Robux |
| `PetEquipSlotPlusThree` | Add 3 permanent equipped-pet slots, no purchase cap | 79 Robux |
| `PetBackpackSlotPlusFifteen` | Add 15 permanent backpack slots, no purchase cap | 49 Robux |

Tier 1–3 products were created off-sale. Prices use 19 / 39 / 59 Robux base prices, with 5% off 3x and 10% off 5x before rounding to the nearest price ending in 9. Roblox product IDs are recorded in `ProductCatalog`; enable sale in Creator Dashboard when ready.

The existing `2x`, `4x`, `8x`, `16x`, `32x`, `64x`, and `100x` developer products are XP-speed products. Do not reuse those keys for pet luck. Do not reuse the existing `Spin1`, `Spin3`, or `Spin5` keys; those belong to another spin system.

## Gamepasses: names and prices

Use these as internal gamepass catalog keys. Create separate Roblox gamepasses for each row. Store numeric Roblox `GamePassId` values separately.

| Gamepass key | Marketplace display name | Purpose | Price |
|---|---|---|---:|
| `PetLuckyBlockFasterOpen` | Faster Open | Skip Lucky Block falling and pet roulette animations | 99 Robux |

Only Faster Open remains a Lucky Block gamepass. 3x and 5x rolls no longer require passes. Paid Premium/Event rolls still require matching developer product purchases; Faster Open changes presentation only, not odds, prices, or rewards.

## Implementation status

Last audited: 2026-10-01. Source implementation updated; runtime behavior still needs Studio/device verification.

Move an item from **Still needed** to **Already in** only after implementation is present and its acceptance checks pass. Keep each task in one status list.

### Already in

- Pet roster/config for Tier 1–3, Premium, and event Lucky Blocks: model paths, rarity, base chance weights, base multipliers, and star-upgrade rules in `PetConfig`.
- Brainrot models under `ReplicatedStorage.BrainrotPets`; shared viewport renderer powers inventory cards, Lucky Block previews, and reveal clones. Model import is present; validate bounds/orientation across the full roster in runtime.
- Profile-persisted inventory, overflow claims, equipped state, backpack capacity, equip-slot capacity, and Luck tier. Starting capacity is 25 pets and 3 equipped slots; purchases add 15 backpack slots or 3 equip slots without a configured cap. Overflow auto-claims when space opens.
- Server-validated equip/unequip, single/bulk delete, merge, and Studio-only random-pet test actions. Merge requirements come from rarity config; equipped pets cannot be deleted or merged.
- Pet multiplier calculation and server XP integration. Equipped pets stack additively over 1x, then multiply gameplay XP; reward XP paths remain pet-free.
- Product callbacks for equip-slot, backpack-slot, and Luck upgrades. Luck upgrades accept only next configured tier; out-of-order receipts remain unprocessed for retry, duplicate/already-owned receipts are consumed without changing Luck.
- Inventory UI, pet multiplier display, Lucky Block previews, rarity/weight labels, roll-button visuals, keyboard E/R/T controls, touch/mouse input, and gamepad selection/navigation.
- Server-created proximity prompts, nearby-block validation, data-loaded and active-event checks, plus Lucky Block modal blur, movement lock, and GUI restoration.
- Roll buttons route to server-validated Wins and matching Lucky Block developer products. Server selects every pet and applies configured per-roll Win costs; client cannot provide pet IDs, rarity, odds, or multipliers.
- Win rolls grant pets only after storage capacity and Win balance checks. Paid receipt callbacks persist inventory/overflow with the generic processed-receipt marker before receipt acknowledgement; a post-save callback starts reveal. Event state/nearby checks happen before prompting, not after payment.
- Luck modifies rarity weights with a logarithmic soft curve shared by server rolls and client odds display. Pet preview cards show every outcome's current per-roll percentage to four decimals; largest-remainder rounding makes displayed odds total exactly 100.0000%.
- `PolicyService:GetPolicyInfoForPlayerAsync()` is cached per player. Unknown/failed lookups fail closed. Restricted users cannot interact with Lucky Block rolls or purchase Luck upgrades. This includes Win-priced Tier 1–3 rolls because `WinCount` is also sold for Robux. Server rechecks eligibility before every roll and before granting a Lucky Block receipt.
- Duplicate results consolidate into one reveal model with an `xN` label, while inventory receives one pet record per result.
- Faster Open purchase/ownership UI is wired. Owned pass lands block without meteor fall and skips roulette; impact and final reveal remain. Results and grants are unchanged.
- Overflow pet claims are persisted and automatically moved into inventory after deletion, merging, or capacity increase creates space.
- Pet multiplier aggregation affects XP gain only; rewards such as daily/group claims remain excluded.

### Still needed

1. **Verify equipped-pet world followers in Studio.** Client controller groups duplicate equipped pets by pet type, prioritizes rarity then highest stars then effective multiplier, fills up to nine visual slots by repeating equipped types in a 3x3 formation, shows pet name and rarity without duplicate-count suffixes, fits models proportionally within configurable 4x4x4-stud bounds, follows each character with idle motion, grounds model bounds with one cached raycast per player (0.5-second refresh, movement-triggered refresh capped at 4/sec), leaves configurable clearance behind tagged equipped karts, disables collision/query/shadows, and only creates nearby players' clones with hysteresis cleanup. Verify model orientation/grounding, kart clearance, scale, billboard readability, range culling, and performance on desktop and mobile/tablet before moving this item to Already in. No separate roster-model import task remains.

### Verification pending

- No pet-specific Luau spec runner/tests were found in `src`. In Studio, test receipt retries and data-save failures, event changes after product prompt, full storage/overflow auto-claim, disconnect/rejoin, insufficient Wins, every Lucky Block/count/payment kind, Luck odds/policy gating, Faster Open, duplicate multi-roll display, and interrupted/respawned cutscenes. Verify desktop, mobile/tablet, and gamepad behavior.

### Design decisions, not implementation tasks

- Tier 1–3 Win prices are **cost per roll**, deducted from current `WinCount`; they are not lifetime-Win unlock thresholds. Do not add lifetime-win unlock tracking unless this design changes.
- Duplicate/pity protection and duplicate conversion are not specified. Multi-roll consolidation is presentation only; each rolled copy still enters inventory.
- Pet trading, collection index, and pet abilities are not in current scope.
