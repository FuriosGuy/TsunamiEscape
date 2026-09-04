# Bloodmoon Rewards And Products

Planning reference for the Bloodmoon update. Runtime prices come from Roblox
Developer Product metadata.

## Complete Reward List

| Item | Unlock or price | Base value per step | Position or role | Ownership |
|---|---:|---:|---|---|
| `EclipseTrail` | 5 `BloodmoonWins` | 7x XP multiplier | Between Flame Trail (6x) and Demon Trail (7.5x) | Permanent free unlock |
| `CrimsonRunner` | 20 `BloodmoonWins` | 25,000 XP Speed | Between Dragon (15,000) and NeonRacing (30,000) | Permanent free unlock |
| `NightGlider` | 50 `BloodmoonWins` | 55,000 XP Speed | Above NeonDragon (50,000), below Formula Car (75,000) | Permanent free unlock |
| `Moonfang` | 100 `BloodmoonWins` | 80,000 XP Speed | Above Formula Car (75,000), below paid karts | Permanent free unlock |
| `CrimsonCell` | 299 Robux | 100,000 XP Speed | Entry premium Bloodmoon kart | Developer Product `3710412649` |
| `BloodDragon` | 499 Robux | 160,000 XP Speed | Slightly above Advanced Tank (150,000) | Developer Product `3710413009` |
| `SiegeTank` | 799 Robux | 225,000 XP Speed | Strongest Bloodmoon kart | Developer Product `3710413231` |

`Base value per step` is the kart's base movement XP award before normal
progression rules and any applicable gameplay multipliers. The three free
karts require Bloodmoon Wins; the three paid karts use permanent Bloodmoon
Developer Products. Maximum paid-kart price is 799 Robux.

Bloodmoon Wins start at zero for each new Bloodmoon event cycle. Unlocks and
owned items remain permanent after the player earns them.

## Free Rewards

### Eclipse Trail

- Unlock requirement: `5 BloodmoonWins`.
- XP multiplier: `7x`.
- Placement: between Flame Trail (`6x`) and Demon Trail (`7.5x`).
- Design: a dark eclipse effect with a red event glow, black-red gradient,
  and a compact silhouette that is visually distinct from Demon Trail.
- Ownership: permanent after unlock; it cannot be equipped early.
- Temporary progress image: the progress UI may reuse the Demon Trail image
  until a dedicated Eclipse Trail image is supplied.

### CrimsonRunner

- Unlock requirement: `20 BloodmoonWins`.
- Base movement reward: `25,000` XP Speed per step.
- Comparison: stronger than Dragon (`15,000`) and below NeonRacing
  (`30,000`).
- Design: a lightweight crimson racing kart with sharp eclipse-shaped body
  panels, bright red trim, a narrow nose, and a compact racing silhouette.
  It should look like the first accessible Bloodmoon kart rather than a tank.
- Role: first free Bloodmoon kart reward.

### NightGlider

- Unlock requirement: `50 BloodmoonWins`.
- Base movement reward: `55,000` XP Speed per step.
- Comparison: above NeonDragon (`50,000`) and below Formula Car
  (`75,000`).
- Design: a sleek black-and-red aerodynamic kart with moonlit blue-black
  surfaces, red underlighting, a low cockpit, and wing-like side panels that
  suggest gliding at high speed.
- Role: mid-progression free Bloodmoon reward.

### Moonfang

- Unlock requirement: `100 BloodmoonWins`.
- Base movement reward: `80,000` XP Speed per step.
- Comparison: above Formula Car (`75,000`) and below the planned paid karts.
- Design: the final free kart has a fang-shaped front, layered dark armor,
  red energy seams, swept rear panels, and an aggressive Bloodmoon silhouette.
  It should feel like a major event reward without replacing the paid tank.
- Role: final free Bloodmoon reward.

## Planned Paid Bloodmoon Kart Products

These are the exact paid-kart names and base movement values. Runtime prices
come from Roblox Developer Product metadata.

### Crimson Cell

- Developer Product: `3710412649`.
- Current price: `299 Robux`.
- Planned base movement reward: `100,000` XP Speed per step.
- Role: entry premium Bloodmoon kart.
- Design: a reinforced shopping-cart frame with a deep crimson basket, dark
  metal rails, glowing red eclipse seams, and bright red wheels. The basket
  should carry a compact Bloodmoon core, while red energy trails leak from
  the rear axle. It should feel like a playful but premium event conversion
  of the regular Shopping Kart without competing with the premium tank. Its
  enclosed shape should resemble a moving prison cell built for the Bloodmoon.

### Blood Dragon

- Developer Product: `3710413009`.
- Current price: `499 Robux`.
- Planned base movement reward: `160,000` XP Speed per step.
- Comparison: slightly above Advanced Tank (`150,000`).
- Role: premium Bloodmoon dragon kart.
- Design: an aggressive dragon-shaped kart with layered black-red scales,
  horn-like front armor, glowing crimson eyes, a segmented tail exhaust, and
  wing-shaped side panels. Red ember effects should pulse from its engine and
  eclipse markings should run along its body. Its silhouette should be
  clearly different from both Formula Car and Crimson Cell.

### Siege Tank

- Developer Product: `3710413231`.
- Current price: `799 Robux`.
- Planned base movement reward: `225,000` XP Speed per step.
- Role: strongest Bloodmoon kart.
- Design: a heavy siege tank with broad armored plating, a large Bloodmoon
  cannon, reinforced tracks or wheels, red emissive seams, dark steel panels,
  and a visible eclipse core. It should be the only Bloodmoon tank-style
  product and the strongest kart in this event lineup.

## Bloodmoon Win Reward

When a player reaches the valid final stage and touches the final WinButton:

- The normal WinButton win amount is awarded.
- The player receives `+1 BloodmoonWin`.
- The Bloodmoon win amount becomes `+2` with the 2x Wins gamepass.
- An active temporary 2x Win Boost also affects the Bloodmoon win.
- Treadmill, XP, rebirth, and unrelated XP multipliers do not affect the
  Bloodmoon-specific win.
- Teleporting to the end area alone cannot grant the reward.
- Newly reached permanent Bloodmoon unlocks become available immediately.

## Current Bloodmoon Config

| Setting | Current value |
|---|---:|
| Maximum Bloodmoon Wins | 100 |
| Normal movement/treadmill XP event multiplier | 1.5x |
| Walkspeed while active | 75% of normal |
| Active duration | 3 days |
| Later-cycle grace period | 2 days |
| Pre-event countdown | 24 hours |

## Implementation Status

- `EclipseTrail` is registered with a 5-win requirement and a 7x multiplier.
- The intended progression thresholds are 5, 20, 50, and 100 Bloodmoon Wins.
- The current `CoreConfig` source still contains `CrimsonRunner` at 25 wins;
  it must be changed to 20 when the gameplay catalog is synchronized with
  this plan.
- `CrimsonRunner`, `NightGlider`, and `Moonfang` still need their final kart
  assets and runtime catalog registration.
- The three paid names, prices, and XP values are now defined by this plan,
  but their Developer Product IDs and Roblox assets still need to be created.
- Temporary Flame Trail and Flame Kart images in the progress UI remain
  visual placeholders and are not the Bloodmoon reward catalog.
