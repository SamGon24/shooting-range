# Firing Range

A first-person shooter MVP set on a military-style firing range, built in Godot 4 for testing weapons and gunplay feel. The goal is realistic ballistics (simulated projectiles with gravity and drag, not hitscan) and smooth, responsive movement. Visuals are deliberately greybox.

## Status

**Milestone 13 implemented; awaiting a real-controller play-test.** See the controller mapping and numbered checklist below.

**MVP complete (Milestones 1 to 6), play-tested.**

**Phase 2 complete (Milestones 7–12) — all nine weapons, attachments, handling animations, main menu and saved-loadout Armory, and the final polish pass. Play-tested by the project owner (see DECISIONS, Play-test record).** The rifle and sniper keep their exact Milestone 6 stats and behavior with no attachments fitted; a frozen fixture verifies every original exported stat.

Movement and range (Milestone 1):

- FPS controller: walk, sprint, crouch, jump and slide, with acceleration and friction rather than instant velocity changes, plus coyote time and a jump buffer.
- Camera feel: head bob, landing dip, slide camera tilt, and an FOV kick when sprinting or sliding. FOV and mouse sensitivity are adjustable and saved between runs.
- Greybox range: firing line, 5 lanes, distance signs and ground stripes at 25/50/100/200/300 m, a backstop, and a movement test area behind the line (steps, a ramp, a crouch tunnel).

Shooting core (Milestone 2):

- Two weapons: the Halberd R-5 assault rifle (full-auto, 700 rpm, 850 m/s) and the Longwatch B-9 bolt-action sniper (900 m/s, scoped).
- Simulated projectiles, not hitscan: pooled, moved under gravity every physics tick, with a swept raycast so fast bullets can't pass through thin objects.
- Weapon handling: hip fire and aim down sights (FOV zoom, lower sensitivity, sniper scope overlay), tactical and empty reloads, bolt cycling, and weapon switching with raise and lower times. Sprinting blocks firing and aiming.
- Greybox viewmodels with sway, bob, inertia and recoil kick, a muzzle flash, impact sparks and marks, and placeholder sounds generated in code.
- Weapon name, ammo counter and scope overlay, extended by the Milestone 5 HUD below.
- Debug overlay (FPS, frame time, speed, movement state), a command-line perf probe, and a hit logger.

Ballistics and recoil (Milestone 3):

- Quadratic air drag from each bullet's mass, diameter and drag coefficient. The rifle round slows from 850 to about 600 m/s by 300 m and drops 78 cm there; the sniper round keeps about 720 m/s and drops 63 cm.
- Damage falloff by distance: the rifle does 32, falling to 70% by 200 m; the sniper does 110, falling to 80% by 400 m. Every hit reports its damage, ready for targets.
- Per-weapon recoil patterns plus random deviation, a little lighter while aimed. The kick moves the real aim. After a short pause the view recovers, and recoil you have already pulled down is not recovered a second time.
- Spread: a hip-fire cone plus bloom that builds per shot and settles after a pause. Both weapons have zero aimed spread, so the first aimed shot from a settled weapon follows its calibrated bore direction without spread. Both weapons are zeroed at 100 m.
- A debug view of bullet paths (F4): each bullet's simulated path, coloured from yellow to red as it slows, with a cross at the impact.

Targets (Milestone 4):

- Six solid humanoid hit zones: head, torso, two arms and two legs. Head damage is 1.5× (2× for the sniper), torso 1×, limbs 0.8×.
- 100 health and 0–3 armor plates of 50 each. Armor absorbs damage first, with overflow reaching health. A killed dummy becomes a six-part ragdoll with angle-limited joints; bullets stop on and push the corpse, but it takes no damage and never scores. It returns fully restored after 3 seconds.
- Stationary dummies at 25/50/100/200/300 m, staggered from left to right. Their armor counts are 0/1/2/3/0 respectively.
- Walk (1.5 m/s, left) and sprint (6 m/s, right) movers at both 50 and 100 m on 4 m rails. Movers are unarmored and keep travelling while down.
- Hinged steel at 100/200/300 m swings from bullet momentum and plays a generated placeholder ring.

Feedback and HUD (Milestone 5):

- White hitmarkers, blue markers when any armor plate breaks, and a red X on kills. Kill feedback takes priority over an armor break in the same hit.
- Floating damage numbers anchored at the hit point: white for body / limb hits and amber for headshots. Values include zone multipliers and overkill, rounded to the nearest whole point.
- A crosshair that projects the current spread cone, including bloom, through the active camera FOV. It hides when ADS passes halfway; hitmarkers remain visible while aiming and scoped.
- A toggleable gameplay FPS readout and an ammo counter. F3 still controls only the separate diagnostic overlay.
- A range stats panel with shots, target hits, accuracy, headshot percentage and time to kill on the last killed dummy. **T** resets stats and clears hitmarkers and damage numbers.
- Distinct original placeholder hit, armor-break and kill confirmation chirps, synthesized before play and credited in `CREDITS.md`.

Polish (Milestone 6):

- Eight bounded rigid props: crates and barrels near the line and movement test area. Bullets apply their momentum; walking into props pushes them. Escaped props return to their original positions.
- Esc pause/settings menu with Resume, mouse sensitivity, ADS sensitivity multiplier, vertical FOV, head bob / FOV-kick scales, master / effects volume and a gameplay FPS toggle. Settings save on resume to `user://settings.cfg` through ViewSettings.
- Keyboard and controller menu navigation with initial focus, directional / Tab cycling, sliders and an accessible Resume button. Game simulation, target resets, stats timers and in-game audio stop while paused.
- Six-part pooled ragdolls on all nine dummies, using killing-shot momentum and rail velocity. Their original hit zones return after 3 seconds of gameplay time.
- Worst-case stress probe: all 54 ragdoll parts awake, eight moving props, three moving steel plates, firing and HUD. Verified at 60.0 fps on the target machine; details and before/after numbers are in `docs/DECISIONS.md`.

Weapon framework and attachments (Milestone 7):

- Composed fire-mode, delivery and reload Resources, named loadout slots, independent cached stat builds and explicit damage-source metadata. Ballistic delivery still uses the original projectile system and target interface.
- Seventeen trade-off attachments: three each for muzzle, barrel, stock and magazine, plus all five optic types. Parts mount on the existing greybox viewmodels; optics change zoom, reticle and authored sight height, and recalibrate the numerical zero.
- F5–F9 cycle attachments on the equipped weapon; F10 restores its native setup. F3 shows the current choices. Changes wait for reload / handling / cooldown boundaries, preserve ammo and recoil, and never modify already-flying rounds.
- The range now uses a strict primary / secondary loadout, initially Halberd / Wayline. All five primaries and four secondaries are available through the debug selectors. Range debug changes are session-only; the Armory saves the startup loadout.

New primaries (Milestone 8):

- Rill S-4 SMG: 900 rpm, 32 rounds, fast handling and steep falloff beyond 25 m.
- Foundry L-8 LMG: 700 rpm, 100 rounds, slow ADS / sprint recovery and reduced aimed recoil.
- Breakwater P-6 pump shotgun: six shells, 0.8 s pump cycle, eight simulated pellets per shell, with harsh falloff beyond 15 m.
- Interruptible shell reloads credit each completed insert. Fire closes the loading action before shooting; an empty gun waits for its first complete shell. Switching preserves inserted shells.
- Shotgun accuracy counts one shot and at most one hit per shell. Pellets striking the same target update one summed damage number, even across physics ticks.
- P exchanges the primary while preserving each gun's ammo and attachments. Longwatch is now selected through P; slot 2 carries a secondary.

Secondaries (Milestone 9):

- Wayline P-15 pistol: semi-auto, 360 m/s, 400 rpm maximum, 15 rounds and the fastest switch times. Muzzle, optic and magazine attachments fit; barrel and stock do not.
- Cairn R-1 launcher: one 120 m/s rocket, light gravity and numerical 50 m zero. Contact before 10 m is a dud; armed contact produces a 6 m blast with torso damage, armor-first absorption, cover occlusion and radial impulses on props, steel and ragdolls. Flight bodies, flashes and boom voices are pooled.
- Latch K-1 knife: one camera sphere cast per click, 1.8 m reach and 0.5 s swing interval. Palisade S-1 shield: 1.5 m bash, 0.9 s interval, frontal projectile-blocking collider and 0.8× movement speed while held. Both have unlimited attacks, no reload and no ADS.
- O exchanges the secondary. B sends a harmless, non-scoring incoming test round while the shield is ready. Damage feedback and logical-shot stats use the existing shared pipeline; one swing counts as one shot and one rocket can score at most one hit.

Handling animations (Milestone 10):

- Procedural motion on the greybox viewmodels for all nine weapons, purely cosmetic. Timings are fractions of each weapon's own Resource times and are read from the weapon logic every frame, so attachments that change reload or handling times change the animation by the same factor, and pause, cancel and interrupt need no extra handling.
- Rifle, SMG, pistol and sniper: the gun rolls to show the magazine well, the magazine pulls out and drops as a pooled physics copy, and a new one goes in. Empty reloads add a rack: charging handle (rifle, SMG, LMG), bolt (sniper) or slide release (pistol). The pistol slide cycles per shot and locks back when empty.
- LMG: cover up, box out, box in, belt laid, cover down; the belt is hidden while the gun is empty. Shotgun: one visible shell goes into the port per insert, and the forend pumps after every shot. Rocket: the fired round disappears and a new one slides into the muzzle. Sniper: the bolt lifts, pulls, pushes and locks after each shot.
- Equip and holster roll each model in and out over its raise / lower time. The knife slashes across the view and the shield pushes forward over their melee cooldowns.
- Dropped magazines come from a fixed pool of six bodies, inherit the player's velocity, settle on the ground and disappear after 4 s. They are on a debris layer that projectiles, melee, blasts, the player and ragdolls ignore.

Main menu and Armory (Milestone 11):

- Startup opens Play, Armory, Settings and Quit. Settings uses the same live controls as the pause menu; the pause menu now also offers Return to Main Menu.
- Armory chooses one primary and one secondary, with compatible attachments for each slot and a native option. Choices stay with each weapon while editing. Save & Back writes `user://loadout.cfg`; Cancel or B / Esc discards the draft.
- Numeric base / fitted / change columns show actual computed stats with units. Shotgun insert and full-reload times, rocket blast values and melee reach / timing use their delivery-specific values. Optic magnification uses the fixed 65° reference.
- A single greybox weapon preview includes fitted parts, rotation buttons and Show handling (empty reload or melee). It uses isolated weapon logic and the existing animation profiles, without firing gameplay projectiles or changing the loadout's ammo.
- Keyboard and controller focus navigation covers selection popups, preview controls, stat scrolling, settings and saving / cancellation. Simulated controller events pass automated tests; a physical-controller play-test is still pending.

Polish (Milestone 12):

- Ragdoll joints are cone-twist joints with per-joint swing and twist limits (neck 40° / 50°, shoulders 85° / 45°, hips 55° / 30°) instead of free pins, so limbs no longer fold through the torso. Jolt enforces them softly: hard hits overshoot by about 12°.
- Corpses are solid to bullets. A round stops on a part and shoves it with its momentum at the point of impact. A corpse hit is still a miss in the range statistics, like a shot through a down dummy, and parked parts after the 3 s reset are off every layer again. Melee (the knife and the shield bash) does not hit corpses.
- The Longwatch sniper's zero can be set to 100, 200 or 300 m with **Z**. The choice is per weapon, survives switching and attachment changes, is recalculated once per change and only affects rounds fired afterwards. A label above the weapon name shows it for adjustable weapons only. It is not saved to the loadout file.
- A new setting, **Time to kill starts at the first shot** (off by default), starts a dummy's clock when the shot that first damaged it was fired instead of when it landed. Flight time then counts, so a one-shot kill at range reads its flight time instead of 0.000 s.
- Muzzle smoke and ejected casings, both pooled and cosmetic. Self-loaders throw their casing on the shot; the sniper and shotgun throw it as the bolt or pump opens. The rocket launcher smokes and ejects nothing; melee does neither. Casings last 2 s and are invisible to projectiles, melee and blasts.
- Particle effects are warmed before the first shot (see DECISIONS): the first shot of a session no longer freezes the game for about half a second on the target GPU. A smaller first-hit stall remains and is documented as a known issue.

Later Phase 2 work is listed under [Roadmap](#roadmap) and [Future phases and known limitations](#future-phases-and-known-limitations).

## Requirements

- **Godot 4.7.2 stable**, the standard build (not .NET). Everything is GDScript.
- **Tested on:** MacBook Pro, Intel i5-8259U, 8 GB RAM, Intel Iris Plus Graphics 655, macOS Sequoia. The target is 60 fps at 1280x720 on this machine.
- **Renderer: Compatibility (OpenGL).** On the target Intel GPU, the Mobile renderer logs shader errors and can't draw a sky or stable sun shadows.

Physics uses Jolt, which is built into Godot 4.4 and later, so nothing extra needs installing.

## Quick start

The commands below assume `godot` points to the Godot binary. On macOS:

```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot
```

Clone the repo. The Godot project lives in the `firing-range/` subfolder:

```sh
git clone https://github.com/SamGon24/shooting-range.git
cd shooting-range/firing-range
```

Import once after cloning. This builds the `.godot/` cache, which isn't committed:

```sh
godot --headless --import
```

Run the game:

```sh
godot
```

You can also open `project.godot` in the editor and press F5.

## Controls

| Action | Key |
|---|---|
| Move | W A S D |
| Look | Mouse |
| Sprint | Shift (hold; forward only) |
| Crouch | Ctrl or C (hold) |
| Slide | Crouch while sprinting |
| Jump | Space |
| Fire | Left mouse button |
| Aim down sights | Right mouse button (hold) |
| Reload | R |
| Switch weapon | 1 / 2, or mouse wheel |
| Cycle the sniper's sight zero: 100 → 200 → 300 m | Z |
| Cycle primary: rifle → SMG → LMG → shotgun → sniper | P |
| Cycle secondary: pistol → rocket → knife → shield | O |
| Incoming shield test round (shield ready only; non-scoring) | B |
| FOV down / up | `[` / `]` |
| Mouse sensitivity down / up | `-` / `=` |
| Toggle debug overlay | F3 or `\` |
| Toggle bullet paths | F4 |
| Cycle muzzle / barrel / optic / stock / magazine | F5 / F6 / F7 / F8 / F9 |
| Clear all attachments on the equipped weapon | F10 |
| Reset range stats, hitmarkers and damage numbers | T |
| Pause / resume; release / restore mouse | Esc or controller Start |
| Navigate menus and Armory | Up/Down, Tab/Shift+Tab; controller D-pad or left stick |
| Adjust focused slider | Left/Right; controller D-pad or left stick |
| Activate focused menu control | Enter / Space; controller A |
| Close settings / resume; cancel Armory draft | Esc, controller Start or B; Resume in the pause menu |
| Open a weapon / attachment picker | Enter / Space or controller A; Up/Down to choose, A to confirm |
| Scroll the focused Armory stat panel | Left/Right or controller D-pad / left stick |

## Settings and pause

On Mac keyboards, use **Fn + F5–F10** if macOS consumes the function keys. In the Godot editor, F5 also runs the project: attachment keys act inside the focused game window. Toggle F3 to see the selection list; each attachment cycle includes **None (native)**.

Open the menu with **Esc**. Resume receives focus immediately. Use arrows or Tab to select controls, Left/Right to change a slider, and Enter/Space to activate a control. Controller Start opens the menu, D-pad / left stick navigates and adjusts, A activates and B resumes. Menu navigation needs no mouse. Controller gameplay is implemented in Milestone 13; physical-controller validation is pending.

| Setting | Default | Range / meaning |
|---|---|---|
| Mouse sensitivity | 0.10 degrees/count | 0.01–1.00 |
| ADS sensitivity multiplier | 1.00 | 0.10–2.00, multiplied by the equipped weapon's ADS sensitivity |
| Vertical FOV | 65° | 50–100° |
| Head bob scale | 1.00 | 0–2; 0 disables bob and landing dip |
| FOV kick scale | 1.00 | 0–2; 0 disables sprint / slide FOV kick |
| Master / effects volume | 1.00 / 1.00 | 0–1 linear gain; 0 mutes |
| Show gameplay FPS | On | Independent of F3 diagnostics |
| Time to kill starts at the first shot | Off | Off: clock starts at the first damaging hit. On: at the launch of the shot that first damaged the dummy |

Changes apply live and save when you resume, or choose Save & Back in main-menu Settings. Esc / B in those Settings also saves and returns. Previous view settings, including invert-Y, remain supported in the same config file. Pause freezes simulation, projectile travel, weapon/reload timing, target resets, ragdolls, props and range-stat timestamps. Menu wall time is excluded from TTK. The cursor returns to its prior capture mode on resume; menu activation cannot become a buffered shot or jump.

## Weapons and selection

Press **P** to cycle Halberd → Rill → Foundry → Breakwater → Longwatch → Halberd. Press **O** to cycle Wayline → Cairn → Latch → Palisade → Wayline. **1** equips the selected primary and **2** equips the selected secondary; the wheel switches those two carried slots. Startup uses the saved Armory loadout, falling back to Halberd / Wayline. Longwatch is a primary, available in Armory or through P.

Changes use normal lower / raise timing and equip the requested selection. Ammo and attachment choices stay with each weapon for the session; exchanging a weapon never refills it. The current / requested choices appear in the F3 list. P / O and F5–F10 remain session-only debug controls. They never write the Armory file. Returning to the menu and pressing Play starts a fresh range with the saved selection, full magazines and reset targets / stats.

Bare weapon values, before attachments:

| Weapon | Fire / cycle | Velocity | Capacity | Damage | Falloff start → end; minimum | ADS |
|---|---|---:|---:|---:|---|---:|
| Halberd R-5 rifle | Auto, 700 rpm | 850 m/s | 30 | 32 | 50 → 200 m; 70% | 0.25 s |
| Longwatch B-9 sniper | Bolt, 1.1 s | 900 m/s | 5 | 110 | 150 → 400 m; 80% | 0.40 s |
| Rill S-4 SMG | Auto, 900 rpm | 400 m/s | 32 | 24 | 25 → 75 m; 35% | 0.18 s |
| Foundry L-8 LMG | Auto, 700 rpm | 850 m/s | 100 | 30 | 60 → 250 m; 75% | 0.48 s |
| Breakwater P-6 shotgun | Pump, 0.8 s; click per shell | 400 m/s | 6 | 18 × 8 pellets | 15 → 40 m; 20% | 0.30 s |
| Wayline P-15 pistol | Semi, max 400 rpm | 360 m/s | 15 | 28 | 20 → 75 m; 40% | 0.16 s |
| Cairn R-1 rocket | Single, max 60 rpm | 120 m/s | 1 | 180 splash | Full ≤1 m; linear to zero at 6 m | 0.42 s |
| Latch K-1 knife | Click, 0.5 s | — | Unlimited | 75 before zone multiplier | 1.8 m reach | None |
| Palisade S-1 shield | Click, 0.9 s | — | Unlimited | 40 before zone multiplier | 1.5 m reach | None |

Rill / Foundry magazine reloads take 1.5 / 4.2 s tactically and 2.0 / 5.0 s empty. Breakwater opens for 0.20 s, inserts its first shell in 0.55 s (0.85 s when empty), inserts each later shell in 0.55 s, then closes for 0.20 s. A full empty reload takes **4.0 s**. Press fire during loading to close and shoot a loaded shell; an unfinished insert gives no ammo. A press while empty loading is remembered until a shell is inserted and the action closes. Hold does not repeat pump shots.

Shotgun pellets spread in an intrinsic 3° half-angle cone around the weapon's aimed/spread direction; ADS does not remove this pellet cone. The hip crosshair includes that cone plus current weapon spread / bloom. The central shotgun trajectory is zeroed at 25 m; SMG / LMG are zeroed at 100 m, with ordinary spread still applied. No weapon has limited reserve ammo on the range.

Wayline reloads in 1.25 s tactically / 1.65 s empty; Cairn loads its single round in 2.8 s after firing. Both are zeroed at 50 m. Knife and shield attacks require a fresh click after the cooldown; holding does not repeat them. Their reach includes the cast sphere's radius, with walls and nearer bodies blocking a strike. Head / torso / limb multipliers still apply. A knife head hit does 112.5 damage to an unarmored target.

Rocket splash applies once per dummy to its torso, including armor carry-over. The maximum 180 damage / 45 N·s impulse hold through 1 m, then decrease linearly to zero at 6 m. Cover blocks damage and impulse. There is no separate contact damage, pre-arm explosion or expiry airburst. A direct armed hit kills an unarmored dummy; three armor plates plus health can survive it. The shield blocks direct projectiles from its front; exposed sides remain vulnerable. B is a test aid in this enemy-free range, not a scored player shot. Swing, bash and reload animations are described under Milestone 10 above.

## Development

### Tests

Unit and integration tests use [GUT](https://github.com/bitwes/Gut), which is vendored in `addons/gut/`. Run them all headless from `firing-range/`:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The run takes about three minutes, because the player and weapon tests step real physics ticks. The exit code is non-zero if any test fails.

### Perf probe

The perf probe sprints the player downrange while sweeping the view, measures 10 seconds of frames, prints average fps, 1% low and the worst frame, then quits. Keep the window in front while it runs; macOS paces background windows differently.

```sh
godot -- --perf-probe                              # as played, capped at 60 fps
godot --disable-vsync --max-fps 0 -- --perf-probe  # uncapped, to see headroom
godot -- --perf-probe --perf-fire                  # walking and firing full-auto
godot --always-on-top -- --perf-probe --perf-fire --perf-stress
# Stress comparison without ragdolls:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-popdown
# Uncapped worst-case headroom:
godot --always-on-top --disable-vsync --max-fps 0 -- --perf-probe --perf-fire --perf-stress
# Worst case with all five attachment slots fitted (one cycle per slot):
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --hold=attachment_muzzle@0.1-0.2,attachment_barrel@0.1-0.2,attachment_optic@0.1-0.2,attachment_stock@0.1-0.2,attachment_magazine@0.1-0.2
# Select any primary: rifle, smg, lmg, shotgun or sniper:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-weapon=shotgun
# Fully fitted new primary; wait until its normal equip has completed:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-weapon=lmg --hold=attachment_muzzle@1.5-1.6,attachment_barrel@1.5-1.6,attachment_optic@1.5-1.6,attachment_stock@1.5-1.6,attachment_magazine@1.5-1.6
# Select any secondary: pistol, rocket, knife or shield:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-weapon=rocket
# Reload stress: tactical reload after every shot, with magazine drops:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-reload --perf-weapon=smg
# Cold start: firing waits until the warm-up ends, so first-use stalls are measured:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-cold --perf-weapon=smg
# The same without the particle warm-up, to see what it removes:
godot --always-on-top -- --perf-probe --perf-fire --perf-stress --perf-cold --no-warmup
```

The stress fixture is opt-in: it repeatedly kills all dummies through their normal damage entry point on reset, keeps all ragdoll parts and props awake and drives steel hinges. Those fixture kills do not count as launched shots. The report verifies 54 awake parts throughout the measurement. Do not open the pause menu while benchmarking.

The report also names the selected gun and lists peak live projectiles / dropped projectiles, armed blasts, non-scoring shield blocks, reloads started, magazines released and the peak number of active dropped magazines. Shield stress sends a real incoming round from 2 m every 0.25 s while bashing, so it exercises blocking while walking and turning. Its printed collision-hit count includes scenery and individual pellets; HUD accuracy counts logical target hits once per shot. Semi-auto, bolt, pump and melee probes generate repeated clicks; the shotgun probe interrupts shell loading after a shell is ready.

The cap comes from `application/run/max_fps=60` in `project.godot`, because OpenGL on macOS doesn't enforce vsync.

### Debug arguments

These go after `--` on the command line and are mainly for Movie Maker captures and automated checks.

| Argument | Effect |
|---|---|
| `--pose=x,y,z,yaw,pitch` | Places the player (metres and degrees; yaw 0 looks downrange) |
| `--hold=action[@seconds[-release]],...` | Presses input actions from the given time and keeps them down until the optional release time. A held action is pressed again if the engine releases it (an unfocused window loses its held keys), so give one-off keys such as attachment cycling a release time |
| `--log-hits` | Prints every projectile hit: what it hit, where, flight time and speed |
| `--hide-overlay` | Starts with the debug overlay hidden |
| `--no-warmup` | Skips the particle first-draw warm-up, to measure what it removes |
| `--bullet-paths` | Starts with the bullet path view on |

For example, switch to the pistol, aim at the unarmored 25 m dummy, fire, and log the hit:

```sh
godot --quit-after 200 -- --pose=-13.2,0,0,0,-0.8 --hold=weapon_2,aim@1.2,fire@1.8 --log-hits
```

For Movie Maker captures, add `--always-on-top`. macOS throttles a Godot window that isn't in front, and Movie Maker then writes the same frame over and over.

### Tuning values

| What | Where |
|---|---|
| Movement: speeds, acceleration, friction, jump, slide, crouch, capsule size | `player/data/movement_default.tres` (fields documented in `player/movement_settings.gd`) |
| Camera feel: head bob, landing dip, slide tilt, FOV kick | Exported properties on the `CameraFeel` node in `player/player.tscn` |
| Settings: FOV, sensitivity, ADS multiplier, invert Y, bob / FOV-kick scales, volume and FPS | Defaults in `player/view_settings.gd`; the player's changes are saved to `user://settings.cfg` |
| Weapon stats: sight zero distance and height, fire rate, magazine, reload times, recoil pattern and recovery, spread and bloom, ADS time, FOV and sensitivity, bolt cycle, raise and lower times, viewmodel poses and kick | `weapons/data/halberd_rifle.tres` and `weapons/data/longwatch_sniper.tres` (fields documented in `weapons/weapon_data.gd`) |
| New primary stats, including sprint-to-fire recovery | `weapons/data/rill_smg.tres`, `foundry_lmg.tres`, `breakwater_shotgun.tres`; complete new tuning table in DECISIONS |
| Pellet count / intrinsic cone; shell opening / closing times; pump policy | `weapons/framework/pellet.tres`, `shell.tres`, `pump.tres` |
| Secondary stats, native sight geometry, damage, movement scale and handling | `weapons/data/wayline_pistol.tres`, `cairn_launcher.tres`, `latch_knife.tres`, `palisade_shield.tres`; complete tables in DECISIONS |
| Blast arming, radius, falloff, impulse and occlusion | `blast` sub-resource in `weapons/data/cairn_launcher.tres`; schema `ballistics/explosion_data.gd`; query cap in `ballistics/explosion_system.gd` |
| Melee reach, radius, impulse and query limit | `weapons/framework/knife_contact.tres`, `bash.tres`; schema `ballistics/contact_data.gd` |
| Shield collider dimensions, eye offset and layer | `weapons/data/palisade_guard.tres`; schema `weapons/guard_data.gd` |
| Secondary offerings / order; shield test round | `weapons/data/secondary_catalog.tres`; O / B in `project.godot`; `debug/guard_probe.gd`, `debug/data/guard_probe_round.tres` |
| Rocket body, pooled blast flashes and spatial boom | Exports in `weapons/effects/explosion_effects.gd`; original sound synthesis in `weapons/effects/sfx_factory.gd` |
| Primary offerings / order | `weapons/data/primary_catalog.tres`; `primary_next` (P) in `project.godot` |
| Handling animation tracks (reload, cycle, equip / holster, melee, staged parts) | `weapons/animation/data/*.tres`, picked by each weapon's `handling`; schema `weapons/animation/handling_track.gd` / `handling_profile.gd`; complete tables in DECISIONS |
| Dropped magazine pool: capacity, lifetime, mass, release speed / spin, layers | Exports in `weapons/effects/magazine_drop_pool.gd` |
| Bullet stats: muzzle velocity, damage and falloff, mass, diameter, drag coefficient | The `projectile` sub-resource inside each weapon `.tres` (fields documented in `ballistics/projectile_spec.gd`) |
| Attachment modifiers, compatible classes, optic FOV and sight height | `weapons/attachments/data/*.tres`; catalog and exact values below |
| Modifier limits | `weapons/attachments/data/stat_limits.tres`; complete bounds in `docs/DECISIONS.md` |
| Fire / delivery / reload policies and loadout slots | `weapons/framework/*.tres` and `weapons/data/range_loadout.tres` |
| Attachment geometry / materials and weapon mount transforms | `weapons/attachments/parts/*.tscn` and `weapons/viewmodels/*.tscn`; fixed bore heights in each weapon Resource |
| Attachment key bindings, selection label and optic reticles | `project.godot`, `debug/attachment_debug.gd` and `ui/scope_overlay.gdshader` |
| Dummy health, plate strength, default armor, zone multipliers, pop-down and reset times | `targets/data/dummy_default.tres` (`targets/target_settings.gd`) |
| Physics props: cap and placement | `prop_count` and `_build_props()` in `range/range_builder.gd` |
| Prop mass, dimensions, player push force, recycling distance and damping | `props/physics_prop.gd` |
| Ragdoll switch, masses, damping, joints, impulse scale | `targets/target_dummy.gd` and `targets/dummy_ragdoll.gd` |
| Ragdoll joint swing / twist limits (per joint) | `swing_limit_degrees` / `twist_limit_degrees` exports in `targets/dummy_ragdoll.gd` |
| Sniper zero options and default | `zero_options` and `zero_distance_m` in `weapons/data/longwatch_sniper.tres`; `zero_cycle` (Z) in `project.godot` |
| Muzzle smoke per weapon; casing size, port, colour and eject delay | `muzzle_smoke_particles`, `casing_*` in each `weapons/data/*.tres`; schema in `weapons/weapon_data.gd` |
| Smoke emitter count, lifetime, drift, size; casing pool capacity, lifetime, ejection speed | Exports in `weapons/effects/muzzle_smoke.gd` and `weapons/effects/casing_pool.gd` |
| Pause menu layout, slider increments, focus and input mappings | `ui/pause_menu.gd` and `project.godot` |
| Audio routing and volume bounds | `default_bus_layout.tres` and `player/view_settings.gd` |
| Worst-case fixture and benchmark parameters | `debug/range_stress.gd` and `debug/perf_probe.gd` |
| Target layout, armor by distance, rail length and speeds | Target exports and `_build_targets()` in `range/range_builder.gd` |
| Steel size, mass, impulse scale, hinge limits and ring volume / attenuation | Exported properties in `targets/steel_plate.gd` |
| Projectile weapon class (sniper head multiplier) | `weapon_class` in the weapon's projectile sub-resource |
| Air density | Exported on the `Projectiles` node in `range/range.tscn` |
| Bullet path view: paths kept, colours, impact cross size | Exported properties on the `BulletPaths` node in `range/range.tscn` |
| Viewmodel motion: sway, bob, inertia, kick spring, sprint and reload poses, muzzle flash | Exported properties on the `WeaponView` node in `player/player.tscn` |
| Impact effects: mark size and count, sparks, impact volume | Exported properties on the `ImpactEffects` node in `range/range.tscn` |
| HUD: ADS hide threshold, FPS and stats refresh intervals | Root exports in `ui/hud.gd` / `ui/hud.tscn` |
| Crosshair: base gap, line / dot size, colors; spread source | Exports in `ui/crosshair.gd`; weapon spread / bloom in `weapons/data/*.tres` |
| Hitmarkers: timing, geometry, colors; damage numbers: pool, lifetime, rise, font and colors | Exports in `ui/feedback_view.gd` (the `FeedbackView` child in `ui/hud.tscn`) |
| Confirmation audio: volumes, pitches, durations, polyphony | Exports in `ui/feedback_audio.gd` (the `FeedbackAudio` child in `ui/hud.tscn`); synthesis in `weapons/effects/sfx_factory.gd` |
| HUD layout, fonts, panel background and margins | `ui/hud.tscn` |
| Stats reset binding | `range_stats_reset` in `project.godot` (T) |
| Weapon sound volumes | Exported properties on the `Weapons/Audio` node in `player/player.tscn` |
| Range layout: lanes, marker distances, sign sizes, colours | Exported properties on the root node of `range/range.tscn` (`range/range_builder.gd`) |

### Project structure

```
firing-range/
├── addons/gut/       GUT test framework (vendored, third-party)
├── ballistics/       Projectile spec, integration math and the pooled projectile system
├── debug/            Debug overlay, perf probe, pose and hold helper, hit logger, bullet paths
├── docs/             DECISIONS.md: design and tuning decisions with evidence
├── player/           FPS controller, movement math, camera feel, view settings
│   └── data/         Movement tuning resource (.tres)
├── props/            Bounded pushable crates and barrels
├── range/            Greybox range builder, grid shader and directly runnable range scene
├── targets/          Dummy health, hit zones, rail carriers, hinged steel and tuning
├── tests/            GUT tests
├── ui/               Main menu, Armory / preview, shared settings, HUD and pooled feedback
└── weapons/          Weapon stats, state machine, recoil and spread, controller and viewmodel
    ├── data/         One stat resource per weapon (.tres)
    ├── effects/      Impact effects, generated sounds, weapon audio
    ├── framework/    Composed policies, loadout persistence and cached stat builds
    ├── attachments/  Modifier schemas, catalog, tuning Resources and mounted parts
    └── viewmodels/   Greybox first-person weapon models
```

The main scene is `ui/main_menu.tscn`. `range/range.tscn` remains directly runnable with the authored Halberd / Wayline defaults, independent of saved loadouts. Every scene and resource is text-based (`.tscn`, `.tres`, `.gd`).

## Architecture in brief

- **Fixed 60 Hz physics.** All gameplay runs in `_physics_process` at 60 ticks per second and never depends on frame rate. Physics interpolation smooths rendering between ticks.
- **Pure movement math.** `player/movement_math.gd` holds static, node-free functions for friction, acceleration, slide decay and jump velocity. They're deterministic and unit-tested headless, and `player_controller.gd` calls them.
- **Simulated, pooled projectiles.** `ballistics/projectile_system.gd` keeps every bullet as a row in packed arrays, not a node. Each tick it integrates gravity and drag (one RK4 step, in `ballistics/projectile_math.gd`), raycasts from the old position to the new one, then emits `projectile_hit` with the damage after falloff.
- **Node-free weapon logic.** `weapons/weapon_logic.gd` is a state machine that takes a `WeaponInput` and a time step, so fire rate, reloads and aim timing are tested to the tick. `weapons/recoil_logic.gd` does the same for recoil pattern, recovery and spread. `weapon_controller.gd` feeds both from the input map and applies the kick to the player's recoil offset.
- **Feel never feeds back into gameplay.** `CameraFeel` and `WeaponView` only read gameplay state. Bullets leave a fixed sight height below `PlayerController.get_eye_position()`, along `get_aim_basis()` plus the equipped weapon’s numerical zero angle and spread, which ignore head bob, viewmodel kick and every other effect.
- **Data-driven tuning.** Numbers live in `Resource` files and exported properties, not in code. Each weapon is one `.tres` in `weapons/data/`.
- **Composed weapon builds.** `WeaponData` references `FireModeData`, `DeliveryData` and `ReloadData`. `WeaponBuild` copies base stats and the projectile spec; attachments add first, then multiply, in muzzle → barrel → optic → stock → magazine order. Results clamp once, magazine size rounds once and falloff end cannot precede start. Unchanged builds return the same cached snapshot. All four deliveries and reload types are implemented. Rockets use the same integrated projectile sweep; contact-triggered explosions deduplicate torso damage and apply radial impulses. Melee uses one reused camera ShapeCast and the shared hit / logical-shot signals. Shield geometry follows fixed-tick aim independently of its cosmetic model.
- **One trigger event across multiple projectiles.** Every launch has a unique logical shot ID; volleys share it while each pellet keeps its own pool slot and sweep. Stats deduplicate per shot, timers remain per target, and keyed damage labels accumulate per shot / target. Group metadata releases after the last impact or expiry.
- **Saved selections are separate from runtime state.** Armory edits independent `LoadoutConfig` / `WeaponBuild` snapshots. Only catalog weapon references and attachment IDs are persisted; stats are recomputed from authored Resources, and the controller copies prepared builds before play.
- **Signals over node paths.** The player, weapon controller and projectile system emit signals (`landed`, `shot_fired`, `projectile_hit` and so on), and effects, audio and the HUD listen to them.

## Roadmap

- [x] **1. Movement:** FPS controller (walk, sprint, crouch, jump, slide), head bob, FOV and sensitivity settings, greybox range with distance markers.
- [x] **2. Shooting core:** assault rifle and scoped bolt-action sniper, hip fire and ADS, reloads, weapon switching, viewmodel sway and bob, muzzle flash and impact effects.
- [x] **3. Ballistics and recoil:** simulated projectiles with gravity and drag, damage falloff, recoil patterns and recovery, a debug view of bullet paths. Play-tested.
- [x] **4. Targets:** humanoid dummies with hit zones and armor plates, pop-down and reset, moving targets on rails, swinging steel plates. Play-tested.
- [x] **5. Feedback and HUD:** hitmarkers, damage numbers, dynamic crosshair, ammo counter and FPS, resettable range stats, placeholder sounds. Play-tested.
- [x] **6. Polish:** capped physics props, pooled ragdolls, navigable pause/settings menu, persisted preferences and worst-case performance pass. MVP complete. Play-tested.
- [x] **7. Weapon framework and attachments:** composed policies and loadout slots, cached modifiers, damage source, mounted parts, five optic types and debug cycling. Play-tested.
- [x] **8. New primaries:** SMG, LMG, pump shotgun with attachments, pellet delivery, summed damage numbers and interruptible shell reloads. Play-tested.
- [x] **9. Secondaries:** pistol with attachments, armed rockets, knife, shield, strict carried slots and pooled feedback. Play-tested.
- [x] **10. Handling animations:** procedural reload, cycle, equip, holster and melee motion for all nine weapons, pooled physics magazine drops. Play-tested.
- [x] **11. Main menu and Armory:** controller-navigable menus, shared settings, primary / secondary selection, computed stat comparisons, animated greybox preview and saved loadouts. Play-tested.
- [x] **12. Polish:** angle-limited ragdoll joints, hittable corpses, adjustable sniper zero, TTK-from-first-shot option, pooled smoke and casings, particle warm-up and final arsenal performance. Play-tested; one first-hit stall remains (see DECISIONS).

## Main menu and Armory play-test

1. Start normally. Navigate Play, Armory, Settings and Quit using arrows / Tab and Enter, then a controller's D-pad / left stick and A. Check visible focus. Quit should close the application.
2. Open Armory. Select every primary and secondary, and fit / clear parts. The pistol offers muzzle, optic and magazine; rocket, knife and shield offer no attachments. A popup consumes B / Esc to close; pressing again cancels the draft.
3. Check base / fitted values and signed changes as you fit a long barrel, quick magazine, stock and optic. Focus the stats panel and use Left/Right to reach the lower rows. Judge readability at 1280×720.
4. Rotate the preview and choose Show handling. Check fitted parts, rifle / pistol magazines, LMG cover / box / belt, shotgun shells, rocket loading and melee motion. The preview should stay centred and must not play range shots or change gameplay stats.
5. Save & Back, then Play. Confirm both selected weapons, fitted parts and ammo capacities. Return to Main Menu through pause, restart the app, and confirm the saved loadout returns. Play starts a fresh range; unsaved range debug choices are not persisted.
6. Make a different draft and Cancel / B. Confirm Play still uses the saved selection. Changes to another weapon's attachments should remain in the draft when switching away and back.
7. Change Settings from the main menu, save, enter the range and open pause. Check the same values, live effects and persistence across restart. Resume / Play must not produce an unwanted shot or jump.
8. Check about 60 fps in the menu and while inspecting fully fitted weapons. Physical controller behaviour and subjective preview / comparison readability remain human checks. The pre-existing rifle reload-stress hitch remains a Milestone 12 issue.

For direct entry, `godot -- --range` uses the saved loadout and `godot -- --armory` opens Armory. Existing `--perf-probe`, `--pose` and `--hold` arguments skip the menu. To benchmark authored defaults regardless of the saved file, specify `res://range/range.tscn` explicitly before `--`.

## Attachment tuning and play-test

Files in the following table are under `weapons/attachments/data/`. Values apply wherever the attachment is compatible. Recoil multipliers affect both the pattern and random kick. Spread values are cone half-angles in degrees; reload multipliers affect both tactical and empty times. Magazine size rounds only after all modifiers.

| Resource | Benefit | Cost |
|---|---|---|
| `baffle.tres` | Recoil ×0.85 | ADS +0.035 s |
| `ported.tres` | Recoil ×0.78 | Hip spread +0.35° |
| `compact_cap.tres` | ADS ×0.90 | Recoil ×1.12 |
| `long_barrel.tres` | Velocity ×1.10; falloff start / end +20 / +40 m | ADS +0.06 s |
| `short_barrel.tres` | ADS ×0.85 | Velocity ×0.90; hip spread +0.25° |
| `heavy_barrel.tres` | Recoil ×0.85 | ADS +0.07 s; raise +0.04 s |
| `iron.tres` | ADS ×0.85; iron sights, 65° FOV, 0.050 m sight height | Aimed spread +0.02° |
| `red_dot.tres` | ADS ×0.95; red dot, 65° FOV, 0.060 m sight height | Recoil ×1.03 |
| `scope_2x.tres` | 2× zoom / plain crosshair; 35.337009252° FOV, 0.065 m height | ADS +0.035 s |
| `scope_4x.tres` | 4× zoom / ticked crosshair; 18.098708656° FOV, 0.070 m height | ADS +0.07 s |
| `scope_8x.tres` | 8× zoom / original scope reticle; 9.106142756° FOV, 0.075 m height | ADS +0.12 s |
| `brace.tres` | Recoil ×0.80 | ADS +0.05 s |
| `light_stock.tres` | ADS ×0.85 | Recoil ×1.15 |
| `balanced_stock.tres` | Hip spread ×0.80 | Raise +0.06 s |
| `extended_mag.tres` | Magazine +10 rounds | Reload ×1.15; ADS +0.03 s |
| `quick_mag.tres` | Reload ×0.85 | Magazine ×0.80 |
| `drum.tres` | Magazine ×1.60 | Reload ×1.30; raise +0.10 s |

Fitted optic magnifications use a fixed 65° reference FOV, independently of the player's hip FOV setting. **None** preserves the native rifle 45° / sniper 12° ADS FOV and original sight geometry. Fitted irons are a deliberate trade-off, so they add aimed spread; clear attachments for the original exact first aimed shot. All primaries accept the five slots; pistol accepts muzzle / optic / magazine; rocket / knife / shield accept none. See DECISIONS for clamps, mount transforms, part dimensions, reticle values and measured performance.

1. Start with `godot`. Toggle F3 and verify all slots read None. Test the rifle's fire, ADS, reload and recoil, then press P four times to select Longwatch and check its bolt cycle and native scope. Use 1/2 to compare the chosen primary with the pistol. Existing MVP behavior should remain familiar.
2. On each weapon, cycle F5–F9 through every choice and back to None. Check the label and mounted parts agree. Use Fn if needed. F3 hides only diagnostics and the selection list.
3. Cycle F7 through irons, red dot, 2×, 4×, 8× and None. ADS at a distance sign: verify zoom / reticle changes, red-dot alignment, model hiding only for scopes, and native sights / FOV returning on None.
4. Compare long and short barrels with F4 bullet paths at 100 / 300 m. Velocity and drop should change while the numerical 100 m zero is retained. Repeat using a fitted optic with a different sight height.
5. Compare braced / light stocks and muzzle brakes during bursts. Judge recoil, ADS and spread trade-offs. Check hip crosshair bloom and the existing hit feedback.
6. Fire a few rounds; fit an extended magazine or drum. Capacity should increase without granting ammo. Reload to fill it. Fit a smaller magazine: loaded rounds clamp to capacity, and reload times change.
7. Queue changes while reloading, switching or cycling the bolt. Verify they apply safely afterwards, without refilling or resetting the action. Switch back and verify each gun retains its own choices.
8. Press F10. All five slots should clear together, native sights should return, and fire / flash / ammo / zero should still work. Pause and resume while attachments are fitted; gameplay and timers must still freeze.
9. Run the all-slots worst-case probe above with the window focused. Check about 60 fps with all 54 ragdoll parts and eight props active. Restart the game: attachment choices intentionally return to None until the Armory milestone.

## Range stats definitions

A shot counts when a single projectile or an entire pellet volley launches, or a melee swing begins (including a whiff). A hit counts once per shot if the attack damages a dummy or rings steel; hitting several zones or targets with one shell still counts once. Walls, ground, props, shields, corpses, melee whiffs and shots through a down dummy are misses. A rocket counts as one hit if any dummy receives splash damage; multiple damaged dummies still score once. Splash is torso damage and cannot score a headshot. B training rounds never enter player stats. Accuracy is hits / shots × 100. Headshot percentage is shots with any dummy head hit / all scoring hits × 100, so steel hits remain in the denominator. Both percentages stay within 0–100%; empty percentages read 0.0%.

Pellets hitting one dummy on one shot update one damage number with their summed zone-adjusted damage, rounded after summing. Any head pellet makes that target's number amber. Separate targets or shells get separate numbers. Totals update as hits arrive rather than waiting for missed pellets to expire. A target that has already died continues to ignore later hits, as before.

Time to kill is measured in physics time from the first damaging hit on each dummy life to its killing hit. With the **Time to kill starts at the first shot** setting on, the clock instead starts when the shot that first damaged that dummy was fired, so bullet flight time counts and a one-shot kill reads its flight time. Interleaved targets keep separate timers. One-shot kills read 0.000 s; the panel holds the last completed kill until the next kill or reset. Steel has no TTK. Reset clears active timers and excludes already-flying rounds from the new stats session, while still showing their real damage feedback. It does not refill ammo or restore targets. Counters record immediately; the panel refreshes at 5 Hz, with reset displayed immediately.

## New primaries play-test

1. Run the game and press F3. Press P to select Rill, Foundry, Breakwater and Longwatch in order, then return to Halberd. Check names, models and ammo; 1/2 and the wheel should still switch the two carried slots.
2. Hold Rill fire, then compare aimed / hip bursts at 25 and 100 m. Check fast ADS, 32-round capacity and the pronounced distant damage falloff.
3. Hold Foundry fire through its 100-round capacity. Check slow ADS and reload, stronger hip recoil than aimed recoil, and a short recovery delay after sprinting.
4. With Breakwater, click once near a dummy. Check eight paths with F4, one shell consumed, one shot/hit in stats and one accumulating damage number per target. A held trigger must not repeatedly fire; repeated clicks must respect the 0.8 s pump cycle.
5. Fire several shells and press R. Watch `LOADING n / capacity` increase per complete insertion. Press fire partway through an insertion: it should close, shoot a previously loaded shell and grant no partial shell.
6. Empty the shotgun and start loading. Press fire before the first insert completes; expect one queued shot after the first shell and closing delay. Repeat without interrupting to verify all six shells load in about four seconds.
7. Switch guns during loading. Return and confirm completed shells remain. Cycle primaries with partially used magazines and attachments; each gun should retain its own state without refilling or transferring attachments.
8. Try F5–F9 on each new gun, including optics and bigger magazines. Confirm safe application after handling/reload boundaries and native restoration with F10. Expanded shotgun capacities still reload one shell at a time.
9. Pause during loading or pellet flight, wait, then resume. Check timers, motion and inserts freeze. Press T with pellets in flight: old impacts may show damage but must not count in the reset stats session.
10. Run the new-primary stress commands above with the window focused. Check the selected gun is reported, all 54 ragdoll parts stay awake, eight props remain active and no projectiles are dropped. Controller gameplay remains future work.

## Secondaries play-test

1. Start the game: expect Halberd / Wayline. Press 2, then O through Cairn, Latch, Palisade and Wayline. Press P through all five primaries, including Longwatch. Check 1/2 and the wheel still select exactly two carried slots.
2. With Wayline, hold fire: expect one shot. Tap rapidly: maximum 400 rpm. Check 15 rounds, fastest switch, tactical / empty reloads, ADS and the 50 m zero (allow its 0.1° native aimed spread).
3. Fit pistol muzzle / optic / magazine parts with F5 / F7 / F9. F6 / F8 must show unavailable. Fire, exchange the secondary and return: ammo and parts must persist. F10 restores native geometry without granting ammo.
4. With Cairn, shoot a nearby wall under 10 m: expect a dud, no blast. Reload, then shoot the unarmored 25 m dummy: expect one torso splash kill, one scored hit, a pooled blast / boom and a ragdoll reset after 3 s.
5. Fire armed rockets near targets / props / steel. Judge the 6 m falloff, armor absorption, cover occlusion and outward impulses. Multiple damaged dummies must still count as one hit, with separate damage labels. No splash headshots; shots expiring in the sky must not explode.
6. Walk within 1.8 m of a dummy with Latch. Click at its head: expect 113 displayed damage and an unarmored kill. Back beyond reach and repeat: a whiff still counts as a shot. Holding does not repeat, and rapid taps respect 0.5 s. R / ADS must do nothing.
7. Equip Palisade. Check reduced walk / crouch / sprint / slide movement and normal speed after switching away. Press B facing open range: sparks should hit the front shield, no floating mark should remain when moving, and player shots / hits must stay unchanged. Check the visor, side exposure and 1.5 m / 0.9 s bash.
8. Pause during rocket flight, melee cooldown and target reset. Wait, resume and confirm simulation / effects / TTK clocks excluded menu time. Reset T with a rocket in flight; its old splash may still damage but must not count in the fresh session.
9. Run the secondary stress probes above with the window focused. Check about 60 fps, 54 awake ragdoll parts, eight props and zero dropped projectiles. Full reload / swing animations and saved Armory choices are later milestones.

## Handling animations play-test

1. Start the game. With Halberd, fire a few rounds and press R. The gun should roll to show the magazine well, the magazine should drop out and fall past the gun, and a new one should go in before the gun settles. Empty the magazine and reload: the charging handle racks near the end. Look down while reloading to see the dropped magazine land; it disappears after about 4 s.
2. Press P for Rill and Foundry and repeat. Foundry opens its cover, swaps the box, lays the brass belt and closes the cover; empty it to see the belt disappear and return.
3. Press P for Breakwater. Fire twice: the forend pumps after each shot. Reload and watch one red shell go in per insert. Press fire mid-insert: the shell vanishes, the gun closes and fires. Judge the tilt and pump feel.
4. Press P for Longwatch. Fire from the hip: the bolt lifts, pulls back, pushes and locks over the 1.1 s cycle. Scoped shots hide the model as before. Empty and reload: the bolt racks near the end.
5. Press 2 for Wayline. Tap fire: the slide cycles. Empty it: the slide stays back, and the empty reload releases it at the end.
6. Press O for Cairn. Fire: the round in the muzzle disappears. Reload: a new round appears in hand and slides into the muzzle.
7. Press O for Latch and Palisade. Click: the knife slashes across the view and the shield pushes forward, both settling by the end of the cooldown. Contact still happens on the click, so judge whether the strike looks late.
8. Switch weapons, including mid-reload: each model rolls away and in. Switching back mid-reload must show the gun at rest, with no extra drop and no ammo gained. Pause mid-reload: the animation and falling magazines freeze.
9. Fit an extended magazine or drum (F9) and reload: the larger part drops with the magazine. Fit a quick magazine: the animation runs faster with the shorter reload time.
10. Run the reload stress probe above with the window focused. Check about 60 fps, all 54 ragdoll parts and eight props, and no more than six dropped magazines.

## Polish play-test

1. Kill an unarmored dummy with the Halberd, then keep firing at the corpse. Rounds should stop on it and shove it, with sparks and a tick but no hitmarker, damage number or change to accuracy. After 3 s the dummy returns upright and rounds pass through where it was.
2. Kill several dummies with the sniper and the shotgun and watch the collapse. Limbs should flop but not fold back through the torso or spin more than a quarter turn about their length.
3. Press P to the Longwatch. Check the HUD shows `ZERO 100 m [Z]`. Press Z: 200, 300, then 100 again. At each distance, aim at a distance sign with the 8× scope (or the iron sights) and check the point of impact moves to your aim point at that range. Switch weapons and back: the zero is remembered. Other weapons show no zero label and Z does nothing.
4. Open Settings and turn on **Time to kill starts at the first shot**. Kill the 300 m dummy with the sniper: Last TTK should read roughly the flight time (about 0.4 s) instead of 0.000 s. Turn it off again to restore the original reading.
5. Fire the rifle, SMG, LMG and pistol: a small smoke puff at the muzzle and a brass casing out of the right side, landing and disappearing after about 2 s. The sniper and shotgun throw theirs a moment after the shot. The shotgun's is red. The rocket launcher smokes and ejects nothing; knife and shield do neither.
6. Fire the very first shot after starting the range, and the first shot after switching to another weapon. Note any stall; the first one should be smooth. Report a freeze of about a fifth of a second on the first hit after switching weapons: that is the known issue.
7. Run the cold probe above for a few weapons with the window focused and compare with the numbers in DECISIONS.

## Feedback and HUD play-test

1. Run the game. Confirm the top-right FPS and stats panel, bottom-right weapon and ammo, and hip crosshair. Toggle F3; the gameplay HUD should remain visible.
2. Press T. Fire one shot into the ground: shots should become 1, hits 0, accuracy 0.0%.
3. Line up with the unarmored 25 m dummy in the leftmost lane (x = -13.2 m). Use rifle torso taps: expect white markers and white numbers. Aim at the head: numbers should be amber. On a kill, expect a red X and updated TTK.
4. Shoot the armored 50 m dummy in the next lane (x = -7.2 m). Break its 50-point plate: expect a blue marker and descending break chirp. A hit that both breaks armor and kills should show the red X and kill chirp.
5. Hold rifle fire from the hip, then release it. The crosshair should expand with bloom and settle again. ADS should hide it; hitmarkers and damage numbers should still appear. Repeat scoped with the sniper.
6. Reset and make an unarmored sniper one-shot kill: shots 1, hits 1, accuracy 100.0%, headshots 100.0% if aimed at the head, last TTK 0.000 s. Wait for the dummy reset and repeat; the previous life must not extend the next TTK.
7. Shoot steel. Expect a white marker, the physical ring plus a hit chirp, one target hit, no damage number and no change to the last TTK.
8. Press T while a long shot is flying. The old round can still cause feedback, but it must not add a hit to the freshly reset counters. Confirm ammo and target state remain unchanged by T.
9. Run `godot --always-on-top -- --perf-probe --perf-fire`. Check the full HUD remains active and the capped average stays near 60 fps.

## Target play-test

- Walk across the firing stalls to line up with the staggered stationary dummies. Check head, torso and limb hits with both weapons; the 25 m and 300 m stationary dummies are unarmored.
- Shoot armored dummies until they ragdoll. Check that shots pass through during the 3 s downtime and that armor and health return together.
- Track the movers at 50 and 100 m, watching the end reversals and resets while moving.
- Shoot steel at 100/200/300 m and check swing direction, settling and ring audibility. Bullet drop still applies; F4 helps inspect misses.
- Judge silhouette readability, armor durability, pop-down feel and distant ring volume. Hitmarkers, damage numbers and confirmation sounds are now available for this check.

## Final MVP play-test checklist

1. Start normally. Walk into a crate and barrel near x = ±18 m behind the firing line, then into the props at x = ±6 m, z = 12 / 17 m in the test area. They should move without launching or trapping the player.
2. Shoot props from the front and off-centre. Expect movement away from the shot and rotation from off-centre hits. Props are not scoring targets.
3. Open Esc during a burst, reload or target reset. Check that projectiles, props, ragdolls and target reset timing stop. Wait, then resume; TTK must not include menu time.
4. Navigate every setting using only arrows / Tab and Enter / Space. Repeat with controller Start, D-pad / left stick, A and B. Confirm focus is always visible and cycles back to Resume.
5. Change every setting, resume, then restart the app. Confirm saved values return. Check ADS scaling with both weapons, bob / FOV kick at 0 and 2, both volume sliders at 0 and 1, and FPS visibility independently of F3.
6. Resume with Enter, Space, controller A and a mouse click. Confirm no unwanted shot or jump occurs and the cursor capture mode is restored.
7. Kill stationary and moving dummies. The killing shot should affect the corpse, rails should leave the corpse behind, and the dummy should return upright with armor and exact hit zones after 3 seconds of unpaused play.
8. Run the existing Feedback and HUD checklist above to check markers, numbers, accuracy, headshots and per-life TTK after ragdoll resets.
9. Run the capped worst-case command above, keeping the window focused. Confirm about 60 fps, eight stress props and `54 min / 54 max` awake ragdoll parts. Inspect the uncapped run if diagnosing headroom.

## Future phases and known limitations

- **Web:** browser export and browser performance are not yet validated. Test pointer-lock gestures, audio unlock, user-config persistence and the selected physics backend in the export templates. Runtime code uses built-in Godot APIs and `user://` storage; no native plugin, subprocess or platform-specific service was added.
- **Controller:** menus have explicit bindings and focus navigation. Full movement / right-stick aiming, gameplay mappings, dead-zone tuning, remapping and device-specific prompts remain post-MVP. Physical controller validation is still needed.
- **Physics:** ragdolls are six greybox parts with cone-twist joints. Jolt enforces the limits softly, and Godot exposes no stiffness setting for it, so hard hits overshoot by about 12°. Corpses collide with the world / props and are hit by bullets, but not by other corpses, the player, melee or the knife; this bounds contact cost. Props are capped at eight and recycle after escaping their area.
- **Display / assets:** OpenGL on the tested Mac uses a 60 fps limiter rather than enforced vsync. Occasional pacing spikes remain possible. Visuals and sounds are placeholders; Movie Maker can still warn about active audio playbacks at capture shutdown.

## Further reading

- [docs/DECISIONS.md](docs/DECISIONS.md): why things are the way they are (renderer, movement model, tuning, measured performance).
- [CREDITS.md](CREDITS.md): third-party assets and tools.

## License

TBD.

## Milestone 13 — controller support (hardware play-test pending)

Gameplay uses InputMap for both devices. Prompts follow the last meaningful input;
small stick noise is ignored. Unmapped pads use Godot's generic button labels.
Disconnecting the active pad pauses the range and clears held/toggled actions.

| Controller input | Range action | Keyboard / mouse |
|---|---|---|
| Left stick | Move | WASD |
| Right stick | Look | Mouse |
| RT / LT | Fire / ADS | Left / right mouse |
| LB / RB | Previous / next weapon | Wheel |
| A | Jump | Space |
| B | Crouch / slide | Ctrl / C |
| X | Reload | R |
| Y | Swap weapon | 1 / 2, wheel |
| LS click | Sprint | Shift |
| RS click | Attack with equipped knife / shield | V (or fire) |
| D-pad Up | Cycle sniper zero | Z |
| Back | Reset range statistics | T |
| Start | Pause | Esc |
| D-pad / left stick, A, B | Navigate, accept, back | Arrows, Enter, Esc |

Settings includes controller X/Y rates, radial dead zone, linear/cubic ramp,
controller invert Y, aim slowdown, rumble, hold/toggle ADS/crouch/sprint and
auto sprint. Defaults preserve keyboard/mouse behavior. Remap controls captures
keys, mouse buttons, pad buttons and signed axes, reports gameplay conflicts,
and saves immediately to `user://bindings.cfg`. Restore defaults is available.
UI navigation bindings remain available as a recovery path. Settings save on
Save & Back / Resume to `user://settings.cfg`.

### Controller play-test (human validation required)

1. Record controller model, USB/Bluetooth connection and macOS version. Connect
   it before launch; navigate Play, Settings and Armory using only the pad.
2. Change a weapon and attachments, save, then enter the range. Check A/B menu
   acceptance/cancellation and that no menu press fires or jumps on entry.
3. Walk diagonally and at partial stick deflection. Jump, sprint, crouch and
   slide; check all mappings above, switching and sniper zero.
4. Leave the right stick centered: verify no drift. Adjust dead zone; compare
   linear and dynamic curves, independent X/Y speeds and invert Y. Compare a
   full-stick turn at different frame caps; turn rate should stay constant.
5. ADS with each optic; check reduced sensitivity. Sweep across a live dummy
   with slowdown 0, 0.5 and 1. Check slowdown without snapping; release the stick
   and confirm no tracking. Switch to mouse and confirm its feel is unchanged.
6. Try each hold/toggle option and auto sprint. Pause/resume while holding
   triggers or toggled ADS; confirm no unwanted shot or stuck stance.
7. Check rumble on firing, target hits and reloading, then disable it. **Actual
   macOS motor output is unverified.** Player damage rumble awaits Milestone 15.
8. Remap one keyboard key, mouse button and controller input. Try a conflict;
   check the message. Restart and verify bindings persist. Restore defaults.
9. Unplug the pad while moving, firing and aiming. Confirm pause/warning and no
   stuck input. Reconnect, resume, and alternate mouse/pad to check prompts.
10. Fire with all targets/props active at 720p. Record FPS and any hitch. Report
    results with the controller model/connection; synthetic tests cannot certify
    hardware mappings, Bluetooth behavior, drift, rumble or subjective feel.

Challenge screens do not exist until Milestone 16; their controller navigation
must be validated when implemented. Stop here for the Milestone 13 play-test.
