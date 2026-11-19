# Project: Firing Range (FPS MVP)

A first-person shooter MVP: a military-style firing range for testing weapons and gunplay feel, inspired by the modern battle-royale firing ranges. Realistic ballistics and a smooth, responsive feel matter more than visuals.

## Hard constraints

- **Target machine:** Intel MacBook Pro, quad-core i5, 8 GB RAM, Intel Iris Plus integrated GPU, macOS Sequoia. Hold **60 fps at 1280x720**, and check this at every milestone.
- **Engine:** Godot 4.x (latest stable), **GDScript with static typing everywhere**.
- **Physics:** set `physics/3d/physics_engine = Jolt Physics`. Physics tick is 60 Hz; never write gameplay logic that depends on frame rate.
- **Renderer:** Compatibility (OpenGL). On the target Intel GPU, Mobile logs engine shader errors on every boot and cannot render a sky or stable sun shadows; Compatibility has none of those faults and still runs at well over twice the 60 fps budget. OpenGL on macOS does not enforce vsync, so the frame rate is capped at 60 in `project.godot`. The evidence is in `docs/DECISIONS.md`; don't switch renderer without re-running those captures and recording the result there.
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
- Commit rules:
  - The git repo root is `SHOOTER/`. All work and commits happen on `dev`. Merge `dev` into `main` only when a phase is complete, using `--no-ff`. Never push. The owner pushes. Leave `backup/main-linear` untouched unless the owner explicitly requests its deletion.
  - One commit per logical change: a single responsibility that reverts cleanly on its own. Config, code, tests and docs for unrelated changes go in separate commits. A test goes in the same commit as the code it covers.
  - Commit as you go: commit each piece as soon as it works and its tests pass, not in one batch at the end, so the commit order and times follow the order the work was actually done in.
  - Every commit must leave the project booting and its tests passing. No broken intermediate commits.
  - Message format: an imperative subject of 72 characters or fewer with a scope prefix (`player:`, `weapons:`, `ui:`, `range:`, `debug:`, `tests:`, `docs:`, `ballistics:`, `targets:`, `render:`), a blank line, then a short body explaining what changed and why.
  - No `Co-Authored-By` trailers or any other AI attribution lines in commit messages.
  - Never use `--amend`, rebase, or change commit dates on existing commits.
- Log non-obvious choices (renderer, drag model, tuning values) in `docs/DECISIONS.md`.
- If a feature costs too much performance on the target machine, say so and propose a cheaper version. Don't silently drop it.