# Decisions

Non-obvious choices, newest milestone last. Each entry says what was chosen, why, and what would make us revisit it.

Target machine for every measurement below: MacBook Pro, Intel i5-8259U, 8 GB, Intel Iris Plus Graphics 655, macOS Sequoia, Godot 4.7.2 stable.

## Project setup

### Renderer: Mobile, with three restrictions on this GPU (superseded)

**Superseded:** the project now uses Compatibility. See "Renderer switch to Compatibility" at the end of this file. This entry is kept as the evidence for that switch.

Mobile holds 60 fps with a wide margin (see Performance), so the rule in `CLAUDE.md` at the time said stay on it. On this Intel GPU it runs through Vulkan on MoltenVK, and three things do not work:

| Problem | Evidence | What we do |
|---|---|---|
| 8 engine compute pipelines fail to compile at startup (`Compute pipeline compile failed ... AIR builtin function was called but no definition was found`) | Happens with an empty scene, before any project code runs | Nothing we can fix. They are logged on every windowed boot. Avoid engine features that need compute shaders. |
| A `Sky` background triggers 14 more errors on the first frame, and sky-based ambient light renders black or blocky | Reproduced in a 3-node test scene; gone with a colour background | Background is a flat colour, ambient light is a fixed colour, reflections are off. No `Sky` resource anywhere. |
| Sun shadows misrender while the camera turns upward: the far shadow cascade marks the whole ground as shadowed for those frames | Scripted jerky-camera capture: 2 splits about 40% of the lower frame dark, 4 splits about 20%, single cascade about 90%. A still camera is fine. Not caused by physics interpolation (same result with it off). | The sun's `shadow_enabled` is off. Shapes are read from direct light plus ambient only. |

The Compatibility renderer has none of these problems on this machine: zero startup errors and clean sun shadows in the same jerky-camera test. It is slower here (about 174 fps with shadows, against about 300 fps for Mobile without) but still nearly three times the budget.

**Outcome:** the project owner approved the switch after Milestone 1.

### HiDPI off

`display/window/dpi/allow_hidpi=false`. The built-in display is Retina, so with HiDPI on a 1280x720 window renders 2560x1440 pixels, four times the fill cost. The perf probe prints the real window pixel size to confirm 1280x720.

### Physics interpolation on

`physics/common/physics_interpolation=true`. Gameplay runs only at the 60 Hz tick. Interpolation keeps the camera smooth when a rendered frame does not line up with a tick. The camera rig is `top_level` with interpolation off and follows the body's interpolated transform each frame, so mouse look has no added latency.

### Static typing enforced

`debug/gdscript/warnings/untyped_declaration=2` makes an untyped declaration a parse error. The unsafe access and cast warnings are on as warnings. Addons are excluded by the engine default.

### GUT 9.7.1, vendored

9.7.x is the GUT line for Godot 4.7. It lives in `addons/gut/` and is committed, so tests run from a fresh clone after `godot --headless --import`.

### Repository layout

The git repository root is `SHOOTER/` (holding `CLAUDE.md`); the Godot project root is `SHOOTER/firing-range/`. All Godot commands run with `--path firing-range` or from inside that folder.

## Milestone 1: movement and greybox range

### Movement model: friction plus capped acceleration

Ground movement is friction followed by acceleration toward a wish velocity, the classic arena-shooter model, because it gives momentum for free: speed builds over about 0.2 s, direction changes carry sideways drift, and releasing the keys coasts to a stop.

Two deliberate changes from the classic model:

- **Acceleration is capped.** Input can redirect momentum but never push horizontal speed above `max(speed before, target speed)`. The uncapped version overshoots when accelerating at an angle to the current velocity. That is the strafe-jump exploit in the air, and a first test run showed it also gave 7.28 m/s against a 7.0 m/s sprint when turning on the ground. Top speed is now exactly the configured value. The same capped function does air control and slide steering.
- **Friction is integrated exactly** (exponential above `stop_speed`, linear below), so its result does not depend on tick rate.

### Slide: constant deceleration

A slide is kinetic friction, so speed falls linearly at `slide_deceleration` until `slide_end_speed`, then becomes a crouch. Duration and distance have closed forms (`MovementMath.slide_duration`, `slide_distance`) that the tests check against the simulation. Slopes do not affect slide speed yet; the range is flat apart from one test ramp.

A slide starts from speed, not from the sprint key: crouch while moving at or above `slide_min_entry_speed` (5.5 m/s, above walk speed). The entry boost has a cooldown so chained slides cannot build speed.

### Gravity as two half steps

Each airborne tick applies half of gravity before the move and half after (velocity Verlet). The jump arc then matches the analytic parabola: the tested apex is within 2 mm of `jump_height` in pure math and within 3 cm on the Jolt body. Jump velocity is derived from `jump_height` and gravity rather than tuned directly.

### Stance changes the collider, feel changes the camera

Crouch and slide shrink the capsule from the top (feet stay planted) at `crouch_transition_speed`. Standing back up is refused while a body test says there is no headroom. The gameplay eye is always `collider height - eye_offset_from_top`; `PlayerController.get_eye_position()` and `get_aim_basis()` are the origin and direction that bullets will use.

Head bob, landing dip, slide camera drop and roll, and the sprint/slide FOV kick are all in `CameraFeel`, which only reads from the player. They cannot change movement or, later, hit results.

### FOV is stored as vertical degrees

Godot cameras take vertical FOV. The default is 65 vertical, about 97 horizontal at 16:9. The overlay shows both.

### No stair stepping yet

`CharacterBody3D` does not step up ledges. The three steps in the test area (0.5 m each) are meant to be jumped. If targets or props later need walkable low ledges, add a step-up shape cast then.

### Range is generated, not hand-placed

`range/range_builder.gd` builds ground, walls, lanes, markers and the test area in `_ready` from exported numbers, so every distance has one source and the scene file stays small. Signs grow with distance (digit height is 2% of distance) to stay readable from the line, and each sign is pushed sideways until it clears the one behind it as seen from the firing line.

The ground uses a world-space grid shader (1 m cells, heavier lines every 5 m). A flat colour gives no motion cue, which makes movement feel impossible to judge.

### Tuning starting points

Walk 4.5, sprint 7.0, crouch 2.2 m/s. Ground accel 9 /s against friction 6 /s reaches walk speed in about 0.18 s and stops in about 0.26 s. Jump height 0.65 m under 9.81 m/s². Slide: +1.5 m/s boost capped at 9, deceleration 6 m/s², so a sprint slide lasts about 0.9 s over about 5.3 m. These are first guesses for play-testing, all in `player/data/movement_default.tres`.

### Automated runs never grab the mouse

The player captures the mouse only in a normal windowed run. Headless runs, Movie Maker captures and the perf probe set `mouse_look_enabled = false`. Before this, Movie Maker captures picked up real mouse movement and produced frames with a turned camera.

### Performance (Milestone 1)

Measured with `godot --path . --disable-vsync -- --perf-probe`: 10 s sprinting downrange while sweeping the view 50 degrees each way, 1280x720 window.

| Configuration | Average | 1% low | Frames over 16.67 ms |
|---|---|---|---|
| Mobile, no sun shadow (shipped) | 306 fps | 169 fps | 1 of 3062 |
| Mobile, sun shadow 2 splits | 263 fps | 186 fps | 1 of 2630 |
| Compatibility, sun shadow 2 splits | 174 fps | 114 fps | 0 of 1736 |
| Mobile, no sun shadow, vsync on | 60.0 fps | 55.5 fps | none over 25 ms |

The scene is 42 draw calls and about 1,100 primitives. The single slow frame in the uncapped runs is a one-off hitch (worst 33.5 ms), not a pattern.

## Renderer switch to Compatibility (after Milestone 1)

### Renderer: Compatibility (OpenGL 4.1)

`rendering/renderer/rendering_method="gl_compatibility"`. The project owner approved the switch because Mobile's faults on the target GPU were correctness problems, not frame rate (see the superseded entry under Project setup). Everything that was turned off as a Mobile workaround was re-tested and is back on.

| Check | Mobile | Compatibility |
|---|---|---|
| Errors in the windowed boot log | 8 compute-pipeline failures on every boot, plus 14 first-frame errors with a `Sky` | 0 errors, 0 warnings |
| Sun shadow, jerky-camera capture (share of the lower frame that goes dark on upward-pitched frames) | about 40% | no change from the no-shadow baseline (at most 9%, which is the unlit wall) |
| Sun shadow, static pitched poses | clean | clean, every frame identical |
| Procedural sky with sky ambient | errors, black or blocky ambient | clean in the same captures |

The captures are the ones used for the Mobile findings: a scripted camera that jumps in yaw and pitch every frame for 40 frames, plus static poses at the firing line, 10 m downrange pitched up between 5 and 45 degrees, and facing the test area and crouch tunnel.

Two things had to be retuned for how Compatibility lights the scene:

- **Light levels.** Compatibility draws a shadow-casting light in a separate additive pass, which brightens lit surfaces. Sun energy went from 1.2 to 0.6 and ambient energy from 0.75 to 0.6 to keep the lit ground at the same mid grey (about 139, 157, 160 in the capture).
- **Sky ambient at 40%.** With all ambient light taken from the sky, the ground came out strongly blue (shadowed ground 52, 85, 110). `ambient_light_sky_contribution = 0.4` mixes the sky with a neutral colour, which keeps a slight cool tint in shadows and a grey ground.

### Frame cap at 60 instead of vsync

Native OpenGL on this macOS does not enforce vsync. With the window focused for the whole run and `window_get_vsync_mode()` reporting enabled, the perf probe measured 119.8 fps. Re-applying the vsync mode after the window was shown changed nothing.

Options tried:

| Option | Result |
|---|---|
| Native OpenGL, vsync on | Not enforced: 120 to 145 fps across seven runs |
| ANGLE driver (`opengl3_angle`) | 90 to 127 fps uncapped with 1% lows of 37 to 62 fps, and a 1.05 s hitch in both vsync runs. Too little headroom. |
| Native OpenGL, `application/run/max_fps=60` | 59.8 to 60.0 fps, median frame 16.6 to 16.7 ms |

So the frame rate is held by `application/run/max_fps=60`. This is a frame limiter, not a display sync: frame count is steady at 60, but frames are not aligned to the display refresh. Windowed apps on macOS go through the compositor, so there is no tearing; an occasional repeated frame is possible. Revisit if play-testing shows judder.

### Performance after the switch

1280x720 window, final configuration (sun shadow with 2 splits, procedural sky), same 10 s sprint-and-sweep probe as Milestone 1.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| As played (60 fps cap), focus steady | 60.0 fps | 54.0 fps | 18.8 ms |
| Uncapped (`--disable-vsync --max-fps 0`), 7 runs | 145 to 193 fps | 84 to 111 fps in runs with steady focus | 9.6 to 26.4 ms |

47 to 52 draw calls, about 1,250 primitives.

Caveats on these numbers:

- Whenever the window gained or lost focus during a run, that run had one frame of about 70 ms. It happened in several probe runs because the probe is launched from a background shell and focus moved mid-run; those runs' 1% lows (down to 26 fps capped, 61 fps uncapped) are excluded above. It is an app-switch hitch, not a steady-state one: no run without a focus change had a frame over 26.4 ms. Focus tracking was added to the probe partway through, so for the first three uncapped runs steady focus is inferred from the absence of that hitch.
- The steady as-played run happened to be unfocused throughout. A fully focused capped run was not captured, so confirm it by eye with the overlay (`ms worst`) during play-testing.
- Uncapped averages vary by about 30% between runs on this machine, so treat the range as the result rather than any single figure. Mobile without shadows was about 300 fps; Compatibility with shadows and sky is roughly half that and still well over twice the budget.

## Milestone 2: shooting core

### Projectiles are rows in packed arrays

`ProjectileSystem` is one node holding position, velocity, age and spec arrays for up to 128 projectiles. Firing takes a free slot and allocates nothing. Each tick integrates every live projectile and raycasts from the previous position to the new one, so a 900 m/s bullet (15 m per tick) cannot skip a thin wall. The system runs after weapons in the tick, so a shot moves on the tick it is fired. Integration is exact for constant acceleration; Milestone 3 adds drag by changing the acceleration and adds fields to `ProjectileSpec`.

### Shots leave from the eye, not the muzzle

**Superseded by sight zeroing below:** the fixed gameplay bore origin is now one configured sight height below the eye. Animated viewmodel geometry still has no effect on hits.

Bullets start at `PlayerController.get_eye_position()` along `get_aim_basis()`. The viewmodel, its kick and the muzzle flash are cosmetic. A test fires a second of full-auto and checks every round lands on the same point.

### Weapon timing

- The shot interval remainder is carried from shot to shot, so 700 rpm (5.14 ticks) averages exactly. It is not carried across a pause, which had made the first interval of a burst one tick short.
- Bullets spawn on tick boundaries; there is no sub-tick spawn offset.
- Ammo changes only on a shot or a completed reload, so a reload cancelled by switching leaves the count untouched. A reload fills the magazine; there is no reserve ammo on the range.
- Pulling the trigger on an empty magazine starts the empty reload. A reload pressed mid-cycle is queued until the weapon is ready.
- Sprinting blocks firing and aiming, as specified; it does not block reloading. Reloading drops the aim. The sniper stays scoped while the bolt cycles.
- Fire and reload presses are latched from input events, because polling an edge in the physics tick loses a click shorter than one tick.

### Never toggle `visible` under the camera rig

The camera rig has physics interpolation off. In Godot 4.7, after `visible` is toggled on a node in that subtree, the renderer stops receiving its later transform changes: the viewmodel froze on screen while its script kept moving it. `WeaponView` therefore adds and removes models from the tree and hides the muzzle flash by scaling it.

### Effects

- Impact marks are instances in one MultiMesh that reuses the oldest, because the Compatibility renderer has no Decal node. Marks only stick to static bodies.
- Particles are `CPUParticles3D`. `GPUParticles3D` was not evaluated.
- Sounds are synthesised at startup from seeded noise and sine tones, so the project has no audio files.

### Capture quirks (Movie Maker only)

Physics runs somewhat behind the frame count in Movie Maker mode on this machine, so `--hold` times are in physics seconds and captures need extra frames. Quitting a capture while sounds are playing logs a "5 ObjectDB instances leaked" warning from the audio playbacks; normal runs that quit mid-burst do not.

### Tuning starting points

| | Halberd R-5 | Longwatch B-9 |
|---|---|---|
| Muzzle velocity | 850 m/s | 900 m/s |
| Rate | 700 rpm, full-auto | 1.1 s bolt cycle |
| Magazine | 30 | 5 |
| Reload, tactical / empty | 1.9 s / 2.4 s | 2.6 s / 3.3 s |
| ADS time, FOV, sensitivity | 0.25 s, 45°, 0.7 | 0.4 s, 12°, 0.2 |
| Raise / lower | 0.4 s / 0.3 s | 0.6 s / 0.45 s |

### Performance (Milestone 2)

Perf probe walking downrange and firing full-auto with reloads, 1280x720, window focused for the whole run.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| Firing, as played (60 cap) | 60.0 fps | 55.0 fps | 18.5 ms |
| Firing, uncapped | 177.8 fps | 99.3 fps | 21.0 ms |
| Sprinting, uncapped (Milestone 1 probe) | 184.3 fps | 110.0 fps | 9.7 ms |

73 draw calls and about 2,050 primitives while firing. 167 tests pass.

## Milestone 3: ballistics and recoil

### Drag model: quadratic, constant Cd, RK4 per tick

Drag deceleration is `k * |v| * v` with `k = 0.5 * air density * Cd * area / mass`. Cd is held constant rather than varying with Mach number. That is a simplification, but over the 0 to 400 m the range covers both bullets stay supersonic, where a real G7-style Cd changes slowly. Each physics tick takes one RK4 step: it is within a millimetre of a 240 Hz run at 300 m, and the drop matches the analytic flat-fire solution to 2 mm at 100, 200 and 300 m (tests in `test_projectile_math.gd` and `test_projectile_system.gd`). The flat-fire solution treats |v| as the horizontal speed, which for these shots is exact to a few parts per million. A spec with Cd 0 keeps the exact vacuum parabola.

The swept raycast still goes in a straight line from the old position to the new one. Over one tick the curved path sags 0.3 mm from that chord.

| Bullet | Mass, diameter, Cd | k (1/m) | Speed at 300 m | Drop at 100 / 200 / 300 m (vacuum) |
|---|---|---|---|---|
| Halberd R-5, 850 m/s | 4.0 g, 5.7 mm, 0.30 | 0.00117 | 598 m/s | 7.3 / 32 / 78 cm (6.8 / 27 / 61) |
| Longwatch B-9, 900 m/s | 10.9 g, 7.82 mm, 0.27 | 0.00073 | 723 m/s | 6.4 / 27 / 63 cm (6.1 / 24 / 55) |

The rifle loses about 30% of its speed by 300 m and the sniper about 20%, in line with real 5.56 mm and 7.62 mm rifle rounds.

### Damage falloff by distance, not by impact speed

Damage is full out to a start distance, then falls linearly to a minimum fraction at an end distance, measured along the flight path. Scaling with impact energy would have tied damage to the drag tuning; separate distance knobs are easier to balance. The rifle does 32, falling to 70% between 50 and 200 m. The sniper does 110, falling to 80% between 150 and 400 m. Hit zones and armor come in Milestone 4, on top of `ProjectileHit.damage`.

### Recoil moves the real aim

Each shot adds its pattern entry plus a random deviation to a recoil offset on the player (`recoil_pitch`, `recoil_yaw`). That offset sits on top of the mouse look angles, and both the bullets and the camera follow it, so recoil is gameplay rather than an effect. The camera blends the offset between ticks so a kick does not step at high frame rates.

- **Recovery.** Once the weapon has rested for `recoil_recovery_delay`, the offset returns to zero at `recoil_recovery_rate`. The rifle's 0.12 s delay is longer than its 0.086 s shot interval, so nothing recovers mid-burst.
- **Compensation is not recovered twice.** Mouse movement against the offset cancels it before it moves the base angle. Without this, a player who pulls the spray down would then have the view recover further down, below the target.
- **Pattern reset.** The pattern restarts at shot 1 after `recoil_reset_time` without a shot. Past its last entry, the last `recoil_loop_length` entries repeat.
- **Aimed scale.** The rifle kicks at 80% while aimed; the sniper kicks the same either way.

The rifle pattern climbs about 0.45 to 0.6 degrees per shot for the first 10 rounds, drifts right, swings left, then wanders at 0.3 degrees per shot. That is about 11.8 degrees over a full magazine before the aimed scale. The sniper kicks 4 degrees up and 0.3 degrees right, ±0.5 degrees, and recovers at 12 degrees per second, well inside its 1.1 s bolt cycle.

### Spread and first-shot accuracy

Shots leave inside a cone: hip spread blended to aimed spread by ADS progress, plus bloom. Each shot adds bloom, and it shrinks only after the same rest delay as recoil recovery, so it builds through a burst and settles between taps. Both weapons have zero aimed spread, so the first aimed shot from a settled weapon goes exactly along the sights. Hip spread is 2 degrees for the rifle and 4 for the sniper. The rifle blooms 0.15 degrees per shot up to 1.2. Points in the cone are spread evenly over its cross-section.

Recoil and spread draw from one seeded random generator on `WeaponController` (`random_seed`, or `reseed()`). Tests seed it. The Milestone 2 test that "every round lands on the same point" no longer holds now that recoil moves the aim. It is replaced by a test that a seeded burst lands identically with the `WeaponView` node removed entirely, which still proves the viewmodel never feeds into hits.

### Bullet path view

`debug/bullet_paths.gd` draws the points the simulation actually visited, one per tick, with no smoothing, so it shows exactly what the hit test swept. It is drawn without a depth test, so paths stay visible behind walls and over the viewmodel.

The first version rebuilt an ImmediateMesh vertex by vertex every tick, which cost about 6 ms a frame with 40 long paths (84 fps uncapped against 162). Each path now builds its own line vertices as it records, and a redraw concatenates them natively into one ArrayMesh surface, at about 1 ms.

### Movie Maker frames repeating (correction to the Milestone 2 note)

The Milestone 2 note blamed physics for running behind in Movie Maker. The actual cause is macOS throttling a Godot window that is not in front: Movie Maker then reports far fewer frames rendered than written (25 of 200) and repeats the last one. Running with `--always-on-top` fixed it; all 200 frames were distinct.

### Performance (Milestone 3)

Perf probe walking downrange and firing full-auto with reloads, 1280x720, window focused for the whole run.

| Run | Average | 1% low | Worst frame |
|---|---|---|---|
| Firing, as played (60 cap) | 60.0 fps | 53.7 fps | 18.8 ms |
| Firing with bullet paths, as played (60 cap) | 60.0 fps | 53.6 fps | 18.7 ms |
| Firing, uncapped | 163.7 fps | 102.0 fps | 11.4 ms |
| Firing with bullet paths, uncapped | 132.1 fps | 53.0 fps | 23.9 ms |

Drag, recoil and spread cost about 0.5 ms a frame against Milestone 2's 177.8 fps uncapped (5.6 to 6.1 ms). No capped run had a frame over 25 ms. 206 tests pass.

## Milestone 4: targets

### One swept hit path, solid humanoid zones

`TargetHits` listens to the existing `ProjectileSystem.projectile_hit` and dispatches only to the collider named in that report. There are no target raycasts, overlap checks or separate damage sweeps. Each humanoid has six `AnimatableBody3D` boxes (head, torso, two arms, two legs), on the same layer the projectile sweep already hits. The carrier moves them at the physics tick with `sync_to_physics` off, so collider and visible positions agree. Using animatable rather than static bodies also keeps the existing impact effects from leaving floating marks on moving or folding targets.

Zone multipliers live in `targets/data/dummy_default.tres`: head 1.5, sniper head 2.0, torso 1.0, limbs 0.8. `ProjectileSpec.weapon_class` selects the sniper rule explicitly; neither weapon names nor damage thresholds select it. Ballistics applies distance falloff before the target applies its zone multiplier, then armor and health. The zone enum belongs to the tuning Resource: making that Resource depend on the hit-zone node created a circular preload through the dummy's default Resource, which retained GUT resources at shutdown. Keeping data dependencies independent of nodes removes that cycle.

### Armor is a contiguous pool of plates

`TargetHealth` is node-free. Remaining armor is a float pool initialized to `plate_count * plate_health`, with the count clamped to 0–3. Damage subtracts `min(armor, damage)` from armor and sends the remainder to health. An exact break on the final plate leaves health untouched; there is no rounding or lost overflow between plates. `remaining_plates()` rounds upward so a partially damaged plate still counts. Negative damage and hits while dead do nothing.

A kill disables all hit-zone layers immediately, folds the silhouette backward over 0.15 s, and restores its health, initial armor and upright pose exactly 3 s after the kill (not 3 s after folding finishes). The clock and pose update at the physics tick. Movers continue on their rails during downtime; a reset happens wherever the carrier is, without teleporting the rail.

### Layout and rail motion

Nine dummies are active: stationary at 25/50/100/200/300 m with 0/1/2/3/0 plates, plus four unarmored movers. The stationary targets are staggered across the five lanes rather than stacked directly behind each other. At both 50 and 100 m, the left rail walks at 1.5 m/s and the right rail sprints at 6 m/s. Each rail is 4 m long. These are exported layout values on `RangeBuilder`; the armor assignment and placement are in `_build_targets()`.

A rail folds an increasing travelled-distance phase into an outgoing and returning leg. It preserves endpoint overshoot, reverses immediately on exact endpoints, and handles several reversals in one step. Tests check speed, both endpoints, large versus small steps, and a real projectile striking a rail-carried zone at its moved position.

### Steel uses physics, not an animation

Three 8 kg steel boxes hang at 100/200/300 m from world-anchored `HingeJoint3D` nodes. The hinge's axis is world X at the top of each plate, limited to ±65 degrees. On an existing projectile report, the plate receives an off-centre impulse of `bullet mass * impact velocity * impulse_scale`; Jolt supplies the swing, gravity and settling. Tuning exports are in `targets/steel_plate.gd`. A real-projectile test checks the ring event, hinge constraint and physical rotation.

The placeholder ring is a cached, one-second decaying pair of inharmonic sine tones in `SfxFactory.steel_ring()`, played spatially with a 60 m unit distance so it remains audible downrange. This intentionally generous attenuation is for range feedback; judge distant volume during play-testing. No audio or other binary assets were added.

### Verification and performance (Milestone 4)

Headless GUT: 221 tests cover the complete project, including armor-first carry-over, an exact final-plate break, both weapons' zone multipliers, pop-down and exact reset timing, real sniper headshot / rifle body-shot outcomes at 100 m, all four limb colliders, rail movement and moved hit zones, and a real projectile ringing and swinging steel. Windowed and headless boots have zero errors. Movie Maker frames were inspected from the range and close to the 25 m dummy; human play-testing of readability, durability, motion feel and distant ring volume remains pending.

1280×720, Compatibility, all nine dummies and three steel targets active, walking and firing full-auto with reloads (`godot --always-on-top -- --perf-probe --perf-fire`). Window focused for 100% of measured frames:

| Average | 1% low | Worst frame | Frames over 25 ms | Draw calls / primitives |
|---|---|---|---|---|
| 60.0 fps | 53.3 fps | 21.18 ms | 0 of 601 | 162 / 2,750 |

The extra meshes and physics bodies retain the 60 fps target on the Intel Iris Plus 655. Values above describe a capped run, not an uncapped headroom measurement.


## Sight zeroing (after Milestone 4)

### Geometry-derived bore offset and equip-time calibration

Both weapon Resources now specify `zero_distance_m = 100.0`. `sight_height_m` is measured from the reference geometry, rather than from the animated pose or the camera-relative ADS translation:

| Weapon | Sight reference | Bore reference | Sight height |
|---|---|---|---|
| Halberd R-5 | FrontSightPost tip: centre y 0.045 + half-height 0.015 = 0.060 m | Barrel / Muzzle centre y 0.010 m | 0.050 m |
| Longwatch B-9 | Scope optical axis y 0.085 m | Barrel / Muzzle centre y 0.012 m | 0.073 m |

The projectile starts at `gameplay eye - gameplay aim up * sight_height_m`, without forward or sideways cosmetic muzzle offsets. The reference geometry supplies the tuning value only; removing the viewmodel, changing its kick or moving its rendered pose cannot alter the shot. This replaces the earlier eye-origin convention and makes the below-sight start and both sight-line crossings possible.

`SightZeroing.solve()` bisects the upward low-arc bracket from 0 to 45 degrees, using full `sin` and `cos` to form each trial launch velocity. Every trial uses `ProjectileMath.step_drag()` at the actual physics tick, including projectile gravity scale and drag at the active system's air density. Its final sample intersects the sight-distance plane along the same straight chord used by the projectile sweep, rather than integrating a shorter final tick. There is no flat-fire formula, small-angle approximation or separate hit path in calibration.

`WeaponController` solves once when the weapon is equipped, including the initial equip. Switching back solves again with the current atmosphere and physics settings. Each shot rotates the gameplay aim upward by the cached angle and applies spread around that bore direction. Existing recoil remains in the gameplay aim, and this shot's recoil is still applied after its bullet leaves. The calibration is for a horizontal line of sight; it is a fixed mechanical bore/sight angle when aiming uphill or downhill. A zero distance of 0 disables the angular correction; an unreachable low-arc zero warns and falls back to an uncalibrated bore.

### Angles and trajectory table

Godot's own integrator and swept-plane intersection, 60 Hz, gravity 9.81 m/s², air density 1.225 kg/m³, original weapon bullet specs, level settled aim:

| Weapon | Elevation above sight line (radians) | Elevation (degrees) |
|---|---|---|
| Halberd R-5 | 0.001238613 | 0.070967308° |
| Longwatch B-9 | 0.001367129 | 0.078330732° |

Signed impact height relative to point of aim, in centimetres. Positive is above aim; negative is below. These are zeroed trajectories, not the old unzeroed horizontal-launch drop figures.

| Distance | Halberd R-5 | Longwatch B-9 |
|---|---|---|
| 25 m | -2.359 | -4.295 |
| 50 m | -0.604 | -2.048 |
| 75 m | +0.203 | -0.597 |
| 100 m | 0.000 | 0.000 |
| 125 m | -1.276 | -0.302 |
| 150 m | -3.689 | -1.501 |
| 200 m | -12.187 | -6.746 |
| 300 m | -46.218 | -29.710 |

**The requested above-aim impact at 50 m conflicts with the measured sight heights and a 100 m zero.** The rifle is still below its first crossing at 50 m; it is above aim at 75 m and returns through aim at 100 m. The sniper's 73 mm sight height puts its first crossing at 100 m, with its second crossing a little farther downrange. Keeping the geometry and 100 m zeros therefore requires the below-aim values shown at 50 m. Getting both weapons above aim there would require changing sight geometry or zero distance. The tests preserve these physical inputs and the computed offsets rather than assuming a sign; a separate lower-sight test demonstrates the expected positive 50 m rise and two crossings.

### Verification

Pure solver tests compare against independent 240 Hz integration with and without drag, exercise a launch angle above 20 degrees to guard against small-angle shortcuts, and cover disabled and unreachable zeros. Geometry tests measure the front sight tip and scope axis against the viewmodel muzzle references. Live controller tests equip both weapons and fire into real Jolt walls at 50, 100 and 300 m: zero-distance impacts must be within 1 cm of aim, and other distances must agree with the integrator within 1 mm. A switch test changes air density and verifies recalibration on equip. Existing recoil, spread and viewmodel-independence tests remain in the full suite.

Full headless suite: **228/228 tests pass**, with clean shutdown. Headless and windowed startup checks both completed without errors.

## Milestone 5: feedback and HUD

### Target signals are the only feedback authority

`RangeFeedback` listens to each dummy's existing `damaged` / `restored` signals and each steel target's existing `rang` signal. It never raycasts, computes damage or applies impulses. A dummy now exposes `last_plate_breaks` before emitting `damaged`; steel exposes `last_hit` before `rang`. The existing signal signatures remain unchanged. Targets do not depend on UI scripts.

Marker priority is kill > armor break > hit. Breaking any plate, including an exact 50-point break, is blue; removing only part of a plate is white. A killing hit that also breaks armor is red. A stronger visible marker is retained for its remaining lifetime if a weaker event arrives immediately afterward. Feedback remains visible during ADS and through the scope overlay.

Damage labels show the signal's zone-adjusted incoming damage, including overkill, rounded to the nearest whole point. Body and limb numbers are white; head numbers are amber. Steel has a white hitmarker and confirmation sound but no damage number because it has no health. Numbers are pooled screen-space labels anchored to the world hit point, offset alternately left/right, rising in pixels and fading. They hide behind the camera and expire after 0.8 s. New events reuse the oldest slot once the 24-label pool wraps. The marker is one custom-drawn control. No feedback event allocates nodes.

### Statistics definitions and reset boundaries

`RangeStats` is node-free. Shots count actual `projectile_fired` launches, excluding rejected pool launches and dry fire. Hits count once when a launched projectile damages a dummy or rings steel. Ground, walls, props and bullets through a down dummy are misses. Accuracy is `100 * hits / shots`; headshot percentage is `100 * dummy head hits / all target hits`. Both read 0% for an empty denominator; armor-only head hits count as headshots. Steel contributes to hits but not headshots or TTK.

A physics-time clock supplies hit timestamps. Each dummy life has an independent first-damage timestamp, including armor damage; a killing hit completes that target's TTK. A one-hit kill is 0.000 s. The panel holds the last completed TTK until the next kill or stats reset. Target restore ends any open timer, and interleaved targets cannot overwrite each other's start time.

T (`range_stats_reset`) clears counters, active timers, completed TTK, marker and number labels. It does not change ammo, weapons or target state. The adapter clears eligibility for already-flying projectiles, so their subsequent real feedback is still shown but cannot produce hits in a new zero-shot session. Eligible slots are also removed on accepted hits and expiration and overwritten on reuse, keeping bookkeeping bounded by the projectile pool.

### Crosshair, readouts and audio

The crosshair's extra radius is `tan(current spread half-angle) * viewport height / (2 * tan(vertical FOV / 2))`, added to its base gap. It reads `RecoilLogic.spread_degrees()` including current bloom and uses the active camera's actual FOV. It hides at ADS blend 0.5 or when scoped; it never feeds aim or projectile logic. Ammo/reload/switch behavior is retained. Gameplay FPS and stats are in the HUD's layer 10, independent of the F3 diagnostics on layer 100.

Audio confirmation is non-spatial player feedback, separate from the existing spatial impact and steel sounds. Three cached chirps are generated by `SfxFactory.confirmation()` before any hit and played by three prebuilt players, each with bounded polyphony. A hit is a short downward chirp, armor break a longer high-to-low chirp, and kill a rising chirp. The original tone synthesis is described in `CREDITS.md`; no samples or binary assets were added.

### Complete Milestone 5 tuning reference

The defaults below live in scripts; change exported properties on the corresponding HUD child in `ui/hud.tscn` to override them. Times are seconds, lengths are pixels unless stated otherwise, and colors are RGBA.

| File / node | Values |
|---|---|
| `ui/hud.gd`, HUD root | `crosshair_hide_aim_blend = 0.5`; `fps_update_seconds = 0.25`; `stats_update_seconds = 0.2` |
| `ui/crosshair.gd`, Crosshair | `gap = 6`; `line_length = 8`; `thickness = 2`; `dot_size = 2`; `color = (1,1,1,0.9)`; `outline_color = (0,0,0,0.6)`; outline expansion is 2 px in drawing code |
| `ui/feedback_view.gd`, FeedbackView: marker | `marker_hold_seconds = 0.10`; `marker_fade_seconds = 0.18`; `marker_gap = 8`; `marker_length = 7`; `marker_thickness = 2`; `kill_length = 12`; `hit_color = (1,1,1,1)`; `armor_color = (0.25,0.65,1,1)`; `kill_color = (1,0.22,0.20,1)`; `marker_outline_color = (0,0,0,0.7)`; drawing code adds a 2 px outline |
| `ui/feedback_view.gd`, FeedbackView: numbers | `number_capacity = 24`; `number_lifetime = 0.8`; `number_rise_pixels_per_second = 36`; `number_horizontal_offset = 16` (alternating ±); `number_font_size = 22`; `number_outline_size = 4` (black); `number_color = (1,1,1,1)`; `headshot_color = (1,0.78,0.25,1)`; `roundi(amount)` sets displayed precision |
| `ui/feedback_audio.gd`, FeedbackAudio: hit | `hit_volume_db = -15`; `hit_start_hz = 1400`; `hit_end_hz = 1000`; `hit_seconds = 0.045` |
| `ui/feedback_audio.gd`, FeedbackAudio: armor break | `armor_volume_db = -11`; `armor_start_hz = 2300`; `armor_end_hz = 400`; `armor_seconds = 0.16` |
| `ui/feedback_audio.gd`, FeedbackAudio: kill | `kill_volume_db = -9`; `kill_start_hz = 1000`; `kill_end_hz = 1800`; `kill_seconds = 0.22` |
| `ui/feedback_audio.gd`, FeedbackAudio: pool | `polyphony = 4` per confirmation type |
| `weapons/effects/sfx_factory.gd`, `confirmation()` | Mix rate 22,050 Hz, 16-bit mono PCM; 0.003 s attack; `exp(-progress * 4)` decay; fundamental weight 0.7; overtone weight 0.3 at 1.5× frequency; frequency sweeps linearly from start to end |
| `ui/hud.tscn`, FPS | Right margin 28, top 18, width 122, height 24; font 16, outline 4 |
| `ui/hud.tscn`, Stats / Readout | Fixed panel: right margin 28, top 52, width 260, height 183; background `(0.035,0.045,0.055,0.78)`, corner radius 4; text inset 14 horizontally / 10 vertically, font 16, line spacing 5; percentages use 1 decimal and TTK 3 decimals in `Hud._refresh_stats()` |
| `ui/hud.tscn`, inherited Ammo / WeaponName | Ammo: right margin 28, bottom 22, width 312, height 46, font 32, black outline 6, white text. Weapon name: right margin 28, bottom 66, width 312, height 26, font 16, black outline 5, text `(0.86,0.88,0.9,1)` |
| `weapons/data/halberd_rifle.tres`, crosshair source | Hip / aimed spread 2° / 0°; bloom +0.15° per shot, cap 1.2°, recovery 4°/s after 0.12 s rest |
| `weapons/data/longwatch_sniper.tres`, crosshair source | Hip / aimed spread 4° / 0°; bloom +0° per shot, cap 0°, recovery 4°/s after 0.15 s rest |
| `project.godot`, input | `range_stats_reset`: T, physical keycode 84 |

### Readout update cost and verification

The first full-HUD firing runs averaged 59.7–59.9 fps, with 5–7 frames over 25 ms and 1% lows of 28–34 fps. An isolated HUD-off comparison held 60.0 fps, 55.9 fps 1% low and 18.15 ms worst, with no measured frame over 25 ms. Keeping the HUD visible but disabling only stats/FPS text updates likewise removed the measured hitches. This localized the cost to changing readouts rather than target feedback or the 3D scene.

Stats still record every event immediately. Display text is now dirty-flagged and refreshed at most every 0.2 s (5 Hz), with reset displayed immediately. Replacing the stats PanelContainer with a fixed Panel also avoids minimum-size/container relayout on each text change. No target feedback events are dropped; marker and number presentation still responds to each event.

Final standard firing probe, `godot --always-on-top -- --perf-probe --perf-fire`, 1280×720, Compatibility, all targets and full HUD active, window focused for 100% of measured frames:

| Average | 1% low | Worst frame | Frames over 25 ms | Draw calls / primitives |
|---|---|---|---|---|
| 60.0 fps | 55.2 fps | 18.32 ms | 0 of 601 | 166 / 3,014 |

Windowed startup completed with zero errors. Movie Maker captures were inspected for white hitmarkers, blue armor breaks, red kill Xs, amber headshot numbers, stats and TTK, plus the final fixed panel layout. Capture-only audio shutdown warnings match the earlier recorded Movie Maker limitation; normal windowed startup and the performance probe are clean. Human judgment of feedback timing, clutter, audio balance and distant readability remains pending; the step-by-step procedure is in README.

Final full headless GUT suite: **245/245 tests pass**, 4,558 assertions, with no errors or shutdown leaks. Coverage includes stats maths and resets, per-target TTK, authoritative damage-marker selection, in-flight reset boundaries, HUD reset input, spread projection / bloom recovery, feedback pooling / lifetime, confirmation sound data / selection, and bounded stats-display latency.

## Milestone 6: final MVP polish

### Capped pushable props and the existing bullet path

Eight props (four crates, four barrels) are built once near the firing line and test area. Their placement avoids the lane centres and movement obstacles. `PhysicsProp.receive_hit()` receives the same `ProjectileHit` dispatched by `TargetHits` for steel and dummies. The off-centre impulse is exactly bullet mass in kg times impact velocity; there is no additional raycast or overlap path. A 4 g rifle round at 850 m/s therefore applies 3.4 N·s, before ordinary damping and contacts.

After `move_and_slide()`, the player forwards rigid-prop contacts and its pre-slide velocity. Pushing is horizontal, capped by both `push_force * physics_delta` and the relative closing momentum. It cannot add vertical launch velocity or keep accelerating a prop already moving away faster than the player. Prop count is capped at eight, and a body below y = -10 m or beyond its home radius returns to its initial transform with velocities cleared. GUT checks both masses' bullet impulse, force-limited player pushing and actual swept-projectile dispatch.

### Pause, settings and mouse-free navigation

The range root explicitly uses `PROCESS_MODE_PAUSABLE`. Only `PauseMenu` uses `PROCESS_MODE_ALWAYS`; opening it pauses the SceneTree, leaving physics, projectile integration, player / weapon ticks, prop simulation, rail motion, ragdoll / target reset clocks, stats timestamps and in-game audio stopped. The renderer and menu still run. Tests check that gameplay tick counts, physical position, a live projectile and the range-stat clock remain unchanged during real elapsed menu time, then advance after resume. This freezes gameplay ticks, not the engine's global frame counter.

All added commands use InputMap actions. `pause` is Esc / controller Start, and UI accept / cancel / directions have explicit keyboard, A/B, D-pad and left-stick bindings. Resume receives focus on every open; vertical and Tab focus neighbours form a cycle, and the scroll container follows focus. Sliders adjust with Left/Right, checkbox / Resume activate with Enter, Space or A, and B cancels back to gameplay. The player's old Esc-only cursor release handler is replaced by this menu. Mouse recapture uses the existing fire action rather than a hard-coded mouse button. Menu transitions clear buffered fire/reload and fire / aim / reload / jump action presses so activating Resume does not act in-game.

`ViewSettings` remains the single persistence owner. Its existing `view` section in `user://settings.cfg` gains ADS sensitivity multiplier, master / effects volume and gameplay FPS visibility; legacy invert-Y and view values still load. Settings apply immediately and save on resume. `ConfigFile` preserves any other sections. Tests round-trip every preference through a separate config path and never overwrite the player's settings. ADS scaling is the per-weapon value multiplied by the global preference, blended from unscaled hip sensitivity.

A text AudioBusLayout defines Effects -> Master. All weapon, handling, impact, steel and HUD players use Effects, and ViewSettings controls both buses with linear gain; zero mutes. The FPS preference affects only the gameplay HUD, never F3 diagnostics. No native extension, OS subprocess, service or runtime path outside `user://` was introduced. Browser export and physical-controller validation remain future acceptance work, not claims made by this native MVP.

### Pooled ragdolls replace pop-downs

Ragdolls are enabled after passing the all-awake performance check below. Each dummy creates six frozen rigid bodies and five disconnected pin joints once at startup, reusing the existing hit-zone shapes and meshes. A killing shot disables live hit-zone collision, hides the standing silhouette, activates the parts at the exact hit-zone transforms, connects the pins and applies bullet momentum to the struck part. Moving targets contribute their carrier velocity. The ragdoll subtree is top-level/world-space, so the rail continues without dragging the corpse.

Ragdoll bodies use layer 4 and mask 1: they contact the world and props, while excluding player, projectile and corpse-to-corpse contacts. Adjacent joints also use the engine's connected-body collision exclusion. Only 54 ragdoll bodies / 45 pins can be active in the shipped nine-target layout. Connecting joints only after unfreezing avoids trying to constrain two static bodies; disconnecting before freezing avoids retaining unnecessary idle constraints.

At exactly 3 seconds of gameplay time, the parts freeze and hide, their collisions and velocities clear, and the original standing hit zones / armor / health return. No new nodes are allocated on kill or reset. Tests snapshot every original zone transform and layer and verify exact restoration, no extra nodes, killing momentum and separation from a moving rail. `ragdoll_enabled = false` retains the tested pop-down fallback, but is not the shipped default. The rig is deliberately greybox with pin joints rather than anatomical angular limits.

### Complete Milestone 6 tuning reference

This table covers newly introduced values and the existing view preferences exposed by the menu; prior milestone tables still describe unchanged movement, weapons and feedback.

| File | Values / policy |
|---|---|
| `range/range_builder.gd` | `prop_count = 8`, hard cap eight locations. Alternating crate / barrel locations (x,z), metres: (-18,1), (18,1), (-18,4), (18,4), (-6,12), (6,12), (-6,17), (6,17). Spawn y is half the corresponding height. |
| `props/physics_prop.gd` | Crate mass 8 kg, side 0.65 m; barrel mass 12 kg, radius 0.30 m, height 0.9 m, 12 radial mesh segments. `push_force = 60` N; `return_radius = 30` m; recycle below y = -10 m. Linear / angular damping 0.2 / 0.4 (combined with world damping). Collision layer / mask 1 / 3. |
| Same file, appearance | Crate color `(0.48,0.36,0.22,1)`, barrel `(0.28,0.36,0.32,1)`, roughness 0.85. |
| `player/view_settings.gd` | FOV default 65°, range 50–100°, hotkey step 5°. Sensitivity default 0.10 °/count, range 0.01–1.0, hotkey ratio 1.1. Invert-Y false. Head bob and FOV-kick scales both 1.0, range 0–2. ADS multiplier 1.0, range 0.1–2.0. Master / effects volume 1.0 / 1.0, range 0–1. Show FPS true. Storage `user://settings.cfg`, section `view`; linear gain floor 0.0001 for dB conversion, zero explicitly mutes. |
| `ui/pause_menu.gd`, slider increments | Sensitivity 0.01; ADS multiplier 0.05; FOV 1°; head bob / FOV kick 0.05; master / effects volume 0.05. Readouts use two decimals. Bounds are the ViewSettings ranges above. |
| Same file, layout / focus | Canvas layer 200; black shade alpha 0.65; centred panel 660×580 px; margins 20; row separation 10; title font 24; help font 14; setting-label minimum width 250; slider minimum 220×30; value width 60. Focus starts on Resume and wraps through nine controls. Scroll follows focus. |
| `project.godot`, added menu input | Pause: Esc (physical key 4194305), Start (button 6). Accept: Enter / Space, A (0). Cancel: Esc, B (1). Directions: arrows, D-pad 11/12/13/14 and left-stick axes 1/0 ±1; UI dead zone 0.5. Default Tab / Shift+Tab actions remain available. |
| `default_bus_layout.tres` | Master and Effects start at 0 dB; Effects sends to Master. Individual player volumes remain as authored in previous milestones. |
| `targets/target_dummy.gd` | `ragdoll_enabled = true`; carrier velocity from successive physics-tick positions. Live hit-zone transforms and materials remain the source of body geometry. |
| `targets/dummy_ragdoll.gd` | Masses in existing zone order (head, torso, left arm, left leg, right arm, right leg): 4 / 24 / 3 / 8 / 3 / 8 kg (50 kg total). `impulse_scale = 1.0`; linear / angular damping 0.25 / 1.0, combined with world damping. Active collision layer / mask 4 / 1; idle 0 / 0. |
| Same file, pins | Torso connects to part indices 0,2,3,4,5. Local anchors, metres: (0,1.49,0), (-0.27,1.43,0), (-0.14,0.88,0), (0.27,1.43,0), (0.14,0.88,0). Pins use engine defaults and connected-body collision exclusion. |
| `targets/data/dummy_default.tres` | Reset remains 3.0 s of gameplay time; fallback fold duration remains 0.15 s. |
| `debug/range_stress.gd` | Opt-in `--perf-stress`; `--perf-popdown` disables ragdolls only in that run. Re-kill damage 400, sniper projectile momentum at 900 m/s, torso point offset (0,0.1,0.1) m. Keeps rag parts awake with 0.005 N·m·s yaw impulses each tick; props get 8 m/s² rotating horizontal forcing at a 0.2 m lever, speed capped at 4 m/s; steel gets 0.03 N·m·s X torque impulses each tick. No fixture forcing runs in ordinary play. |
| `debug/perf_probe.gd` | Existing 2 s warmup / 10 s measurement, 50° yaw sweep / 4 s period and -4° pitch. Reports min/max awake ragdoll parts in every measured frame and count of stress props. |

### Performance pass, before / after and ragdoll decision

All measurements below are on the documented target Mac at 1280×720, Compatibility, full HUD and firing/reloads, with the window focused for 100% of measured frames. The stress fixture continually wakes all props and steel and immediately re-kills every dummy on restore, including activation/reset cost throughout the measurement. Ragdoll runs reported **54 min / 54 max awake parts**; this is not a test of already-sleeping corpses. The fixture applies no scoring shots for its synthetic kills.

| Configuration | Average | 1% low | Worst | Frames >25 ms |
|---|---|---|---|---|
| Before Milestone 6, Milestone 5 ordinary firing | 60.0 fps | 55.2 fps | 18.32 ms | 0 / 601 |
| Milestone 6 stress, pop-down baseline, eight moving props / steel | 60.0 fps | 37.0 fps | 27.39 ms | 23 / 601 |
| Initial all-ragdoll stress, capped | 60.0 fps | 43.9 fps | 28.58 ms | 1 / 602 |
| All-ragdoll stress, uncapped headroom | 115.4 fps | 70.6 fps | 15.09 ms | 0 / 1,156 |
| Final isolated all-ragdoll stress, capped | 60.0 fps | 49.0 fps | 21.92 ms | 0 / 601 |

The uncapped run had **zero frames over 16.67 ms**, keeping worst-case simulation/render work within the 60 fps budget. Ragdolls are retained. The final capped run had 166 draw calls / 3,012 primitives, eight continuously awake props, all 54 rag parts awake, three driven steel hinges and 83 fired rounds. Bounded prop count, pooled bodies, disconnected idle constraints, shared geometry and corpse collision filtering keep physics and allocation costs controlled; the earlier HUD refresh bound remains in force. No gameplay feedback or ragdoll feature was silently removed.

Capped runs are paced by the limiter rather than enforced OpenGL vsync. The earlier capped spikes also appeared in the pop-down baseline, whereas the uncapped all-ragdoll run stayed below 16.67 ms on every frame. Treat those as measured pacing variability rather than claiming that adding ragdolls made rendering faster. The final isolated run confirms the requested capped behavior; the table retains the earlier results instead of reporting only the best run.

### Final verification and future phases

**254/254 headless GUT tests pass**, 4,632 assertions, clean shutdown. Windowed startup and the final stress probe have zero errors. Movie Maker frames were inspected for the focused pause menu, props at the movement area and articulated ragdolls. The pause-menu capture retains the existing Movie Maker active-audio shutdown warning; ordinary startup and probes are clean. Final manual judgment is pending; README contains the numbered MVP checklist.

Web work still needs an actual browser export, physics/template validation, pointer-lock / audio activation gestures, persistence and browser performance tests. Menu controls have InputMap bindings and synthetic keyboard/controller event tests, but physical-device checks and full controller gameplay (right-stick look, mappings, dead zones, rebinding, prompts) remain post-MVP. No web-incompatible runtime service, native library or OS operation was added. The MVP uses simplified greybox ragdolls and capped recycling props rather than an unrestricted physics sandbox.

## Milestone 7 — weapon composition and attachments

### Preserve the Milestone 6 definitions

The existing guns remain independent `WeaponData` Resources, with no per-gun subclasses. Before refactoring, every original exported weapon stat and nested projectile stat was frozen in `tests/fixtures/milestone_6_weapon_stats.json`. `test_weapon_build.gd` compares both zero-attachment computed builds against that fixture, including packed recoil arrays, poses, sight geometry, sound settings and scene paths. New metadata does not replace or regenerate the fixture. All original tests remain in the suite, covering fire timing, recoil, reloads, zeroing, hits, damage, feedback and rendering state.

`WeaponData` composes three Resources:

- `FireModeData`: full-auto uses a held trigger; semi-auto / bolt / pump use a fresh press. Interval remains `max(60 / rpm, cycle_time)`. `weapons/framework/auto.tres` and `bolt.tres` select the existing rifle / sniper behavior.
- `DeliveryData`: `weapons/framework/ballistic.tres` delegates to the original `ProjectileSystem.fire`. Pellet, explosive and melee tags are declared, but their runtime implementations deliberately wait for Milestones 8–9; unsupported launches fail explicitly. There is no additional hit-detection path.
- `ReloadData`: `weapons/framework/magazine.tres` retains the existing tactical / empty timing and full-magazine refill. Single-round refill adds one, bounded by capacity; none disallows reloading. Interruptible shell reload is explicitly unsupported until Milestone 8.

`WeaponLoadout` names primary and secondary slots and validates roles / classes. Both existing guns are primaries, while the user requires both to stay playable now. Therefore only `weapons/data/range_loadout.tres` enables `comparison_mode = true`; the Resource default is false and ordinary loadouts reject primary / primary pairs. This preserves 1 / 2 and wheel behavior without misclassifying the sniper as a secondary. Remove the range exception when a real default secondary ships in Milestone 9.

### Deterministic cached builds and safe application

`WeaponBuild` holds immutable authored inputs and caches a separate computed `WeaponData`, independent projectile spec and copied recoil pattern. Base Resource identity keys viewmodels and sounds; snapshot identity never creates another gun model or another synthesized sound. One slot accepts one `AttachmentData`, which declares class compatibility, typed `StatModifier` entries, a part scene, mount path and optional optic settings. Class rules independently reject pistol barrel / stock and all rocket / knife / shield attachments, even if an attachment's compatibility array mistakenly includes them.

Build order is fixed: copy base stats; select optic overrides; apply every **ADD**, then every **MULTIPLY**. Within either pass use muzzle → barrel → optic → stock → magazine, then the modifier array's authored order. Keep intermediate values as floats; clamp once after stacking, then round magazine size once. Enforce falloff end ≥ start. For example `(850 + 50) × 1.1 = 990 m/s` regardless of installation order; `(30 + 0.4) × 1.5` rounds once to 46 rounds. Recoil scale multiplies both pattern entries and random deviation; it does not change the camera's cosmetic kick.

Only allowlisted scalar paths can be modified. Unknown fields, non-finite values and negative multipliers are rejected. `set_attachment` invalidates only a real selection change; `get_stats` returns the existing snapshot when unchanged. Authored Resources are treated as immutable: change selections through the build API, not by editing a fitted Resource in place at runtime. A computation counter makes this boundary testable.

The controller queues requests per weapon until ready / firing with the previous cooldown finished. Reloading, lowering, raising and bolt-cycle timing remain intact. Applying a batch computes once, preserves recoil state, clamps current bloom and loaded rounds only if necessary, and never grants rounds when capacity grows. It updates logic, view and audio through the existing weapon signal, and numerically recalibrates the zero using current air density. Already-flying rounds retain their original spec. Clearing all five slots is one batch; clearing an empty build is a no-op.

`DamageSource.Kind` adds BALLISTIC / PELLET / SPLASH / MELEE metadata. `ProjectileSpec.source` defaults to BALLISTIC; `ProjectileSystem` copies it to `ProjectileHit.source` on the existing swept-ray hit. Existing target damage and scoring semantics are unchanged. A real projectile-to-target integration test verifies metadata survives this path.

### Mounted parts and optics

The seventeen catalog Resources live in `weapons/attachments/data/`; [README's attachment table](../README.md#attachment-tuning-and-play-test) lists **every modifier, FOV, sight height and individual Resource filename**. There are three choices per physical slot and five optics, exceeding the suggested optic count to cover all five requested types. Every entry has both a benefit and a cost. Catalog order determines debug cycling, including None after the last compatible choice. Both existing weapons accept all five slots; optics / muzzle / magazines also declare future pistol compatibility.

Each viewmodel has `Mounts/{Muzzle,Barrel,Optic,Stock,Magazine}`. An attachment's local `Mount` marker is aligned with the corresponding weapon marker using an inverse transform. Cosmetic parts never determine projectile origins. Fitted optics detach the native sight nodes and None reattaches those exact nodes. This also preserves the MVP workaround for inherited visibility / physics-interpolation faults. Muzzle parts have an `Exit` marker for the existing flash; flash nodes are detached before an old part is freed, so repeated swaps retain effects without leaks. Node creation happens on selection / equip events, never per shot.

Optic FOV is authored as `degrees(2 × atan(tan(65° / 2) / magnification))`, with no small-angle approximation. The reference stays 65° even when a player changes hip FOV. Explicitly fitting an 8× scope therefore gives 9.106142756°, while **None retains the original sniper's 12°**; None also retains rifle 45° and both original sight heights / ADS poses. Fitted iron / red-dot FOV is 65°. Iron has physical sights, red dot uses a transparent red overlay, 2× a full crosshair, 4× ticks and 8× the original scope reticle. Only scopes hide the model. Head bob, recoil cosmetics and mount transforms remain separate from the calibrated bore direction.

Optic sight height is authored above the bore; the camera-relative ADS Y offset becomes `-sight_height_m - bore_height_m`. Bore heights are 0.010 m rifle / 0.012 m sniper, matching the unchanged model geometry. These values are explicit in the respective weapon Resources. Fixed authored geometry, rather than reading animated meshes, keeps zeroing deterministic.

### Complete new limits and presentation tuning

All clamp bounds below are in `weapons/attachments/data/stat_limits.tres` (`StatLimits`). `Vector2` stores the bounds as engine floats; tests use tolerance for decimal bounds such as 0.05. The operation order, integer rounding and min/max relation above are policies rather than hidden tuning.

| Stat | Minimum–maximum |
|---|---|
| `ads_time` | 0.05–1.5 s |
| `rounds_per_minute` | 30–1500 rpm |
| `bolt_cycle_time` | 0–3 s |
| `magazine_size` | 1–200 rounds |
| `reload_tactical_time`, `reload_empty_time` | 0.1–6 s each |
| `recoil_scale` | 0.25–2 |
| `hip_spread_degrees`, `aimed_spread_degrees`, `max_bloom_degrees` | 0–15° each |
| `spread_per_shot_degrees` | 0–5° |
| `recoil_recovery_rate` | 0–90°/s |
| `raise_time`, `lower_time` | 0.05–2 s each |
| `ads_fov_degrees` | 2–90° |
| `ads_sensitivity_scale` | 0.05–1 |
| `sight_height_m` | 0–0.5 m |
| `projectile.muzzle_velocity` | 50–1500 m/s |
| `projectile.damage` | 0–500 |
| `projectile.falloff_start_distance`, `projectile.falloff_end_distance` | 0–1000 m each |
| `projectile.min_damage_fraction` | 0–1 |

| File | New values / defaults |
|---|---|
| `weapons/weapon_data.gd` and `weapons/data/*.tres` | New default metadata: rifle class / primary role, recoil scale 1, iron optic kind 0, bore height 0.010 m. Sniper overrides class to sniper, optic kind to 4 and bore height to 0.012 m. Existing firearm stats are unchanged. |
| `weapons/attachments/attachment_data.gd` | Default part mount `Mount`; optic kind -1 inherits base, default fallback FOV 45° / sight height 0.050 m. Each catalog optic overrides all three values. `StatModifier` default operation MULTIPLY, value 1. |
| `weapons/framework/*.gd`, `*.tres` | Default full-auto / ballistic / magazine kinds. Auto fires while held; other modes require a press. Default comparison mode false; shipped range Resource explicitly true. Enum order is a stable data contract, not a tuning slider. |
| `weapons/viewmodels/halberd_rifle_viewmodel.tscn` | Muzzle `(0,0.010,-0.50)`; barrel `(0,0.010,-0.25)`; optic `(0,0.010,-0.01)`; stock `(0,-0.012,0.25)`; magazine `(0,-0.030,-0.04)`, metres. |
| `weapons/viewmodels/longwatch_sniper_viewmodel.tscn` | Muzzle `(0,0.012,-0.84)`; barrel `(0,0.012,-0.25)`; optic `(0,0.012,-0.01)`; stock `(0,-0.020,0.32)`; magazine `(0,-0.030,-0.03)`, metres. |
| `weapons/attachments/parts/{baffle,ported,compact_cap}.tscn` | Box cross-section 0.045×0.045 m, lengths 0.080 / 0.100 / 0.035 m; extend along -Z from mount, Exit at the end. |
| `weapons/attachments/parts/{long_barrel,short_barrel,heavy_barrel}.tscn` | Cross-section 0.035×0.035 m; lengths 0.350 / 0.180 / 0.300 m, extend along -Z. |
| `weapons/attachments/parts/{brace,light_stock,balanced_stock}.tscn` | Cross-section 0.060×0.100 m; lengths 0.220 / 0.160 / 0.200 m, extend along +Z. |
| `weapons/attachments/parts/{extended_mag,quick_mag,drum}.tscn` | Width 0.040 m, depth 0.065 m; heights 0.170 / 0.090 / 0.220 m, extend along -Y. |
| `weapons/attachments/parts/{iron,red_dot,scope_2x,scope_4x,scope_8x}.tscn` | Stem width / depth 0.018 / 0.035 m, height `optic sight height - 0.020 m`, centre at half stem height. Iron post 0.006×0.020×0.006 m, top at sight height. Red-dot sides 0.006×0.040×0.040 m at X ±0.021 m, centred at sight height; top 0.048×0.006×0.040 m at sight height +0.020 m. Scope radii 0.020 / 0.026 / 0.032 m, lengths 0.140 / 0.190 / 0.240 m, 12 radial segments / one ring, rotated X 90°, axis at sight height. |
| All part `.tscn` files above | Identity Mount transforms; roughness 0.8; shadows off. RGB by slot: muzzle `(0.24,0.27,0.30)`, barrel `(0.32,0.35,0.38)`, optic `(0.20,0.24,0.28)`, stock `(0.34,0.37,0.30)`, magazine `(0.35,0.32,0.24)`, alpha 1. Boxes centred at half their extension length. |
| `ui/hud.gd` | `red_dot_show_aim_blend = 0.85`; existing crosshair hide remains 0.5. Scope model hiding retains the existing WeaponView threshold 0.85. |
| `ui/scope_overlay.gdshader` | New `reticle_kind` default 4 preserves native sniper. Red RGB `(1,0.12,0.08)`; dot radius retains 0.0022 screen heights, alpha fade width 0.001. 2× line alpha 0.85 / existing half-width 0.0011; 4× tick spacing 0.05, phase offset 0.025, half-length 0.008, alpha 0.85. Native circle radius / gap / ring values unchanged. |
| `debug/attachment_debug.gd` | Canvas layer 11; physics priority -10 to collect requests before weapons; selection label offsets left 24 / top -155 / right 600 / bottom -24 px, top / bottom anchored to 1; font 14, outline 3. Label follows F3 visibility, refreshes only on selection / weapon changes. |
| `project.godot` | `attachment_muzzle/barrel/optic/stock/magazine`: F5–F9, physical codes 4194336–4194340; `attachment_clear`: F10, 4194341. Dead zone 0.2. All are InputMap actions and pause with gameplay. |

Debug choices are per weapon and session-only. Nothing writes a loadout file yet; `user://loadout.cfg` belongs to the Armory milestone. No new filesystem dependency, thread or native plugin was introduced into gameplay.

### Verification and performance

New coverage checks frozen zero-attachment stats, arithmetic order / clamps / integer rounding, compatibility, cache reuse, policy composition and source propagation, safe live changes, zero recalibration without mutating launched specs, all catalog trade-offs, every optic's zoom / sight height / model state, red-dot HUD behavior, and F5–F10 fitting / clearing with surviving muzzle effects. The original Milestone 6 tests remain unchanged in intent.

Final full headless GUT run: **269/269 tests, 4,997 assertions, 119.698 s**, clean shutdown with no engine errors. The frozen-fixture comparison proves both computed bare builds retain every original Milestone 6 stat; existing integration tests continue proving their behavior.

Windowed normal startup and the final performance run shut down with zero errors. Movie Maker frames were inspected for the fitted hip model, aligned red-dot ADS and 4× scope / tick reticle. Choices in those captures were baffle / long barrel / red dot (or 4×) / braced stock / extended magazine. Captures and test drivers are temporary files outside the repo.

All figures below use the target Intel Mac, Compatibility, 1280×720, firing with the HUD / diagnostics, eight continuously moving props, three driven steel plates and all **54 min / 54 max** ragdoll parts awake. Each probe measures ten seconds after two seconds of warmup. No tests, captures or commits ran concurrently. Final probes used a temporary SceneTree driver to fit all five parts and restore foreground focus when lost; shipped game focus handling is unchanged.

| Configuration | Focus | Average | 1% low | Worst | Frames >25 ms |
|---|---|---|---|---|---|
| Milestone 6 final capped, historical reference | 100% | 60.0 fps | 49.0 fps | 21.92 ms | 0 / 601 |
| Milestone 6 uncapped, historical reference | 100% | 115.4 fps | 70.6 fps | 15.09 ms | 0 / 1,156 |
| Milestone 7 capped, five parts / fitted irons via debug actions | 100% | 60.0 fps | 42.7 fps | 31.90 ms | 2 / 601 |
| Milestone 7 uncapped, five parts / red dot, foreground driver | 100% | 91.3 fps | 55.4 fps | 19.61 ms | 0 / 914 |
| Milestone 7 final capped, five parts / red dot, foreground driver | 100% | 60.0 fps | 42.6 fps | 30.46 ms | 2 / 600 |

Two preliminary uncapped attempts lost focus (0% and 18%) and are excluded from acceptance comparisons. The valid uncapped run measured 12 / 914 frames above 16.67 ms, median 10.66 ms, with 189 draw calls / 3,906 primitives at the final sample. The final capped run had 190 draw calls / 4,014 primitives and 75 shots. Render counts vary with the ragdoll / prop poses and particles at the sample time. All five fitted parts and the diagnostic selection label add work relative to the MVP; builds themselves never recompute per frame.

The range still averages the requested 60 fps capped, with substantial average uncapped headroom. **This is not a claim that every frame meets 16.67 ms:** uncapped tail frames and two capped pacing spikes remain. The historical MVP table is a reference, not a controlled thermal comparison. Preserve this limitation for the final-arsenal performance pass rather than hiding it behind the average or claiming a nonexistent optimization.

### Recommendations for the remaining Phase 2 plan

1. At the start of Milestone 8, add a logical `shot_id` shared by all pellets / impacts from one trigger event. Route existing hit metadata through that ID so stats count one hit per shot and damage numbers combine per target / shot before pellet delivery ships. `source` alone cannot provide grouping.
2. Keep pump timing and interruptible shell reload state separate from the animation milestone. Build their deterministic gameplay timelines first; Milestone 10 should consume them without driving ammo or damage.
3. When Milestone 9 supplies secondaries, choose a real default secondary and disable the range's explicit comparison exception. Do not reclassify the sniper to satisfy the slot rule.
4. Milestone 11 should edit selections through the existing build boundary and preview independent snapshots. Add stable attachment-ID persistence / validation there; keep authored Resource inputs immutable. Use the same fixed FOV reference in Armory magnification labels.
5. Keep a full-slot assembly in Milestone 12's arsenal stress matrix, including high-zoom ADS, pellet bursts and splash. Budget total draw calls and contacts together; the current tail measurements justify retaining that explicit check.

## Milestone 8 — new primaries, pellets and shell reloads

### One logical shot, independent pooled projectiles

The three new primaries are composed Resources: **Rill S-4** (SMG), **Foundry L-8** (LMG) and **Breakwater P-6** (pump shotgun). There are no gun subclasses or alternate target-hit paths. A pellet is a normal pooled projectile with its own RK4 gravity/drag integration and original swept raycast; `DamageSource.PELLET` follows the existing target interface and zone / armor rules.

`ProjectileSystem` now assigns a monotonic `shot_id` to every successful single shot or volley. Pool-slot IDs remain independent and reusable. `fire_volley` validates every direction and checks capacity before launching, so it emits all eight pellets or rejects the whole volley. Rejected volleys do not count as shots and increment dropped-projectile count by the requested count. Group metadata is bounded by live projectiles and released after the final impact / expiry. Completion is emitted after damage callbacks, so downstream consumers can finish a group without losing its last hit.

Stats listen to `shot_started`, deduplicate hits by shot ID and retain eligibility only until `shot_finished`. Reset discards eligibility for all old groups. One shotgun shell counts as one shot and at most one hit, even if several zones / targets or steel are struck. Any head pellet promotes the shot's headshot flag once, so headshot percentage remains ≤100%. Each damaged target still receives its own first-damage / kill timer, independent of whether the shot has already scored a hit elsewhere. Original single-projectile behavior is retained, including old-round exclusion after reset.

Pellet damage presentation aggregates by `(shot_id, target instance ID)`. The existing 24-label pool updates one keyed label as more pellets arrive, including across physics ticks; it does not wait for misses to expire. Values sum zone-adjusted incoming damage and round once for display. Any contributing head pellet makes the number amber. A target already killed continues to reject later pellets through the existing target interface. Marker / confirmation events for one dummy/shot emit on the first hit and on priority upgrades (armor break / kill), avoiding eight identical hit chirps. Physics damage remains immediate; UI aggregation never determines damage.

`ConeSpread.sample` extracts the original recoil-cone algorithm without changing its random draws: polar angle `half_angle × sqrt(U)` and uniform azimuth. Ballistic weapons retain their exact seeded behavior. Pellet delivery consumes eight further samples from the same per-controller RNG, around the already calibrated and spread-adjusted bore direction, before this shot's recoil applies. Its intrinsic cone remains present while ADS; the hip crosshair displays the sum of weapon spread / bloom and pellet half-angle as an envelope.

### Shell phases and sprint recovery

`WeaponLogic` owns START → INSERT → FINISH phases for shell reloads. START and FINISH use the reload policy Resource's opening / closing times. The first INSERT uses the gun's empty or tactical reload time according to current ammo; later inserts use the tactical time. Each completed INSERT credits exactly one shell and emits `shell_inserted`. Partial inserts credit nothing. Large time steps carry their remainder through phase boundaries; normal gameplay remains at 60 Hz.

A fresh pump trigger press while loading requests interruption. With a loaded shell, the current partial insert is discarded and FINISH begins. While empty, the press remains queued until the first shell completes, then FINISH runs. On closing, the queued press fires once through ordinary readiness / sprint / pump gates. Holding a pump trigger never repeats shots. Lowering cancels the reload and queued press while retaining completed shells. Reload pressed during the 0.8 s pump cycle still waits for that cycle; interruption cannot bypass it. HUD reads `LOADING n / capacity`; a cached existing handling click accompanies inserts. Detailed pump / shell hand animation remains Milestone 10 work.

The new `WeaponData.sprint_to_fire_time` defaults to zero, preserving both MVP guns. Each sprinting tick refreshes the authored delay; after sprint ends it counts down in physics time before fire can resume. Rill / Foundry / Breakwater use 0.10 / 0.35 / 0.20 s. The field is allowlisted and clamped to 0–2 s in `weapons/attachments/data/stat_limits.tres`; existing attachment modifiers otherwise remain unchanged.

### Two carried slots, cached range offerings

`WeaponCatalog` separates available definitions from the two carried loadout slots. `WeaponRuntime` holds a cached build, logic and recoil state per offered gun. Models and synthesized sounds are created once per definition, while only the current model is in the scene. P (`primary_next`, physical code 80, dead zone 0.2) exchanges slot 1 through normal lowering / raising. 1 / 2 and the wheel retain their two-slot behavior. Gun state survives exchange without refill; pending attachment requests are keyed by definition, so a queued SMG magazine cannot accidentally apply to an LMG newly installed in the same slot.

Catalog order in `weapons/data/primary_catalog.tres` is Halberd, Rill, Foundry, Breakwater, Longwatch. The range's explicit comparison loadout already carries Longwatch in slot 2, so the primary cycle excludes that duplicate and cycles the first four. The selector uses stable catalog order rather than current-slot order; repeated cycling reaches every offered gun. Requests can be cancelled by selecting the original gun or choosing a carried slot during lowering. Default startup stays Halberd / Longwatch, and the frozen Milestone 6 stat fixture is unchanged. No Armory UI or persistence is introduced ahead of Milestone 11.

The F3 selection label gains a P primary line and moves its top offset from -155 to **-180 px**; other label settings retain Milestone 7 values. The three new models use the same five mount paths as the existing guns and geometry-derived 0.050 m sight height above a 0.010 m bore. Fitted optics retain the existing authored FOV / height / ADS-pose calculation. All seventeen attachments fit each new primary. Reload-speed modifiers scale shell insertion times; policy opening / closing times remain fixed. Capacity modifiers change tube capacity without granting shells.

### Complete new weapon tuning reference

Columns below correspond to `weapons/data/rill_smg.tres`, `weapons/data/foundry_lmg.tres`, and `weapons/data/breakwater_shotgun.tres`. They are the gameplay and cosmetic tuning authority. Values are bare, before attachments. All three use primary role, default target multiplier class, unscoped native iron presentation, gravity scale 1, and the unchanged range air density / target settings.

| Field / units | Rill S-4 | Foundry L-8 | Breakwater P-6 |
|---|---|---|---|
| Weapon class / fire / delivery / reload | SMG / auto / ballistic / magazine | LMG / auto / ballistic / magazine | shotgun / pump / pellet / shell |
| Rate, rpm / cycle, s | 900 / 0 | 700 / 0 | 75 / 0.80 |
| Velocity, m/s | 400 | 850 | 400 per pellet |
| Projectile damage | 24 | 30 | 18 per pellet (144 for eight torso pellets) |
| Falloff start / end, m | 25 / 75 | 60 / 250 | 15 / 40 |
| Minimum damage fraction | 0.35 | 0.75 | 0.20 |
| Bullet mass, g / diameter, mm / Cd | 8 / 9 / 0.32 | 8 / 7.2 / 0.30 | 3.5 / 8.4 / 0.45 |
| Lifetime, s | 3 | 3 | 1.5 |
| Source | ballistic | ballistic | pellet |
| Zero, m / sight height, m / bore Y, m | 100 / 0.050 / 0.010 | 100 / 0.050 / 0.010 | 25 / 0.050 / 0.010 |
| Capacity | 32 | 100 | 6 |
| Tactical / empty reload, s | 1.50 / 2.00 | 4.20 / 5.00 | 0.55 / 0.85 per insert |
| ADS time, s / FOV, degrees / sensitivity | 0.18 / 50 / 0.80 | 0.48 / 45 / 0.60 | 0.30 / 55 / 0.75 |
| Raise / lower / sprint recovery, s | 0.28 / 0.22 / 0.10 | 0.80 / 0.55 / 0.35 | 0.45 / 0.35 / 0.20 |
| Recoil scale / aimed recoil scale | 1 / 0.85 | 1 / 0.45 | 1 / 0.85 |
| Random recoil ±(yaw,pitch), degrees | (0.16,0.10) | (0.20,0.12) | (0.30,0.25) |
| Recoil loop length | 6 | 8 | 3 |
| Recovery delay, s / rate, degrees/s / pattern reset, s | 0.10 / 11 / 0.22 | 0.15 / 8 / 0.35 | 0.20 / 10 / 0.60 |
| Hip / aimed spread half-angle, degrees | 2.5 / 0.10 | 3.5 / 0.15 | 1.5 / 0 (plus intrinsic pellet cone) |
| Bloom per shot / maximum, degrees / recovery, degrees/s | 0.12 / 1.4 / 5 | 0.10 / 1.6 / 3 | 0.40 / 0.8 / 4 |
| Hip pose, m | (0.17,-0.17,-0.42) | same | same |
| ADS pose, m | (0,-0.060,-0.38) | same | same |
| Cosmetic kick back, m / pitch, degrees | 0.025 / 1.2 | 0.050 / 2.0 | 0.080 / 4.0 |
| Shot sound pitch, Hz / duration, s | 160 / 0.15 | 90 / 0.28 | 65 / 0.40 |

Recoil patterns are `(yaw,pitch)` in degrees, in the respective weapon Resources; the complete pattern loops after its final entry:

- Rill: `(0,0.32), (0.08,0.38), (0.12,0.42), (-0.06,0.38), (-0.14,0.35), (0.05,0.32)`.
- Foundry: `(0,0.70), (0.10,0.75), (0.18,0.80), (0.12,0.75), (-0.08,0.70), (-0.15,0.65), (-0.10,0.60), (0.05,0.60)`.
- Breakwater: `(0.15,2.80), (-0.10,3.00), (0.05,2.90)`.

`weapons/framework/pellet.tres` selects eight pellets and a **3°** intrinsic half-angle; `DeliveryData` authoring defaults are likewise 8 / 3°, with inspector ranges 1–32 pellets / 0–15°. `weapons/framework/shell.tres` sets opening / closing to **0.20 / 0.20 s** (also the `ReloadData` defaults, inspector ranges 0–2 s each). `pump.tres` selects pump-action gating. The empty native shotgun reload totals `0.20 + 0.85 + 5 × 0.55 + 0.20 = 4.0 s`; a tactical top-up takes opening + missing shell count × 0.55 + closing. The original guns retain sprint recovery zero and all original stats.

### New model geometry tuning

All geometry lives in `weapons/viewmodels/{rill_smg,foundry_lmg,breakwater_shotgun}_viewmodel.tscn`. Eight shadowless BoxMesh parts use metal RGB `(0.16,0.17,0.19)`, roughness 0.8, and polymer `(0.30,0.31,0.27)`, roughness 0.9, alpha 1. All positions / dimensions below are metres. Receiver is centred at zero; each barrel centre has Y 0.010. Native rear sight is a 0.030×0.022×0.020 metal box at `(0,0.046,0.070)`; front post is 0.006×0.030×0.006 at Y 0.045. The tip therefore remains 0.050 above the bore. Polymer grip is 0.030×0.085×0.040 at `(0,-0.070,0.090)`.

| Geometry | Rill | Foundry | Breakwater |
|---|---|---|---|
| Receiver size | (0.045,0.065,0.20) | (0.075,0.090,0.40) | (0.055,0.075,0.28) |
| Handguard size / centre Z | (0.042,0.050,0.13) / -0.16 | (0.065,0.065,0.30) / -0.32 | (0.065,0.065,0.24) / -0.27 |
| Barrel size / centre Z | (0.018,0.018,0.10) / -0.27 | (0.030,0.030,0.24) / -0.58 | (0.035,0.035,0.38) / -0.43 |
| Stock size / centre Z | (0.035,0.055,0.15) / 0.16 | (0.065,0.080,0.25) / 0.30 | (0.050,0.070,0.24) / 0.27 |
| Magazine size / centre Y,Z | (0.027,0.15,0.035) / -0.095,-0.025 | (0.14,0.16,0.13) / -0.095,-0.040 | (0.028,0.028,0.40) / -0.035,-0.28 |
| Front post centre Z | -0.21 | -0.45 | -0.44 |
| Muzzle / muzzle mount Z | -0.32 | -0.70 | -0.62 |

Handguards use Y -0.005; stocks Y -0.012. All listed parts have X 0 and identity rotation. Muzzle markers use `(0,0.010,Z above)`; barrel mounts `(0,0.010,handguard Z)`; optic mounts `(0,0.010,-0.010)`; stock mounts the stock centre; magazine mounts `(0,-0.030,magazine Z)`. Mount parents have identity transforms. Attachments reuse the existing Milestone 7 parts and tuning unchanged. No binary models or sounds were added; existing CREDITS coverage remains accurate.

### Performance tooling and measured results

`debug/perf_probe.gd` accepts `--perf-weapon=rifle|smg|lmg|shotgun` together with the existing probe / firing flags. It selects through the same primary exchange API used by P, drives InputMap fire edges for pump guns and interrupts shell loading when a round is ready. This keeps an enlarged tube from spending most of a short measurement loading. Auto guns retain held fire. Physics priority is -20; all probe processing is disabled in ordinary play. The report adds selected gun, peak simultaneous projectiles and dropped count. Its printed collision-hit count is per projectile and includes scenery; the HUD's accuracy still uses deduplicated logical target hits.

The existing 2 s warmup / 10 s measurement and 60 Hz gameplay tick are unchanged. All five attachment actions are pressed at 1.5 s, after equip and before measurement: baffle / long barrel / fitted irons / braced stock / extended magazine. Larger capacities receive no free rounds, so initial native ammo remains. The projectile pool stays capped at 128.

Target Intel Mac, Compatibility, 1280×720, full HUD / diagnostics, all 54 ragdoll parts awake throughout, eight continuously forced props and three driven steel hinges. Each accepted capped run was focused for 100% of measured frames. Probes ran in isolation from tests / imports / captures / commits; a temporary external SceneTree driver restored foreground focus without altering shipped focus behavior.

| Run | Average | 1% low | Worst | Frames >25 ms | Peak projectiles / dropped |
|---|---|---|---|---|---|
| Milestone 7 fitted rifle, historical reference | 60.0 fps | 42.6 fps | 30.46 ms | 2 / 600 | not recorded |
| Milestone 8 fitted Rill | 60.0 fps | 52.0 fps | 20.21 ms | 0 / 601 | 14 / 0 |
| Milestone 8 fitted Foundry | 60.0 fps | 40.6 fps | 29.45 ms | 3 / 601 | 36 / 0 |
| Milestone 8 fitted Breakwater | 60.0 fps | 52.1 fps | 21.03 ms | 0 / 601 | 8 / 0 |

The runs fired 102 / 100 / 9 logical shots respectively. Final sampled draw calls / primitives were 189 / 4,134, 168 / 3,400 and 186 / 3,800; counts depend on the sampled particle / ragdoll pose. Breakwater generated 72 physical collisions from its nine eight-pellet shots while also exercising interrupted shell loading. A separate uncapped Foundry diagnostic averaged 120.2 fps but had only 89% focused frames, so it is excluded from acceptance and headroom comparisons.

The capped 60 fps average is retained across all three new primaries. This is not a strict per-frame 16.67 ms floor: Foundry retains three capped pacing spikes, comparable to the existing Milestone 7 tail behavior. Keep those tails in the final arsenal performance matrix; these historical rows are not a controlled thermal before/after optimization claim. Bounded live projectiles, per-shot bookkeeping, cached gun state and pooled labels keep the added work limited.

### Verification and remaining scope

The full arsenal suite covers the original frozen stat comparisons and regression tests plus shot grouping, cross-tick / multi-target totals, stats reset with reused slots, pool exhaustion / expiry, keyed-label eviction, seeded pellet count / speed / cone, vertical aim, every shell phase / cancellation path, sprint recovery and pump cooldown. Each new gun is tested for timing, magazine / reload, real projectile-to-target delivery, all attachment compatibility and authored sight geometry. Range integration tests cover P order, two-slot count, preserved ammo / attachments, definition-keyed pending changes, cancelled exchanges, cached models / sounds / stats, eight pellets per shell and loading HUD.

Final full headless GUT run: **297/297 tests, 5,713 assertions, 144.681 s**, clean shutdown with no engine errors. The loading HUD also checks the shell phase, so the cancellation signal clears `LOADING` immediately before the lowering state transition. Its regression test checks the readout while the shotgun is still displayed, not after a different gun replaces it.

Headless and normal windowed boot complete without errors. Movie Maker hip / ADS frames were inspected for all three new native models. A close shotgun capture shows one 108-point torso total on the killing shot, a red X, ammo 5 / 6, shots 1 / hits 1, accuracy 100%, headshots 0% and TTK 0.000 s. The remaining pellets are ignored after the existing target death transition, explaining 108 rather than 144 on that unarmored target. The armored real-delivery test separately verifies all eight torso pellets sum to 144.

Manual judgment of recoil, sound balance, pellet-cone feel and handling remains pending; README has the numbered checklist. Detailed reload / pump animations remain Milestone 10, Armory / saved loadouts Milestone 11, and secondary delivery / weapons Milestone 9. Menu controller bindings remain available; full controller gameplay and a browser export are still future work.


## Primary cycling key after Milestone 8

Move `primary_next` from F11 to **P** (physical keycode 80) because macOS intercepts F11 for desktop controls. P is otherwise unused. The InputMap action, two-slot behavior and per-gun session state remain the same. The F3 hint and README controls now show P. Primary-selection integration tests pass 6/6, including cycling with physical P events; headless startup is clean.

## Milestone 9: secondaries and strict loadouts

### Composition and shared damage reporting

The four secondary definitions compose the existing policies: Wayline is semi / ballistic / magazine; Cairn is semi / explosive / single-round; Latch and Palisade are semi / melee / none. `WeaponData` adds `uses_ammo=true`, `can_aim=true` and `movement_speed_scale=1` defaults, plus an optional `GuardData`. Knife / shield override ammo and ADS off. Their unused carrier projectile fields never create a simulated bullet. Every original rifle / sniper stat remains unchanged; regression scenes explicitly request `tests/fixtures/mvp_loadout.tres` rather than depending on the range's new production loadout.

`weapons/data/range_loadout.tres` now disables comparison mode and carries Halberd / Wayline. Primary catalog order remains Halberd, Rill, Foundry, Breakwater, Longwatch; P now reaches all five because Longwatch is no longer carried as a secondary. `weapons/data/secondary_catalog.tres` offers Wayline, Cairn, Latch, Palisade. O exchanges slot 2 using the same lower / raise pipeline as P. Exactly two slots remain carried, with one runtime cache per offered definition. Ammo, recoil, built stats and attachments survive exchanges. The last requested replacement wins, including cancellation and cross-slot requests; role checks reject putting a secondary in the primary slot or vice versa. No Armory or loadout persistence is introduced early.

Rockets use the original pooled RK4 integrator, drag and swept ray. `TargetHits` routes an explosive contact to `ExplosionSystem` rather than adding direct contact damage. A rocket arms at **travelled path length ≥10 m**; earlier contacts are duds. Expiry is not an airburst. Armed contact queries a sphere, deduplicates each dummy and applies damage to its torso through the original target interface. Armor order, exact plate breaks, health overflow, death, feedback, timers and reset remain target responsibilities. One rocket can damage several dummies but scores one hit; splash cannot score a headshot.

`ExplosionData` sets full damage / impulse through 1 m and linear falloff to zero at 6 m: `f = clamp((6-distance)/5,0,1)`, capped at 1 inside the inner radius. Damage is **180 × f** and impulse **45 N·s × f**, using torso centre / rigid-body origin distance respectively. A reused visibility ray starts 0.02 m off the struck surface; world geometry and shields can occlude damage / impulse. Newly killed ragdoll parts join the same deduplicated impulse pass, so they receive radial force once, without duplicate contact momentum. Already active ragdolls, props and steel receive outward impulse; frozen bodies are skipped. Coincident body origins use upward impulse. Indirect steel impulses do not fabricate a direct ring or scoring target hit.

`MeleeSystem` owns one reused camera `ShapeCast3D`. A swept sphere selects the nearest contact; its radius is included in the authored reach. Walls and shields block contact, and the player's own shield RID is excluded only for that strike. A swing or whiff opens and closes the existing logical-shot lifecycle without occupying a projectile slot. Contact emits the same `projectile_hit` signal with source `MELEE`, slot -1 and an explicit momentum override. Target zones, props, steel and ragdolls use the existing handlers; `ProjectileHit.momentum()` otherwise retains bullet mass × velocity exactly. A fresh press is required after the 0.5 / 0.9 s cooldown. No ammo, reload, ADS or muzzle flash is produced for melee.

The shield's reusable `WeaponGuard` is an `AnimatableBody3D` on layer 8, following fixed-tick gameplay eye / aim independently of cosmetic bob or kick. It blocks direct frontal projectiles while ready or bashing; it is inactive during raising, lowering or holstering. Its finite box leaves the sides exposed. The default projectile collision mask becomes `1|8`; existing world / zone collisions remain on layer 1. The contact cast also uses `1|8`, margin 0. The blast query uses `1|4|8` (live zones / world, ragdolls, shield), while its visibility ray uses `1|8`, so corpses do not block splash. The blast candidate cap is **128** (authoring range 16–256), above the range's bounded actor count even with all 54 parts active. Contact result cap is 8 (range 1–32).

Movement scales walk, crouch, sprint, slide thresholds / boost / maximum / decay and air target speed by the held weapon's multiplier. Equipping the shield immediately reduces existing horizontal momentum by 0.8; switching away restores normal speed targets without granting a velocity boost. Vertical motion is unchanged. At steady state its walk / crouch / sprint speeds are **3.60 / 1.76 / 5.60 m/s**. The `movement_speed_scale` authoring range is 0.1–1; other guns remain at 1.

### Complete secondary tuning reference

Columns correspond to `weapons/data/wayline_pistol.tres`, `cairn_launcher.tres`, `latch_knife.tres`, `palisade_shield.tres`. All are secondary-role, semi-auto press gated, native irons / unscoped, recoil scale 1. Target multipliers remain head 1.5, torso 1, limbs 0.8; only Longwatch retains the sniper head multiplier 2. All physical units are SI except the explicitly labelled grams / millimetres.

| Field / units | Wayline P-15 | Cairn R-1 | Latch K-1 | Palisade S-1 |
|---|---|---|---|---|
| Class / delivery / reload | pistol / ballistic / magazine | rocket / explosive / single-round | knife / melee / none | shield / melee / none |
| Uses ammo / can aim / movement scale | true / true / 1 | true / true / 1 | false / false / 1 | false / false / 0.8 |
| Velocity, m/s | 360 | 120 | 50 unused | 50 unused |
| Gravity scale / lifetime, s | 1 / 3 | 0.15 / 6 | 0 / 0.1 unused | 0 / 0.1 unused |
| Projectile / contact damage | 28 | 0 (180 radial blast only) | 75 | 40 |
| Distance falloff start / end, m / minimum | 20 / 75 / 0.4 | 0 / 0 / 1 unused | 0 / 0 / 1 | 0 / 0 / 1 |
| Mass, g / diameter, mm / Cd | 8 / 9 / 0.3 | 1500 / 80 / 0.06 | 4 / 5.7 / 0 unused | 4 / 5.7 / 0 unused |
| Source | ballistic | ballistic impact → splash damage | melee | melee |
| Rate, rpm / cycle, s | 400 / 0 | 60 / 0 | 120 / 0.5 | 66.666666667 / 0.9 |
| Zero, m / sight height, m / local bore Y, m | 50 / 0.035 / 0.008 | 50 / 0.100 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Capacity | 15 | 1 | 1 unused; HUD MELEE | 1 unused; HUD MELEE |
| Tactical / empty reload, s | 1.25 / 1.65 | 2.4 / 2.8 | 0.1 / 0.1 unused | 0.1 / 0.1 unused |
| Raise / lower / sprint recovery, s | 0.18 / 0.16 / 0.08 | 0.65 / 0.45 / 0.30 | 0.22 / 0.18 / 0.10 | 0.45 / 0.35 / 0.20 |
| ADS time, s / FOV, degrees / sensitivity | 0.16 / 55 / 0.8 | 0.42 / 45 / 0.55 | 0.2 / 65 / 1 unused | 0.2 / 65 / 1 unused |
| Pattern (yaw,pitch), degrees | (0,0.7), (0.12,0.8), (-0.08,0.75) | (0,2.5) | (0,0) | (0,0) |
| Random recoil ±(yaw,pitch), degrees | (0.15,0.12) | (0.15,0.20) | (0,0) | (0,0) |
| Pattern loop / aimed recoil scale | 3 / 0.85 | 1 / 1 | 1 / 1 | 1 / 1 |
| Recovery delay, s / rate, degrees/s / reset, s | 0.12 / 14 / 0.25 | 0.20 / 10 / 1 | 0.10 / 10 / 0.5 | 0.10 / 10 / 0.5 |
| Hip / aimed spread half-angle, degrees | 2.8 / 0.1 | 1.5 / 0 | 0 / 0 | 0 / 0 |
| Bloom per shot / max, degrees / recovery, degrees/s | 0.2 / 1.5 / 6 | 0 / 0 / 4 | 0 / 0 / 4 | 0 / 0 / 4 |
| Hip pose, m | (0.17,-0.17,-0.35) | (0.23,-0.20,-0.50) | (0.18,-0.22,-0.42) | (0,-0.25,-0.60) |
| ADS pose, m | (0,-0.043,-0.26) | (0,-0.10,-0.45) | same as hip, unused | same as hip, unused |
| Cosmetic kick back, m / pitch, degrees | 0.035 / 2 | 0.12 / 4 | 0.02 / 1 | 0.025 / 0.8 |
| Shot / swish pitch, Hz / duration, s | 170 / 0.18 | 65 / 0.35 | 240 / 0.20 | 120 / 0.25 |

Pistol raise and lower are individually faster than every other weapon. Rocket reload has no staged animation yet; empty single-round refill follows the authored 2.8 s time. `ProjectileSpec` inspector mass / diameter maxima expand from 100 g / 20 mm to **5000 g / 200 mm** to allow the rocket, without changing any existing projectile values or attachment clamps. `stats_eligible=true` is the projectile default; only training rounds override it. Ballistic fields marked unused above are inert carrier metadata, retained to keep one shared damage event type.

The rocket's `blast` sub-resource explicitly sets arming 10 m (range 0–100), radius 6 m (0.1–20), inner radius 1 m (0–20), damage 180 (0–500), impulse 45 N·s (0–200), occlusion true and surface offset 0.02 m (0.001–0.1). These are also `ExplosionData` authoring defaults. `knife_contact.tres` / `bash.tres` set reaches **1.8 / 1.5 m**, cast radii **0.12 / 0.18 m**, impulses **6 / 12 N·s**, results **8 / 8**. Contact authoring defaults are the knife's values; reach range 0.1–3 m, radius 0.01–0.5 m, impulse 0–50 N·s. Actual radius is capped at half the reach, preserving the total reach even for a very short authored strike.

`weapons/data/palisade_guard.tres` matches `GuardData` defaults: **size (0.65,1.25,0.08) m**, eye offset **(0,-0.25,-0.60) m**, collision layer **8**; collision mask 0, no player pushing body. Pistol compatibility is limited to muzzle / optic / magazine; all seventeen existing attachment trade-offs stay unchanged. Rocket / knife / shield reject all attachments. Fitted pistol optics use the existing geometry-based ADS height and numerical zero recalibration. Melee zero distance 0 explicitly skips calibration.

### Feedback, controls and bounded effects

`weapons/effects/explosion_effects.gd` reads projectile slots without any physics query. It draws rockets in one shadowless BoxMesh MultiMesh sized to the existing 128-projectile pool. Blast flashes use one further MultiMesh and an eight-slot ring pool, overwriting the oldest on overflow. Four spatial boom voices are created once. Processing sleeps when no rocket / flash is active; ordinary bullets do not wake it. Pause inherits the range's pausable process mode. Hit / armor / kill chirps, damage numbers and logical-shot stats still come only from actual target damage.

| Cosmetic tuning in `explosion_effects.gd` | Value |
|---|---|
| Rocket size, m / RGB | (0.06,0.06,0.30) / (0.85,0.55,0.15) |
| Flash capacity / lifetime | 8 / 0.30 s |
| Flash radius fraction of gameplay radius / initial radius | 0.35 / 0.15 m |
| Flash RGBA | (1,0.4,0.08,0.45), alpha decreases linearly to zero |
| Flash geometry | unit sphere, radius 1 / height 2 m, 8 radial segments / 4 rings; double-sided, unshaded, no shadows |
| Boom voices / volume / pitch / duration | 4 / -10 dB / 40 Hz / 0.6 s |
| Spatial boom unit size / maximum distance | 30 / 450 m |
| MultiMesh bounds | (-1000,-100,-1000) origin, (2000,200,2000) size, m |

Flash radius grows linearly to `blast.radius_m × 0.35`; it does not imply a gameplay radius change. Visual exports allow capacities 1–32 flashes / 1–16 voices, lifetime 0.05–1 s, fraction 0.01–1, starting radius 0.01–1 m, volume -40–6 dB, pitch 10–200 Hz, duration 0.1–2 s, attenuation unit size 1–100 m and max distance 10–1000 m. Rocket bodies face their simulated velocity; effects interpolation is off. Existing impact effects skip persistent marks on `AnimatableBody3D`, including the shield, because those bodies move; sparks / sound remain.

`SfxFactory.swish` caches deterministic 22050 Hz / 16-bit mono filtered noise plus a sine tone. Its smoothing coefficient is 0.1, noise gain 0.7, tone gain 0.1, envelope `sin(PI*t/duration)^2`; pitch and duration come from the melee Resources. Boom uses the existing falling-thump / noise gunshot synthesis. All are original project sounds credited in CREDITS; no binary samples or models were added.

InputMap adds `secondary_next` = **O**, physical keycode **79**, and `shield_test_fire` = **B**, code **66**, both dead zone **0.2**. P remains physical 80; no F11 binding is restored. The F3 list adds secondary selection, shows unavailable attachment slots and a shield B hint, and moves its top offset to **-210 px**. The guard probe sends one round from **15 m** ahead of the gameplay eye towards it, only while a shield is ready / firing. Exported distance range is 1–50 m. `debug/data/guard_probe_round.tres` sets **120 m/s**, gravity **0**, lifetime **0.5 s**, damage **0**, `stats_eligible=false`; remaining carrier defaults are unchanged. This uses the same projectile sweep and blocks on intervening scenery. It never increases player shots or hits. The range has no enemy attacks / player health system; B makes protection observable without introducing either.

### Secondary greybox geometry

All dimensions and positions below are metres, with identity part rotations and X 0 unless listed. Four text scenes live in `weapons/viewmodels/*_viewmodel.tscn`. Metal uses RGB (0.16,0.17,0.19), roughness 0.8; polymer (0.30,0.31,0.27), roughness 0.9, alpha 1. Shield visor uses RGBA (0.36,0.53,0.56,0.25), roughness 0.2 and alpha transparency. Parts cast no shadows. Native pistol / rocket sight post tips are respectively 0.043 / 0.100 m above model origin, yielding authored sight heights after subtracting their bore Y.

`wayline_pistol_viewmodel.tscn`:

| Part | Size | Position | Material |
|---|---|---|---|
| Receiver | (0.04, 0.045, 0.15) | (0, 0, 0) | metal |
| Slide | (0.035, 0.035, 0.13) | (0, 0.015, -0.02) | metal |
| Barrel | (0.016, 0.016, 0.1) | (0, 0.008, -0.165) | metal |
| Grip | (0.03, 0.085, 0.05) | (0, -0.055, 0.035) | polymer |
| Magazine | (0.022, 0.07, 0.03) | (0, -0.08, 0.035) | metal |
| RearSight | (0.025, 0.012, 0.012) | (0, 0.034, 0.04) | metal |
| FrontSightPost | (0.006, 0.013, 0.006) | (0, 0.0365, -0.12) | metal |

Markers: Muzzle = Vector3(0, 0.008, -0.22); Mounts/Muzzle = Vector3(0, 0.008, -0.22); Mounts/Optic = Vector3(0, 0.008, -0.02); Mounts/Magazine = Vector3(0, -0.04, 0.035).

`cairn_launcher_viewmodel.tscn`:

| Part | Size | Position | Material |
|---|---|---|---|
| Tube | (0.14, 0.14, 0.75) | (0, 0, -0.25) | polymer |
| FrontRim | (0.17, 0.17, 0.06) | (0, 0, -0.65) | metal |
| RearRim | (0.17, 0.17, 0.06) | (0, 0, 0.15) | metal |
| Grip | (0.045, 0.12, 0.06) | (0, -0.11, 0.05) | polymer |
| Rest | (0.1, 0.04, 0.18) | (0, -0.09, 0.02) | metal |
| RearSight | (0.035, 0.025, 0.02) | (0, 0.0825, 0.05) | metal |
| FrontSightPost | (0.008, 0.02, 0.008) | (0, 0.09, -0.45) | metal |

Markers: Muzzle = Vector3(0, 0, -0.75).

`latch_knife_viewmodel.tscn`:

| Part | Size | Position | Material |
|---|---|---|---|
| Grip | (0.03, 0.03, 0.12) | (0, 0, 0.04) | polymer |
| Guard | (0.07, 0.015, 0.012) | (0, 0, -0.025) | metal |
| Blade | (0.025, 0.008, 0.27) | (0, 0, -0.17) | metal |
| Tip | (0.012, 0.008, 0.04) | (0, 0, -0.325) | metal |

Markers: Muzzle = Vector3(0, 0, -0.345).

`palisade_shield_viewmodel.tscn`:

| Part | Size | Position | Material |
|---|---|---|---|
| LowerPanel | (0.65, 0.6, 0.05) | (0, -0.32, 0) | polymer |
| LeftFrame | (0.09, 0.6, 0.05) | (-0.28, 0.3, 0) | metal |
| RightFrame | (0.09, 0.6, 0.05) | (0.28, 0.3, 0) | metal |
| TopFrame | (0.65, 0.1, 0.05) | (0, 0.575, 0) | metal |
| VisorBottom | (0.47, 0.2, 0.05) | (0, 0.1, 0) | polymer |
| VisorTop | (0.47, 0.125, 0.05) | (0, 0.4625, 0) | polymer |
| Visor | (0.47, 0.2, 0.012) | (0, 0.3, -0.028) | visor |
| Grip | (0.12, 0.035, 0.1) | (0, 0, 0.07) | metal |

Markers: Muzzle = Vector3(0, 0, -0.05).

### Milestone 9 performance and validation

The probe now accepts all nine names: `--perf-weapon=rifle|smg|lmg|shotgun|sniper|pistol|rocket|knife|shield`. Primaries and secondaries select through their normal role-aware exchange APIs. Non-auto weapons receive press / release edges; empty guns reload normally, shell reload interruption remains unchanged, and ammo-free melee repeatedly swings through its real cooldown. Reports add armed blast and shield-block counts alongside existing shots, physical collisions, dropped projectiles and awake actors.

Shield stress sends the non-scoring training Resource through the original projectile system every **15 physics ticks (0.25 s)** from **2 m** ahead. This is a probe-only fixture, separate from B's normal 15 m test. An initial 15 m moving stress attempt recorded zero blocks: during the 0.125 s flight the walking player could move outside the finite shield. It was excluded as a blocking benchmark. The shorter flight gives real blocks while retaining walking, view sweep, all actors and the regular projectile / impact effects path. The corrected probe records **45 blocks** plus **13 bash swings** per run, without adding incoming rounds to player stats. All probe processing remains disabled in ordinary play.

Measured on the target Intel i5 / Iris 655, Compatibility, **1280×720**, 60 Hz physics, full HUD and diagnostics. Every accepted run was focused for **100%** of measured frames, with **54 min / 54 max awake ragdoll parts**, **eight awake props** and three driven steel hinges. Runs used the existing 2 s warmup / 10 s measurement in isolation from tests, imports, captures and commits. A temporary external driver restored foreground focus without changing normal game focus handling.

| Capped run | Average | 1% low | Worst frame | Frames >25 ms | Peak projectiles / dropped | Actions since start |
|---|---|---|---|---|---|---|
| M8 fitted Foundry, historical reference | 60.0 fps | 40.6 fps | 29.45 ms | 3 / 601 | 36 / 0 | 100 shots |
| M9 fitted Wayline | 60.0 fps | 50.6 fps | 22.27 ms | 0 / 602 | 3 / 0 | 46 shots |
| M9 Cairn | 60.0 fps | 52.5 fps | 21.01 ms | 0 / 601 | 1 / 0 | 3 shots / 3 armed blasts |
| M9 Latch | 60.0 fps | 42.1 fps | 29.52 ms | 2 / 601 | 0 / 0 | 23 swings |
| M9 Palisade, corrected fixture repeat | 60.0 fps | 52.1 fps | 20.37 ms | 0 / 601 | 2 / 0 | 13 bashes / 45 blocks |
| M9 fitted Foundry regression | 60.0 fps | 39.8 fps | 25.86 ms | 3 / 601 | 36 / 0 | 100 shots |

Wayline fits baffle / irons / extended magazine at 1.5 s; Foundry additionally fits long barrel / braced stock. No free ammo is granted. Sampled draw calls / primitives were respectively **188 / 4,088**, **184 / 3,662**, **180 / 3,608**, **175 / 3,724**, **174 / 3,620** for the five M9 rows. Physical collision counts include scenery / incoming training rounds and are not HUD accuracy.

The first corrected shield run also averaged 60.0 fps, but had a **35.0 fps 1% low, 32.49 ms worst and 57/601 frames >25 ms**. A fully focused uncapped diagnostic then averaged **103.3 fps**, 9.68 ms mean, with **51.0 fps 1% low, 33.81 ms worst, 5/1035 frames >16.67 ms and 2/1035 >25 ms**, still recording 45 blocks / all actors / zero dropped rounds. Repeating the capped run produced the Palisade row above. There was no intervening gameplay optimization or feature removal; these results demonstrate variable pacing and uncapped headroom, not a controlled before/after improvement.

The 60 fps average is retained. A strict per-frame 16.67 ms floor is **not** claimed: the knife / LMG tails and the variable shield pacing remain visible in these measurements. Bounded query candidates, one contact cast, sleeping effects processing, reused colliders, cached weapon state and fixed visual / audio pools keep additional gameplay work bounded. Keep incoming shield impacts and rocket blasts in the Milestone 12 final performance matrix, alongside the historical fitted LMG case.

The full tests cover splash arming / falloff / occlusion, torso deduplication / armor carry-over / exact last-plate break, multi-target logical hits and stats reset, real prop / steel / newly killed ragdoll impulses, expiry duds, melee wall blocking / reach / overlap / timing / one-shot scoring, ammo-free rules, guard blocking / side exposure / pose reuse, scaled movement / momentum, authored pistol timing / reload / attachment compatibility and role-safe cached secondary exchange. Range integration uses real controller fire for a knife headshot, rocket splash kill, 25 m pistol torso hit (about 26.5 damage), 40-damage shield torso bash and non-scoring shield test round. Frozen MVP stats and all original regression tests remain green. Effects tests cover bounded reuse, rocket-only rendering, expiry and pausing; moving-body impact tests include the shield's animatable body type.

Movie Maker frames were inspected for all four native models, the pistol / rocket ADS sight geometry, the shield visor and incoming sparks with no floating persistent mark, a **113 displayed knife headshot** (75 × 1.5 rounded) and **180 rocket torso kill**. Both kill captures show one shot / hit and 0.000 s TTK, with headshot percentage 100% / 0% respectively. A separate clear-view capture with the cosmetic model hidden confirms the expanding orange blast at the actual impact. Short firing captures can retain the existing engine warning about active audio playback objects at Movie Maker shutdown; the ordinary boot and GUT shutdown checks are separate.

Final verification: **340/340 headless GUT tests, 6,606 assertions, 176.911 s**, clean exit with no engine errors or leaked-object warnings. A separate headless startup (10 frames) and ordinary windowed startup (120 frames) both exit successfully with zero errors / warnings. The focused stress measurements above are separate from the boot and Movie Maker checks.

### Remaining Phase 2 scope

Human judgment of recoil, sight readability, sound balance, blast / melee feel and shield coverage remains pending; README's numbered secondary checklist describes each check. This range still has no player damage / enemy simulation, so the shield test is an incoming training round rather than an AI opponent. Shield sides remain exposed and its collider does not model destructible glass or penetration. Corpses retain the existing bullet-excluded layer and pin joints; blasts can still push them.

Milestone 10 should animate the existing handling / reload policy timelines and the already working knife / bash signals without changing their contact timing. Milestone 11 can consume the existing role-filtered catalogs and cached builds for Armory / persistence. No additional gameplay milestone is needed between them. Browser export and full controller gameplay remain unvalidated future work; this milestone adds only GDScript, built-in physics / audio and InputMap actions, with no new runtime filesystem access or native dependency.

## Milestone 10: handling animations

### The weapon logic is the only clock

Handling animation has no timer of its own. Every frame, `HandlingTimeline.collect` reads the current weapon's `WeaponLogic` and lists the running events with a 0–1 progress:

- **Reloads** use `get_reload_progress()`. `reload_phase` picks shell start / insert / finish; otherwise `is_reload_empty()` picks empty or tactical.
- **Cycle** is `1 - time_to_next_shot / shot_interval`. It covers bolt and pump actions, the pistol slide and melee cooldowns.
- **Lowered** is `1 - raise blend`. Equip therefore follows `raise_time` and holster follows `lower_time`, and a switch reversed halfway continues from the same pose.
- **Empty hold** applies while an ammo-using weapon holds no rounds, is not reloading and is not cycling.

Durations therefore come from the computed build stats. A quick magazine (reload ×0.85) shortens its reload animation by exactly the same factor. Pause freezes it because the logic stops ticking. Cancelling by switching, or interrupting a shell insert by firing, needs no animation-side state: the next frame samples whatever the logic now says. Tests count the ticks each event is reported for all relevant weapons. Reloads and shell phases report for exactly their Resource length in ticks. Cycles and raises report one tick fewer, because the first sample is taken a tick after the shot or switch began.

### Profiles, tracks and composition

A `HandlingProfile` Resource (`weapons/animation/data/*.tres`) holds `HandlingTrack`s. Each track is a pulse on one event and one named part (empty name = the whole model): it eases (smoothstep) from rest to its offset / rotation between `out_start` and `out_end`, holds, and eases back between `back_start` and `back_end`. `back_start = 1` never returns within the event. Simultaneous tracks sum their offsets and Euler XYZ rotations. Offsets are in the model's space; rotations are about the part's own origin.

- Every frame, every animated part is rewritten from its recorded rest transform. Nothing accumulates, so leaving an event always returns the part to rest.
- An attachment mount named like the part (`Mounts/Magazine`) follows it rigidly (`part_new × part_rest⁻¹ × mount_rest`), so fitted magazines move with the native one.
- Parts are hidden by scaling to 0.0001, never with `visible` (the Milestone 2 camera-rig fault).
- `staged_parts` are hidden unless a SHOW window is open (the loading shell). `empty_hidden_parts` are hidden while the weapon is empty (the rocket in the tube, the LMG belt). A HIDE window always wins over SHOW.
- A HIDE window with `releases_copy` drops a physics copy on the frame its window opens, once per event instance.

The previous generic reload dip / roll in `WeaponView` (0.11 m, 28°) is removed; the profiles replace it. The generic lowered offset / pitch remain underneath the per-weapon lowered tracks. Tests require every profile to be valid, every named part to exist in its viewmodel, every reload / finish / cycle event to end at rest, every event to start at rest except where it continues the previous pose (an empty reload begins at the empty-hold pose; shell start → insert → finish are continuous), racks only on empty magazine reloads, and exactly one release per magazine reload.

### Parts must be posed before the pivot moves

The first rendered reload showed no motion at all, although the node transforms were correct: the trace showed the expected magazine and model transforms every frame, all with interpolation off. Under the camera rig (interpolation off), Godot 4.7 only drew model-part transforms written *before* the pivot's own transform was set that frame. `WeaponView._process` now calls the animator first and writes the pivot afterwards. This is the second rig-specific renderer fault after the `visible` one; any future per-part viewmodel motion must follow the same order. Headless tests cannot catch this, so the Movie Maker captures below were the check.

### Edges and accepted pops

- **Shell interrupt during the 0.20 s opening:** the tilt jumps from its partial START pose to the full FINISH pose. A fire press during an insert is continuous.
- **Cancel by switching:** the reload pose snaps to rest on the first lowering frame while the model starts its holster roll. Ammo is unchanged; no extra magazine drops.
- **Pistol last round:** the slide cycles forward over 0.15 s, then snaps back into the empty hold.
- **Cairn** has no tactical-reload tracks. Its capacity is one and it accepts no attachments, so only an empty reload can occur; this also keeps the hidden-start rocket from counting as a visible jump.
- **Melee contact still happens on the press** (Milestone 9 timing is unchanged). The knife reaches its strike pose after 0.12 × 0.5 s = 0.06 s and the shield after 0.10 × 0.9 s = 0.09 s; the rest of each cooldown is follow-through. If a play-test finds the strike late, a real wind-up needs a contact delay, which is a gameplay change and needs sign-off.

### Pooled physics magazines

`MagazineDropPool` is created by `WeaponView` beside the player (outside the camera rig, so its bodies are ordinary interpolated physics bodies), with **6** `RigidBody3D`s built once. Each release reuses the oldest body. It:

1. copies up to **4** meshes: the native magazine plus mesh instances under its mount, so an extended or drum magazine drops with its part;
2. fits a box collider around them;
3. starts at the part's world transform with the player's velocity, minus **1.2 m/s** along the part's down axis and **4 rad/s** about its X axis;
4. is frozen, hidden and removed from collision after **4 s** of gameplay time.

Mass 0.35 kg, friction 0.9, bounce 0.15. The velocity is set after unfreezing; a frozen body discarded it. Bodies use layer **16** and mask **1**. Projectiles (mask 1 | 8), melee casts (1 | 8) and blast queries (1 | 4 | 8) never include 16; the player and ragdolls do not scan it. A copy can rest against layer-1 props or target zones, but at 0.35 kg against 8–12 kg props and kinematic targets it cannot move them meaningfully, and it can never produce a hit or stat. Tests fire a real projectile through an active drop and check it strikes the wall behind it.

Releases were first placed when the magazine was fully out (0.26 m below the well). The copy then spawned off screen and, when looking down, behind the eye, because "down" in the tilted gun frame points back toward the body. Release points now sit 0.04 of the event after the pull starts, so the copy leaves from the well in view and falls under gravity. When looking steeply down it falls toward the feet, below the visible part of the frame.

### Complete handling tuning reference

One table per profile. Out / back / window are fractions of the event; Lowered progress is how far the weapon is put away.

`magazine.tres` (Halberd, Rill):

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Tactical | model | (-0.05,-0.01,0.02) | (10,8,-28) | 0–0.16 | 0.82–1 | — |
| Tactical | Magazine | (0,-0.26,0.03) | (-12,0,0) | 0.1–0.3 | 0.48–0.74 | hide 0.14–0.48, drops copy |
| Empty | model | (-0.05,-0.01,0.02) | (10,8,-28) | 0–0.14 | 0.9–1 | — |
| Empty | Magazine | (0,-0.26,0.03) | (-12,0,0) | 0.06–0.22 | 0.4–0.64 | hide 0.1–0.4, drops copy |
| Empty | ChargingHandle | (0,0,0.07) | (0,0,0) | 0.74–0.8 | 0.82–0.88 | — |
| Lowered | model | (0,0,0) | (0,0,-15) | 0–1 | — | — |

`pistol.tres` (Wayline):

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Tactical | model | (-0.04,-0.01,0.01) | (8,6,-26) | 0–0.18 | 0.8–1 | — |
| Tactical | Magazine | (0,-0.2,0.02) | (-8,0,0) | 0.1–0.28 | 0.46–0.74 | hide 0.14–0.46, drops copy |
| Empty | model | (-0.04,-0.01,0.01) | (8,6,-26) | 0–0.16 | 0.86–1 | — |
| Empty | Magazine | (0,-0.2,0.02) | (-8,0,0) | 0.08–0.24 | 0.42–0.68 | hide 0.12–0.42, drops copy |
| Empty | Slide | (0,0,0.03) | (0,0,0) | 0 | 0.74–0.8 | — |
| Cycle | Slide | (0,0,0.03) | (0,0,0) | 0–0.3 | 0.35–1 | — |
| Empty hold | Slide | (0,0,0.03) | (0,0,0) | 0 | — | — |
| Lowered | model | (0,0,0) | (0,0,-25) | 0–1 | — | — |

`bolt.tres` (Longwatch):

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Cycle | BoltHandle | (0,0,0) | (0,0,65) | 0.12–0.24 | 0.72–0.84 | — |
| Cycle | BoltHandle | (0,0,0.08) | (0,0,0) | 0.28–0.42 | 0.5–0.66 | — |
| Cycle | model | (0,-0.01,0) | (0,0,6) | 0.08–0.22 | 0.74–0.92 | — |
| Tactical | model | (-0.05,-0.01,0.02) | (10,8,-26) | 0–0.14 | 0.84–1 | — |
| Tactical | Magazine | (0,-0.22,0.03) | (-10,0,0) | 0.1–0.26 | 0.44–0.7 | hide 0.14–0.44, drops copy |
| Empty | model | (-0.05,-0.01,0.02) | (10,8,-26) | 0–0.12 | 0.9–1 | — |
| Empty | Magazine | (0,-0.22,0.03) | (-10,0,0) | 0.08–0.22 | 0.38–0.6 | hide 0.12–0.38, drops copy |
| Empty | BoltHandle | (0,0,0) | (0,0,65) | 0.64–0.68 | 0.82–0.86 | — |
| Empty | BoltHandle | (0,0,0.08) | (0,0,0) | 0.7–0.74 | 0.76–0.8 | — |
| Lowered | model | (0,0,0) | (0,0,-12) | 0–1 | — | — |

`lmg.tres` (Foundry); hidden while empty: Belt:

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Tactical | model | (-0.05,-0.01,0.02) | (8,14,-24) | 0–0.08 | 0.9–1 | — |
| Tactical | Lid | (0,0,0) | (-75,0,0) | 0.06–0.14 | 0.8–0.88 | — |
| Tactical | Magazine | (0.02,-0.3,0.03) | (0,0,-10) | 0.16–0.32 | 0.46–0.62 | hide 0.2–0.46, drops copy |
| Tactical | Belt | (0,-0.03,0) | (0,0,0) | 0.64 | 0.66–0.76 | hide 0.16–0.64 |
| Empty | model | (-0.05,-0.01,0.02) | (8,14,-24) | 0–0.07 | 0.92–1 | — |
| Empty | Lid | (0,0,0) | (-75,0,0) | 0.05–0.12 | 0.74–0.81 | — |
| Empty | Magazine | (0.02,-0.3,0.03) | (0,0,-10) | 0.14–0.28 | 0.4–0.55 | hide 0.18–0.4, drops copy |
| Empty | Belt | (0,-0.03,0) | (0,0,0) | 0.57 | 0.59–0.7 | show 0.57–1 |
| Empty | ChargingHandle | (0,0,0.08) | (0,0,0) | 0.84–0.88 | 0.9–0.95 | — |
| Lowered | model | (0,0,0) | (0,0,-10) | 0–1 | — | — |

`shotgun.tres` (Breakwater); staged: LoadingShell:

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Shell start | model | (-0.07,0.04,0) | (8,10,-32) | 0–1 | — | — |
| Shell insert | model | (-0.07,0.04,0) | (8,10,-32) | 0 | — | — |
| Shell insert | LoadingShell | (-0.02,-0.07,0.05) | (0,0,0) | 0 | 0.3–0.75 | show 0–0.8 |
| Shell finish | model | (-0.07,0.04,0) | (8,10,-32) | 0 | 0–1 | — |
| Cycle | Handguard | (0,0,0.08) | (0,0,0) | 0.1–0.35 | 0.45–0.75 | — |
| Lowered | model | (0,0,0) | (0,0,-15) | 0–1 | — | — |

`rocket.tres` (Cairn); hidden while empty: LoadedRocket:

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Empty | model | (-0.06,-0.06,0.05) | (6,8,-12) | 0–0.15 | 0.82–1 | — |
| Empty | LoadedRocket | (-0.14,-0.16,0.32) | (0,20,0) | 0 | 0.25–0.7 | show 0.2–1 |
| Lowered | model | (0,0,0) | (0,0,-10) | 0–1 | — | — |

`knife.tres` (Latch):

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Cycle | model | (-0.18,0.04,-0.12) | (-10,55,-35) | 0–0.12 | 0.3–0.9 | — |
| Lowered | model | (0,0,0) | (0,0,-30) | 0–1 | — | — |

`shield.tres` (Palisade):

| Event | Part | Offset, m | Rotation, ° | Out | Back | Window |
|---|---|---|---|---|---|---|
| Cycle | model | (0,0.02,-0.22) | (-6,0,0) | 0–0.1 | 0.3–0.85 | — |
| Lowered | model | (0,0,0) | (0,25,0) | 0–1 | — | — |

Times are fractions of the event: for example the Halberd empty reload (2.4 s) releases its magazine at 0.24 s and racks the charging handle at 1.78–2.11 s; the Breakwater shell moves in over 0.17–0.41 s of a 0.55 s insert. Rotations use the model's axes: +X pitches the muzzle up, +Y yaws it left, −Z rolls the underside toward the screen centre. Reload rolls were first authored positive (+24°), which turned the magazine well away from the camera; captures showed the magazine never on screen, so they were flipped.

### New greybox geometry

Materials reuse each viewmodel's metal / polymer, plus three new ones. None of the parts cast shadows.

| Scene | Node | Size, m | Position, m | Material |
|---|---|---|---|---|
| `halberd_rifle_viewmodel.tscn` | ChargingHandle | (0.02, 0.012, 0.025) | (0.035, 0.02, 0.06) | metal |
| `rill_smg_viewmodel.tscn` | ChargingHandle | (0.02, 0.012, 0.022) | (0.032, 0.018, 0.03) | metal |
| `foundry_lmg_viewmodel.tscn` | ChargingHandle | (0.02, 0.014, 0.028) | (0.05, 0.02, 0.1) | metal |
| `foundry_lmg_viewmodel.tscn` | Lid (hinge `Node3D`) / Cover | Cover (0.07, 0.015, 0.16) | Lid (0, 0.0525, −0.2); Cover local (0, 0, 0.08) | metal |
| `foundry_lmg_viewmodel.tscn` | Belt | (0.015, 0.06, 0.05) | (−0.045, −0.005, −0.04) | brass RGB (0.62, 0.48, 0.20), roughness 0.5 |
| `breakwater_shotgun_viewmodel.tscn` | LoadingShell | (0.02, 0.02, 0.065) | (0, −0.045, −0.06) | shell RGB (0.55, 0.12, 0.10), roughness 0.7 |
| `cairn_launcher_viewmodel.tscn` | LoadedRocket | (0.085, 0.085, 0.30) | (0, 0, −0.66) | warhead RGB (0.33, 0.36, 0.25), roughness 0.8 |

The Lid hinges at the cover's front edge, so the −75° X rotation lifts its rear. The loaded rocket protrudes 0.13 m from the front rim. No sight geometry moved, so authored sight heights and zeros are unchanged.

### Debug tooling

- **`--hold=action@start-release`** now releases at an optional time. A held action is also pressed again if the engine releases it. Movie Maker windows lose focus, and the engine then drops every pressed action: a held fire stopped after six shots. One-off edge keys (attachment cycling) should be given a release time so a focus loss cannot cycle them again; the README perf commands now do.
- **`--perf-reload`** (with `--perf-fire`) presses reload whenever the gun has fired at least one round. Reports add reloads started, magazines released and peak active drops.
- Movie Maker captures occasionally stalled on one repeated frame: three of about twenty back-to-back captures this milestone, one of them with `--always-on-top`, with nothing in the log. Rerunning the same command produced a normal capture. Treat a capture whose HUD never changes as stalled, not as evidence.

### Milestone 10 performance and validation

Measured on the target Intel i5 / Iris 655, Compatibility, **1280×720**, 60 Hz physics, full HUD and diagnostics, with `--perf-fire --perf-stress` (54 / 54 awake ragdoll parts, eight awake props, three driven steel hinges throughout every run), 2 s warmup / 10 s measurement, window in front. All rows below were focused for 100% of measured frames.

| Capped run | Average | 1% low | Worst frame | Frames >25 ms | Draw calls / primitives | Actions since start |
|---|---|---|---|---|---|---|
| Halberd `--perf-reload` | 58.9 fps | 16.4 fps | 225.34 ms | 1 | 186 / 3,792 | 6 reloads, 6 drops, 2 peak active |
| Rill `--perf-reload` | 60.0 fps | 51.3 fps | 21.66 ms | 0 | 188 / 3,858 | 8 reloads, 8 drops, 3 peak active |
| Foundry `--perf-reload` | 60.0 fps | 48.9 fps | 22.80 ms | 0 | 186 / 3,752 | 3 reloads, 3 drops, 1 peak active |
| Wayline `--perf-reload` | 60.0 fps | 51.8 fps | 21.29 ms | 0 | 184 / 3,730 | 8 reloads, 8 drops, 3 peak active |
| Breakwater (pump + shell loading) | 60.0 fps | 51.6 fps | 22.60 ms | 0 | 186 / 3,990 | 9 shells, 4 shell reloads |
| Longwatch (bolt cycling) | 60.0 fps | 42.1 fps | 38.49 ms | 1 | 188 / 3,920 | 7 shots, 1 reload |
| Cairn | 60.0 fps | 52.5 fps | 19.96 ms | 0 | 185 / 3,676 | 3 rockets, 3 armed blasts |
| Latch | 60.0 fps | 49.8 fps | 22.18 ms | 0 | 181 / 3,620 | 23 swings |
| Palisade | 60.0 fps | 50.2 fps | 21.28 ms | 0 | 175 / 3,724 | 13 bashes, 45 blocks |
| Fitted Foundry regression | 60.0 fps | 49.0 fps | 23.23 ms | 0 | 166 / 3,524 | 100 shots, 1 reload / drop |

Against Milestone 9, the knife (42.1 → 49.8 fps 1% low) and fitted Foundry (39.8 → 49.0) rows are better and the rocket row is identical; nothing was optimised between them, so this is run-to-run variance rather than a gain. The animator rewrites at most six part transforms per frame (Foundry: model, cover, box, its mount, belt, charging handle) and the pool never exceeded three active bodies.

The Halberd reload-stress row has one **~225 ms** frame, and it pulls the average to 58.9 fps and the 1% low to 16.4 fps. All three Halberd runs had it (worst 225.3 / 224.6 / 232.4 ms; the last two were only partly focused and are not tabled). A traced run placed it at **2.17 s**: the start of the second reload, just after the first counted shot. Repeating the run with the animator and magazine release disabled by a temporary switch gave the same frame at the same time (**220.2 / 223.0 ms** in two runs), so it is a pre-existing first-use cost that this probe's ordering moves into the measured window, not a Milestone 10 cost. The other probes switch weapon first, which probably places the equivalent moment in the warmup; its cause has not been isolated. It is recorded for the Milestone 12 performance pass rather than hidden by a longer warmup. Excluding that frame, the Halberd run had no other frame over 25 ms.

Movie Maker frames were inspected for:

- the Halberd empty reload (roll, magazine pull, falling copy, new magazine, rack)
- the Wayline shot and tactical reload
- the Longwatch bolt cycle
- the Foundry tactical reload (cover, box, belt)
- the Breakwater pump and shell inserts
- the Cairn fire and reload
- the Latch slash and Palisade bash

The view from steeply above shows the copy falling past the gun toward the feet.

Final verification: **373/373 headless GUT tests, 7,009 assertions, 221.7 s**, clean exit with no engine errors or orphan warnings. Headless startup (10 frames) exits with zero errors / warnings. New tests are in `test_handling_timeline.gd`, `test_weapon_animator.gd` and `test_magazine_drop_pool.gd`; every earlier test is unchanged and passing.

### Remaining Phase 2 scope

Human judgment is still needed for reload readability, roll direction and amount, pump / bolt / slide feel, the knife strike timing and the magazine drop. README's numbered handling checklist describes each check. Animations are greybox part motions without hands or arms. A dropped magazine falls from the well and leaves the frame quickly; it is visible on the ground only when looking around. Milestone 11 can show these profiles unchanged in the Armory preview by calling `WeaponAnimator.apply` with a logic in any state.

## Milestone 11: main menu and Armory

### Front end, settings and range lifetime

`ui/main_menu.tscn` is the application entry point. `GameFlow` owns one active screen: MainMenu, Armory or the range. Play creates a fresh range; Return to Main Menu removes it, so old projectiles, targets, timers, audio and magazine pools cannot continue behind the menus. Entering Play again restores full magazines and fresh stats, using the saved selection. Debug P / O and F5–F10 changes remain session-only.

The menu offers Play, Armory, Settings and Quit. `SettingsPanel` contains the existing seven sliders and FPS toggle; both front-end Settings and PauseMenu use it. Values still apply live through ViewSettings. Save & Back, or Esc / B from front-end Settings, saves `user://settings.cfg`; pause saves on Resume as before. No second settings schema or tuning source was introduced.

Menu activation must not become a shot or jump. `Input.action_release` does not erase `just_pressed` within the current physics tick: the first integration test entered with 41 instead of 42 SMG rounds. GameFlow releases actions and waits across **two physics boundaries** before creating the player. A transition generation counter prevents an intervening screen change from later reopening the range. Tests deliberately hold fire and jump across Play, and cancel a pending transition.

RangeBuilder exposes explicit controller and pause-menu references in its scene; GameFlow connects the pause return signal and supplies startup builds through those references. Tests and probes can still instantiate `range/range.tscn` directly, retaining its authored defaults without reading a loadout file. `--range` uses the saved configuration; `--armory` opens the editor. Existing `--perf-probe`, `--pose` and `--hold` commands bypass the menu. For repeatable authored-default benchmarks, explicitly launch `res://range/range.tscn`.

### Persistence and draft boundaries

`LoadoutConfig` owns role-validated primary / secondary definitions and lazy, weapon-keyed WeaponBuilds. It uses the existing five-primary, four-secondary and seventeen-attachment catalogs. Switching the edited weapon retains its draft attachments. Armory operates on a copy; Save & Back writes the file before emitting an independent saved snapshot, and Cancel discards the draft. Save failures keep the editor open with a message.

`user://loadout.cfg` is a version-1 ConfigFile. The loadout section stores the selected weapons' authored Resource paths; per-weapon sections store attachment IDs under the five slot names. These are **lookup keys only**: no file value is ever passed to `load`. Weapon keys must match the correct role's catalog, and parts must match a catalog ID, slot, class and WeaponBuild validation. Unknown entries fall back independently to the default selection or native part. Missing / unreadable files and unsupported versions retain Halberd / Wayline defaults. Stats, ammo, recoil and animation state are never serialized.

Catalogs are loaded from fixed authored paths when a configuration is constructed, after script initialization. Preloading the catalog Resources as class constants exposed shutdown reference-retention warnings when GUT imported the Armory, even in an import-only test without UI instances. Moving the same catalog loads into `_init` removed those warnings across isolated tests and the full suite. No GUT/vendor modification or warning suppression was needed; a deeper engine cause is not claimed.

Before entering the tree, the controller receives the two prepared builds. It copies their attachments into independent WeaponRuntime builds, computes the final stats and initializes ammo to the final capacity. Range changes cannot mutate the saved selection or draft. The original fixture-based rifle / sniper tests remain unchanged and green.

### Comparisons and preview

StatComparison reads the actual cached WeaponBuild snapshot rather than duplicating modifier arithmetic. Rows show base, fitted and signed difference, with units. The scrollable panel includes rate / interval, capacity, ADS / reload / handling times, falloff, recoil, spread and sight values. Shotguns distinguish first-empty insert, later insert and complete empty reload; pellets show per-pellet damage and cone. Rockets show blast damage, radius and arming distance; melee shows damage, reach, attack interval and movement scale. Magnification is `tan(65° / 2) / tan(ADS FOV / 2)`, preserving the fixed reference used to author the optics.

The preview uses **one SubViewport, one world, one camera, one light and one weapon model**, only while Armory is open. It instantiates the existing viewmodel and compatible attachment parts, removes displaced native sights, fits the actual mesh bounds and recentres before binding WeaponAnimator. It renders at the panel's full pixel size; halving it made the small geometry visibly coarse in the first capture.

Show handling runs an isolated WeaponLogic with the build's real timings: empty reload for ammo weapons, attack cooldown for melee. WeaponAnimator samples that logic every frame. There are no gameplay projectile, damage, sound or magazine-drop connections. Part posing happens before the pivot is written, preserving the camera-rig ordering from Milestone 10. No `visible` toggles are used for model parts. Rotation buttons change yaw by **30°** per activation; bounds fitting uses the same scale at every angle.

Presentation reference at **1280×720**:

| Value | Choice |
|---|---|
| Outer margin / column gap | 28 / 18 px |
| Selection / comparison column minimum widths | 285 / 360 px |
| Preview minimum size | 300×280 px; expands into the remaining space |
| Main menu / Armory title sizes | 42 / 30 px |
| Armory controls / comparison rows | 14 px; 5 px vertical button padding |
| Preview camera | 48° FOV; near 0.01 m; position (0, 0.12, 1.65) |
| Preview light / ambient energy | 1.5 / 0.65; no shadow map |
| Preview rotation / fit | initial yaw 0.9 rad; pitch 0.12 rad; bounds diagonal scaled to 1.15 |
| Stat scrolling | 80 px per Left/Right press while the panel has focus |

The initial layout clipped Save & Back below the window. Compact Armory controls fixed it, and a GUT test now instantiates the screen in an explicit 1280×720 viewport and checks the footer and final selector bounds. Focus rings are amber. Up/Down and Tab cycle an explicit list; disabled attachment slots are omitted. Native Godot popups handle controller A / D-pad selection and B cancellation; the screen only consumes cancellation after a popup closes. A focusable stats panel exposes Left/Right scrolling. Full controller gameplay remains a later phase.

### Performance and validation

Measured on the target **Intel i5-8259U, 8 GB RAM, Iris Plus 655**, Compatibility, **1280×720**, 60 Hz physics, the existing 60 fps cap. Runs were sequential, separate from tests, imports, captures and commits. A temporary external scene exercised the actual GameFlow / Armory and restored foreground focus without changing normal application focus handling. Each row uses a **2 s warmup / 10 s measurement**. Every accepted row below was focused for **100%** of measured frames.

| Capped run | Average | 1% low | Worst frame | Frames >25 ms | Draw calls / primitives |
|---|---|---|---|---|---|
| Main menu | 60.0 fps | 56.4 fps | 17.81 ms | 0 | 16 / 374 |
| Front-end Settings | 60.0 fps | 47.2 fps | 38.45 ms | 1 | 37 / 1,604 |
| Fully fitted Halberd preview, repeated reloads | 60.0 fps | 56.2 fps | 17.85 ms | 0 | 65 / 2,090 |
| Fully fitted Foundry preview, repeated reloads | 60.0 fps | 56.2 fps | 17.90 ms | 0 | 67 / 2,126 |
| Palisade preview, repeated bashes | 60.0 fps | 56.1 fps | 17.94 ms | 0 | 58 / 1,058 |
| Fully fitted Foundry range stress | 60.0 fps | 43.0 fps | 31.55 ms | 1 | 172 / 3,606 |
| Halberd reload-stress regression | 58.9 fps | 16.5 fps | 223.81 ms | 1 | 186 / 3,768 |

Preview fittings used compact cap, heavy barrel, 8× scope, balanced stock and drum magazine. Range Foundry used the existing first-choice-per-slot stress fixture, fired 100 shots and released one magazine. Both range rows kept **54 min / 54 max awake ragdoll parts**, **eight awake props**, three driven steel hinges and the full HUD; no projectiles were dropped.

The first home-menu run was only **99.2% focused** (59.8 fps average, 49.00 ms worst, ten frames over 25 ms). It was excluded and repeated without a code change; the accepted fully focused row is above. Settings retained one pacing spike despite its 60.0 fps average. These measurements establish the capped average and visible tail, not a strict 16.67 ms floor or a controlled optimization claim.

The Halberd row retains the Milestone 10 issue: one **223.81 ms** frame, six reloads / drops and two peak active drops. Its average is still 58.9 fps, matching the earlier 225.34 ms / 58.9 fps result. The pre-existing hitch remains unresolved for Milestone 12; no warmup extension or animation removal hides it.

Movie Maker frames were inspected for the main menu and shared settings with focus changes, fitted Halberd at rest / magazine-out / insertion, fitted Foundry cover / box motion, and the Palisade preview / disabled slots. Captures used `--always-on-top`. Changing focus and animation frames distinguish the captures from a repeated-frame stall.

Final verification: **389/389 headless GUT tests, 7,615 assertions, 224.464 s**, clean exit with no engine errors or orphan warnings. The main menu, Armory, saved-loadout range entry and direct range scene each passed a separate ten-frame headless boot with zero errors / warnings. New tests cover isolated disk round trips, role / catalog / attachment rejection, safe file fallback, independent drafts and startup builds, actual comparison values, all nine preview models, 720p layout, keyboard / simulated controller navigation, stat scrolling, saving / cancellation, settings reuse and transition input / lifetime boundaries.

Human play-tests remain pending for Milestones **3–11**, including physical controller input, preview readability, comparison usefulness and the full saved-loadout-to-range flow. README contains the Milestone 11 checklist. Stop for that play-test before beginning Milestone 12.

## Milestone 12: polish pass

### Angle-limited ragdoll joints

The five `PinJoint3D`s are now `ConeTwistJoint3D`s. Each joint's local X axis is its twist axis and points along the limb it holds: up for the neck, down for shoulders and hips. The swing limit is therefore how far the limb may leave its hanging pose and the twist limit is how far it may roll about its own length. Joints are re-placed with the dummy's basis at every activation, because a rail carrier can have moved it.

| Joint (part) | Swing | Twist |
|---|---|---|
| Neck (head) | 40° | 50° |
| Left / right shoulder (arm) | 85° | 45° |
| Left / right hip (leg) | 55° | 30° |

Limits are `swing_limit_degrees` / `twist_limit_degrees` exports on `DummyRagdoll`, in `ATTACHED_PARTS` order. **Jolt enforces them softly and Godot exposes no stiffness for it**, so a hard hit overshoots. The test kicks every part with the same seeded impulses every 25 ticks (3 m/s per kg) with and without limits. Free joints reached 148–174° of swing and 177–180° of twist (limbs completely flipped). Limited joints reached 52 / 87 / 57 / 89 / 60° of swing and 63 / 51 / 40 / 51 / 35° of twist in the order neck, left arm, left leg, right arm, right leg, an overshoot of at most 12° of swing and 13° of twist. Much harder kicks (6 m/s per kg, ten times) overshot by up to 8.5° of swing and 28° of twist. The tests allow 22° and also check that no limb ever folds past 120° of swing.

### Corpses are solid to bullets, and still never score

Active ragdoll parts are `RagdollPart` rigid bodies on layer **4** (`DummyRagdoll.CORPSE_LAYER`); the projectile mask is now `1 | 4 | 8`. They collide with the world and props only (mask 1), as before. `TargetHits` dispatches a hit on one to `RagdollPart.receive_hit`, which applies `momentum() × impulse_scale` at the point of impact. The 24 kg torso gains about 0.1 m/s from a rifle round and 0.4 m/s from a sniper round; the 3–4 kg limbs and head visibly move.

A corpse takes no damage and emits no signal: the killed dummy's zones are off every layer, so a round can never reach its health again. The range statistics see only the shot, so a corpse hit is a **miss**, exactly like a shot through a down dummy. Impact sparks and the tick play; marks do not (a rigid body is not a static surface). A rocket's explosive hit on a corpse detonates normally. Melee casts keep their mask (1 | 8) and do not hit corpses, which keeps the knife unchanged. After the 3 s reset the parts leave every layer, and a test checks that a round then reaches the wall behind.

### Adjustable sniper zero

`WeaponData.zero_options` lists the distances the player may cycle with **Z** (`zero_cycle`, physical key 90). Only the Longwatch sets it: 100, 200, 300 m, with `zero_distance_m` 100 as the default. The choice lives in `WeaponRuntime.selected_zero_m`, per weapon, so it survives switching, the exchange of primaries, and attachment rebuilds (each rebuild replaces the stat snapshot, not the runtime). `get_zero_distance()` is the selection or the Resource value; `_calibrate_zero` uses it. A change runs the existing `SightZeroing.solve` bisection once; nothing recalculates per frame. Only rounds fired afterwards use the new angle. `request_zero` rejects any distance not in the weapon's options, and `cycle_zero` is false for weapons with fewer than two. Cycling picks the option nearest the current zero and wraps.

The HUD shows `ZERO 200 m  [Z]` in a separate label above the weapon name (gold, 14 pt), visible only for adjustable weapons. It is separate so the weapon-name text that Phase 1 tests pin stays unchanged. The zero is session-only: it is not in `user://loadout.cfg`. With the sniper's 900 m/s round, a 100 m zero lands only 6.7 cm low at 200 m, and 300 m is the visible case.

### Time-to-kill clock from the first shot

`ViewSettings.ttk_from_first_shot` (default off, saved with the other view settings) changes only where a dummy's clock starts. Off keeps the original rule: first damaging hit. On: the clock starts at the **launch of the shot that first damaged that dummy**. "The first shot at a target" has no meaning before a hit lands, so a shot's launch is the earliest point that can be tied to a dummy. A one-shot kill therefore reads the bullet's flight time (about 0.4 s at 300 m with a 900 m/s round) instead of 0.000 s. Each dummy keeps its own clock; a later shot never moves it. `RangeFeedback` records each live shot's launch time on its physics clock (so a pause excludes menu time as before) and passes it to `RangeStats` as an optional start time, never later than the hit. A reset clears the recorded times, and a restore still discards an open clock. A shot that only damages steel opens no clock. The setting is a second toggle in the shared settings panel; the panel's refresh now reads each toggle from its own setting, where it had used the FPS setting for every checkbox.

### Muzzle smoke and ejected casings

Both are pooled, built once beside the player outside the camera rig, and cosmetic.

| Pool | Count | Lifetime | Notes |
|---|---|---|---|
| `MuzzleSmoke` | 8 one-shot `CPUParticles3D` | 0.9 s | World-space particles; 1–12 per puff (per-weapon); size 0.14 m growing ×3.2 (curve 0.35 → 1); drift 0.45 m/s up; burst 0.3–0.9 m/s, damped; colour (0.78, 0.78, 0.80, 0.30) fading to zero alpha; unshaded, alpha, billboard-particles material |
| `CasingPool` | 24 `RigidBody3D` | 2.0 s | Box collider and unit mesh scaled to the casing's size; mass 0.27 kg per metre of length; ejection 1.6–2.6 m/s along the port's +X, 1.2 m/s up, ±0.4 m/s scatter, 18 rad/s spin; friction 0.7, bounce 0.35; layer 16, mask 1 |

Both reuse the oldest slot, so nothing is allocated per shot. Casings age in gameplay time. Layer 16 is in no projectile, melee or blast mask, and the player and ragdolls do not scan it. The per-weapon values are in the weapon Resources:

| Weapon | Smoke particles | Casing box, m (X, Y, Z) | Port, model space | Colour | Eject delay |
|---|---|---|---|---|---|
| Halberd | 4 | (0.012, 0.012, 0.045) | (0.03, 0.02, 0.03) | brass (0.8, 0.62, 0.25) | 0 |
| Rill | 3 | (0.010, 0.010, 0.019) | (0.025, 0.02, 0.01) | brass | 0 |
| Foundry | 3 | (0.012, 0.012, 0.045) | (0.045, 0.02, 0.06) | brass | 0 |
| Breakwater | 6 | (0.020, 0.020, 0.070) | (0.04, 0.01, 0.06) | red (0.65, 0.12, 0.10) | 0.30 s (pump) |
| Longwatch | 5 | (0.013, 0.013, 0.065) | (0.04, 0.025, 0.12) | brass | 0.35 s (bolt) |
| Wayline | 2 | (0.010, 0.010, 0.019) | (0.02, 0.02, 0.0) | brass | 0 |
| Cairn | 10 | none | — | — | — |
| Latch, Palisade | 0 | none | — | — | — |

Both manual-action delays are shorter than the weapon's lower time (0.35 s vs 0.45 s, 0.30 s vs 0.35 s), so a casing still leaves while the weapon is being put away; a test pins this and that the delay is shorter than the shot interval. A second shot flushes a casing still waiting for the first. A scoped view has no model in the tree, so a casing thrown while still scoped is skipped, and smoke is skipped like the muzzle flash. The casing is queued before that scoped early return, so the bolt's casing still comes out once the player unscopes.

**A captured frame found a real bug:** the first smoke capture showed one screen-filling black-then-white rectangle. A particle billboard material drops the particle's scale unless `billboard_keep_scale` is set, so every quad drew at its full 1 m mesh size. Setting it fixed the capture, and a test pins the flag. The smoke quads are visibly blocky at the screen edge of each puff; that is accepted greybox quality.

### Particle first-draw stall and the warm-up

The Milestone 10 notes recorded an unexplained ~225 ms frame about 2 s into the Halberd reload probe. Disabling the muzzle-flash path removed it (worst frame 20.3 ms), and pre-emitting every effect once at 0.5 s moved the whole stall to 1.03 s with a measured worst frame of 21.9 / 21.4 ms. So the cause is **the first time each particle material is drawn**: the muzzle sparks, the smoke (added this milestone) and the impact sparks. Together they cost 560–570 ms on the target GPU, a visible freeze on the first shot of a session. Earlier probes hid it: shots began at 0 s, so the cost fell inside the 2 s warm-up.

`ParticleWarmup` fixes it. A few frames after load, a throwaway **twin** of each emitter (sharing the real mesh and material) emits one particle at 0.0001 scale in front of the camera, then frees itself after its lifetime plus 0.25 s. The impact marks are shown once at the same scale. It does nothing under the headless renderer, so the suite and CI see no change. `--no-warmup` turns it off for measurement. The flash *mesh* is not warmed because it is always drawn at negligible size.

`--perf-cold` (new) holds all firing until the 2 s warm-up ends, so first-use costs fall inside the measurement. Cold rifle runs, same code:

| Cold rifle run | Average | 1% low | Worst frame |
|---|---|---|---|
| `--no-warmup`, focused 100% | 53.3 fps | 3.7 fps | **707.36 ms** |
| `--no-warmup`, focused 83% | 49.0 fps | 2.5 fps | **981.93 ms** |
| warm-up, focused 100% (earliest runs) | 60.0 fps | 52.1 fps | 20.73 ms |
| warm-up, five consecutive plain cold runs, four focused 100% | 60.0 fps | — | 20.56–29.45 ms |

One of the earliest warm-up runs had a residual 234.64 ms frame (100% focused) and three of four runs in the next trace hit ~230 ms at 2.15 s; they stopped reproducing partway through that session without a code change, then returned on other weapons (below). I could not explain the disappearance.

### Known issue: a ~220 ms stall on the first hit after switching weapons

A residual stall remains in cold-start runs for **weapons the probe switches to**. It is steady and reproducible: always one frame of **212–247 ms at 2.15–2.17 s**, with 3 shots fired and 1–2 hits. The default rifle, with no switch, does not show it (five plain cold runs: 20.56–29.45 ms worst). A macOS stack sample over a run shows the time is **driver shader compilation** (`USC::CompilePixelShaderOpenGL` / `CompileVertexShaderOpenGL` in the Intel graphics driver: about 210 and 120 samples in two events, about 330 ms in all), not script work. The Godot binary has no symbols, so the sample cannot name which material is being compiled.

I bisected it with temporary switches (all removed), each three to five times at 100% focus, and none of these removes the stall: the muzzle flash mesh, flash sparks, impact sparks, impact sound, impact marks, shot sound, casing ejection, the whole HUD, and the stress fixture (it persists with no ragdolls, props or steel at all). Candidates left are the first draw of some other effect on a freshly switched weapon, or something in the first hit on a target. **Impact on play:** one ~0.2 s stall on the first hit after the first switch of a session; steady-state frame times are unaffected (see below). A fix needs a symbolised build or Godot's rendering profiler.

| Cold run (focused), `--perf-stress --perf-cold` | Worst frame | Notes |
|---|---|---|
| Halberd (default weapon, no switch) | 20.56–29.45 ms | clean in five plain runs |
| Rill SMG | 214.6–234.7 ms (12 fully focused runs) | at 2.15–2.17 s; 218.7–224.6 ms in the three of those with no stress fixture; larger (up to 431 ms) when the window was not focused |
| Foundry LMG | 223.04 ms and 284.1 ms (both 100% focused) | same moment |
| Breakwater, Longwatch, Halberd reload stress | 222–245 ms | focus 0–45%; not valid rows but the same size |

### Final performance matrix

Measured on the target **Intel i5-8259U, 8 GB RAM, Iris Plus 655**, Compatibility, **1280×720**, 60 Hz physics, the existing 60 fps cap, full HUD and diagnostics, `--perf-fire --perf-stress` (54 / 54 awake ragdoll parts, eight awake props, three driven steel hinges, in every row), 2 s warm-up / 10 s measurement, one row per run. **Every row below was focused for 100% of measured frames.** Runs that were not fully focused were repeated and are not tabled; the first set had several at 0–54% focus, and a version of the run script that re-activated the window every 2 s itself worsened frame pacing, so the window is now brought forward once at 3 s, before measurement.

| Weapon (steady state) | Average | 1% low | Worst frame | Frames >25 ms | Draw calls | Actions since start |
|---|---|---|---|---|---|---|
| Halberd | 60.0 fps | 49.8 fps | 22.71 ms | 0 | 186 | 80 shots |
| Rill | 60.0 fps | 51.0 fps | 21.36 ms | 0 | 185 | 90 shots |
| Foundry | 60.0 fps | 48.3 fps | 22.36 ms | 0 | 63* | 100 shots |
| Breakwater | 60.0 fps | 51.5 fps | 21.34 ms | 0 | 186 | 9 shells (73 pellet collisions) |
| Longwatch | 60.0 fps | 49.9 fps | 21.84 ms | 0 | 190 | 7 shots |
| Wayline | 60.0 fps | 50.9 fps | 22.45 ms | 0 | 183 | 45 shots |
| Cairn | 60.0 fps | 38.7 fps | 26.35 ms | 7 | 185 | 3 rockets, 3 armed blasts |
| Latch | 59.9 fps | 37.5 fps | 35.02 ms | 2 | 181 | 23 swings |
| Palisade | 60.0 fps | 49.8 fps | 23.91 ms | 0 | 175 | 13 bashes, 45 blocks |
| Foundry, all five attachments fitted | 60.0 fps | 41.7 fps | 40.52 ms | 1 | 176 | 100 shots, 1 reload |
| Longwatch, all five attachments fitted | 60.0 fps | 46.5 fps | 24.88 ms | 0 | 191 | 7 shots |

\* Draw calls are those of the last measured frame, which depends on where the view sweep points. The Foundry's 63 is such a frame; the same weapon read 164–176 in other runs.

All averages are 60.0 fps (59.9 for the knife), no projectile was dropped, and the ragdoll and prop counts held (54 min / 54 max, eight props). Compared with the Milestone 10 rows, the 1% lows are within about 1 fps for the Rill, Foundry, Wayline, Breakwater and Palisade, and better for the Longwatch (42.1 to 49.9 fps). **Three rows are lower: the Cairn (52.5 to 38.7 fps), the Latch (49.8 to 37.5 fps) and the fitted Foundry (49.0 to 41.7 fps).** I did not isolate why. The knife uses neither smoke nor casings, so those pools do not explain its row; every row also now runs cone-twist joints and hittable corpses in the stress fixture. Earlier milestones saw the same weapons swing between 35 and 52 fps from run to run (the Palisade in Milestone 9), so run-to-run variance is plausible but is not proven here. The tails to watch in play-testing are the rocket (7 frames over 25 ms), the knife (35.0 ms worst) and the fitted Foundry (40.5 ms worst). The strict 16.67 ms per-frame floor is **not** claimed; every 1% low is above 37 fps.

Draw calls: up to 24 casing meshes plus 8 smoke emitters can be visible in the worst case. The sampled frames show 175–191 draw calls and about 3,500–4,000 primitives for the steady-state rows (the Foundry sky frame aside), against 166–188 in Milestone 10, so the pools add at most a handful of calls.

### Final verification

**423/423 headless GUT tests, 7,854 assertions, 264.8 s**, clean exit with no engine errors or orphan warnings, with a separate 10-frame headless boot. Tests added this milestone cover: the joint limits and axes and a limited-versus-free comparison (`test_ragdoll`); corpse hits, misses in the statistics, no damage and pass-through after reset (`test_corpse_hits`); the sniper zero (`test_sniper_zero`); the TTK start time in `RangeStats`, a live feedback test in both modes and the settings toggle (`test_range_stats`, `test_range_feedback`, `test_settings_pause`); both pools and their weapon integration, including the bolt and pump delays (`test_casings_smoke`); and the warm-up twin (`test_particle_warmup`). Movie Maker frames were inspected for a dummy kill with the new joints, a shotgun kill followed by shots into the corpse, the HUD zero label before and after cycling, and a rifle burst with smoke and casings (before and after the billboard fix). Several captures stalled on one repeated frame again (about one in four this milestone) and were repeated.

### Remaining scope

Human play-tests remain pending for Milestones **3–12**; README's Polish play-test lists this milestone's checks. The first-hit stall above is unresolved. Controller gameplay and the web export are still unvalidated future phases; this milestone adds only GDScript, built-in physics, particles and InputMap actions (`zero_cycle`), with no new runtime filesystem access beyond `user://settings.cfg` for the one new setting.
