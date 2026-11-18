# Project: Firing Range (FPS MVP)

A first-person shooter MVP: a military-style firing range for testing weapons and gunplay feel, inspired by the modern battle-royale firing ranges. Realistic ballistics and a smooth, responsive feel matter more than visuals.

## Hard constraints

- **Target machine:** Intel MacBook Pro, quad-core i5, 8 GB RAM, Intel Iris Plus integrated GPU, macOS Sequoia. Hold **60 fps at 1280x720**, and check this at every milestone.
- **Engine:** Godot 4.x (latest stable), **GDScript with static typing everywhere**.
- **Physics:** set `physics/3d/physics_engine = Jolt Physics`. Physics tick is 60 Hz; never write gameplay logic that depends on frame rate.
- **Renderer:** Mobile. Switch to Compatibility only if Mobile can't hold 60 fps, and record that switch in `docs/DECISIONS.md`.
- **Units:** 1 Godot unit = 1 meter. Use real-world SI values for velocities, masses and gravity (9.81 m/s²).
- **Original IP only:** no names, logos, UI art, sounds or assets from any existing game. Weapons get fictional names. Use greybox geometry, or CC0 assets (Kenney, Quaternius) with the source credited in `CREDITS.md`.
- **Everything stays text-based** (`.tscn`, `.tres`, `.gd`). No binary scene formats.
- Godot CLI path: `/Applications/Godot.app/Contents/MacOS/Godot` (alias as `godot`).

## Architecture rules

- Folders by feature: `player/`, `weapons/`, `ballistics/`, `targets/`, `range/`, `ui/`, `debug/`, `tests/`.
- **Weapon stats live in `Resource` files** (`weapons/data/*.tres`): fire rate, muzzle velocity, damage falloff, recoil pattern, spread, ADS time, magazine size, reload times. No magic numbers in weapon code.
- **Projectiles are simulated, not hitscan.** Every physics tick, integrate position with gravity and simple drag, then raycast from the previous position to the new one so bullets can't pass through thin objects. Pool projectile objects; don't spawn a node per bullet.
- Gameplay logic and feel effects (camera shake, viewmodel sway, hitmarkers) stay separate. Effects never change hit results.
- Systems talk through signals or a small event bus, not deep node paths.

## Testing and verification

- Use **GUT** for unit tests in `tests/`. Run headless: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
- Anything deterministic needs a test, including:
  - projectile trajectory (drop at 100/200/300 m within tolerance of analytic results)
  - damage falloff and hit-zone multipliers
  - armor-then-health damage order
  - recoil pattern indexing and recovery
  - fire-rate timing
- A milestone is done only when its tests pass, the game boots headless without errors, and the acceptance checklist below is met. Note which checks still need a human play-test.

- To check visuals, run a scene with Movie Maker mode and inspect the frames:
  godot --path . res://range/range.tscn --write-movie /tmp/frames/frame.png --quit-after 120
  Look at a few frames before telling me something looks right.

## Milestones (one at a time; stop for a play-test after each)

1. **Movement:** FPS controller with walk, sprint, crouch, jump and slide. Uses acceleration/friction for momentum (no instant velocity snapping), plus head bob and FOV/sensitivity settings. Greybox range: flat ground, a firing line, and lanes with distance markers at 25/50/100/200/300 m.
2. **Shooting core:** two weapons, an assault rifle (~850 m/s) and a bolt-action sniper (~900 m/s, scoped). Add hip fire and ADS (FOV zoom, sensitivity scaling, ADS transition time), reload with tactical and empty timings, weapon switching, a viewmodel with sway/bob/inertia, and muzzle flash and impact particles/decals.
3. **Ballistics and recoil:** projectile simulation with gravity and drag, damage falloff by distance, a per-weapon recoil pattern plus random deviation, recoil recovery and first-shot accuracy. Add a debug toggle that draws bullet paths.
4. **Targets:** humanoid dummies with head, torso and limb hit-zones and multipliers, health plus up to 3 armor plates, and pop-down on kill with auto-reset. Add moving targets on rails at varying speeds, and steel plates that ring and swing (physics hinge).
5. **Feedback and HUD:**
   - hitmarkers: white for a hit, blue for armor break, red X for a kill
   - floating damage numbers
   - crosshair that reacts to spread
   - ammo counter and FPS readout
   - range stats panel: shots, hits, accuracy, headshot %, time-to-kill on the last target
   - placeholder sound effects
6. **Polish:** physics props (barrels and crates that react to bullet impulses), ragdolls on dummy kill if they hold 60 fps, a pause/settings menu, and a performance pass.

## Working style

- Before writing code for a milestone, post a short plan and a list of the files you'll touch.
- Make small commits with clear messages, one per working step.
- Log non-obvious choices (renderer, drag model, tuning values) in `docs/DECISIONS.md`.
- If a feature costs too much performance on the target machine, say so and propose a cheaper version. Don't silently drop it.

## Future phases (not now, but don't block them)

- **Web export:** keep the Compatibility renderer and GDScript only; avoid threads, native plugins and file system access in gameplay code.
- **Controller support:** all input goes through InputMap actions, never hardcoded keys or mouse buttons. Look/aim code takes an input delta that a gamepad stick can feed later.

## Phase 2: Content and polish (post-MVP)

Phase 1 (Milestones 1–6) is complete and tagged `v0.1.0-mvp`. Phase 2 adds a full loadout of weapons, attachments, reload animations, a main menu and a polish pass. Everything from Phase 1 still applies: hard constraints, architecture rules, testing, working style and commit rules.

**No regressions:** every existing test must keep passing, and Phase 1 behaviour stays the same unless a milestone below says otherwise.

### Loadout model

- The player carries **one primary and one secondary**. Switch with 1/2 and the mouse wheel.
- **Primaries (5):** SMG, assault rifle (existing), sniper rifle (existing), LMG, pump shotgun.
- **Secondaries (4):** pistol, rocket launcher, tactical knife, riot shield.
- All weapons get original fictional names. No real or other-game weapon names.
- Each weapon is a `WeaponData` Resource. Weapons differ through **composition**, not one subclass per gun:
  - **Fire mode:** full-auto, semi-auto, bolt-action, pump-action.
  - **Delivery:** ballistic projectile, pellet spread, explosive projectile, melee.
  - **Reload type:** magazine, one shell at a time (interruptible), single round, none.

### Attachments

- **Slots:** muzzle, barrel, optic, stock, magazine.
- Each attachment is a Resource that declares:
  - which weapon classes accept it
  - its stat modifiers, each explicitly additive or multiplicative
  - a greybox viewmodel part with a mount point
- **Final stats** = base stats + modifiers, applied in a fixed, deterministic order. They are computed once on equip or loadout change, never per frame, and clamped to per-stat limits.
- **Optics** set the ADS zoom and the reticle: iron sights, red dot, 2×, 4×, and an 8× sniper scope.
- Start with 3–4 attachments per slot. Each must be a **trade-off**, not a strict upgrade. For example, a long barrel adds velocity and range but slows ADS.
- **Which weapons take attachments:**
  - Primaries: all five slots where it makes sense.
  - Pistol: muzzle, optic and magazine only.
  - Rocket launcher, knife and shield: none.

### Starting stats (tuning lives in the Resources, not here)

| Weapon | Fire mode | Muzzle velocity | Rate | Magazine | Notes |
|---|---|---|---|---|---|
| SMG | auto | ~400 m/s | ~900 rpm | 32 | Fast ADS, steep damage falloff past 25 m |
| LMG | auto | ~850 m/s | ~700 rpm | 100 | Slow ADS and sprint-to-fire, low recoil when ADS |
| Pump shotgun | pump | ~400 m/s | pump ~0.8 s | 6 | 8 pellets in a cone, each a real projectile; harsh falloff past 15 m |
| Pistol | semi | ~360 m/s | input-limited, max ~400 rpm | 15 | Fastest switch time |
| Rocket launcher | single | ~120 m/s, light gravity | — | 1 | Arms after 10 m; blast radius ~6 m with falloff; impulse on props, steel and ragdolls |
| Tactical knife | melee | — | ~0.5 s swing | — | ~1.8 m reach via a shape cast from the camera |
| Riot shield | melee | — | ~0.9 s bash | — | Frontal collider stops projectiles; 0.8× move speed while held; bash ~1.5 m |

### Damage sources and stats

- All damage goes through the existing target damage interface. Add a `source` field (`ballistic`, `pellet`, `splash`, `melee`) so the HUD and stats can tell them apart.
- **Splash damage** hits the torso zone, falls off with distance and still goes to armor first.
- **Stats rules:**
  - A shotgun shot counts as one shot, and as one hit if any pellet hits.
  - A melee swing counts as one shot.
  - A rocket counts as a hit if it damages any target.
- **Damage numbers:** pellets that hit the same target on the same shot add up to one number.

### Phase 2 milestones (one at a time; stop for a play-test after each)

7. **Weapon framework and attachments:**
   - Loadout slots, composition-based fire modes, deliveries and reload types, and the attachment system, all applied to the existing rifle and sniper.
   - The `source` field on damage.
   - Debug keys to cycle attachments until the Armory screen exists.
   - Tests: modifier order and clamping, compatibility rules, stat recomputation only on change, optic zoom.
8. **New primaries:**
   - SMG, LMG and pump shotgun, with attachments.
   - Pellet delivery, and pump/shell reloads that you can interrupt by firing.
   - Tests:
     - fire timing for each weapon
     - pellet count and spread
     - pellets adding up to one damage number
     - interrupting a shell reload
9. **Secondaries:**
   - Pistol with attachments.
   - Rocket launcher with explosive delivery: arming distance, splash falloff, physics impulse.
   - Melee delivery for the knife and riot shield, plus the shield's projectile-blocking collider.
   - Tests:
     - splash falloff and armor order
     - no explosion before the arming distance
     - melee reach and timing
     - the shield stopping projectiles
10. **Reload and handling animations:**
    - Procedural animation on the greybox viewmodels: magazine out, a physics magazine that drops and despawns, magazine in, and a bolt or charging-handle rack on empty reloads.
    - One shell at a time for the shotgun, rocket loading, and the LMG box and belt.
    - Equip and holster motions, and melee swing and bash motions.
    - Animation timings come from each weapon's reload and handling times, and stay purely cosmetic.
    - Tests: animation timelines match the Resource timings, and cancelling a reload resets the animation cleanly.
11. **Main menu and Armory:**
    - **Main menu:** Play, Armory, Settings (reuse the pause menu's settings), Quit.
    - **Armory:** pick a primary and a secondary, and an attachment for each slot, with a live stat comparison against the base weapon and a greybox weapon preview.
    - The loadout saves to `user://loadout.cfg`.
    - Fully usable with keyboard and controller.
    - Tests: loadout save/load round trip, invalid attachments rejected, stat comparison values.
12. **Polish pass:**
    - Angle-limited ragdoll joints (cone-twist or 6DOF) instead of pins.
    - Corpses that bullets can hit.
    - Adjustable sniper zero (100/200/300 m) with a key.
    - Muzzle smoke and ejected casings (pooled).
    - An option for the time-to-kill clock to start at the first shot.
    - A final performance pass with the full arsenal.

### Per-weapon checklist (each new weapon needs all of these)

- A Resource with all stats.
- Tests for fire timing, magazine and reload, and delivery behaviour.
- An entry in the README controls and weapons table.
- A row in the DECISIONS.md tuning reference.

## Future phases (not now, but don't block them)

- **Web export:** keep the Compatibility renderer and GDScript only. Avoid threads, native plugins and file system access outside `user://` in gameplay code.
- **Controller support:** all input goes through InputMap actions, never hardcoded keys or mouse buttons. Look and aim code takes an input delta that a gamepad stick can feed later.