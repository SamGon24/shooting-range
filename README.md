# SHOOTER

This repository holds **Firing Range**, a first-person shooter MVP built in Godot 4. It is a military-style firing range for testing weapons and gunplay feel. The goal is realistic ballistics (simulated projectiles with gravity and drag, not hitscan) and smooth, responsive movement on modest hardware. The visuals are deliberately greybox.

The Godot project lives in [`firing-range/`](firing-range/). Its [README](firing-range/README.md) is the full developer guide.

## Status

Milestone 1 of 6 is done: movement and a greybox range.

| Area | State |
|---|---|
| FPS movement (walk, sprint, crouch, jump, slide) | Done |
| Camera feel (head bob, landing dip, FOV kick), FOV and sensitivity settings | Done |
| Greybox range with markers at 25/50/100/200/300 m, movement test area | Done |
| Debug overlay and perf probe | Done |
| Weapons, shooting, ballistics, targets, HUD, sound | Not started |

**Tests:** 84 GUT tests (movement math, player integration, range layout), all passing.

**Performance:** holds 60 fps at 1280x720 on the target machine, with about 145 to 190 fps uncapped. The measurements are in [`docs/DECISIONS.md`](firing-range/docs/DECISIONS.md).

## Repository layout

```
SHOOTER/                       git root, branch main
├── README.md                  this file
├── CLAUDE.md                  older copy of the project instructions (see note)
└── firing-range/              Godot 4 project
    ├── README.md              developer guide: setup, controls, tuning, structure
    ├── CLAUDE.md              project instructions and working rules (current)
    ├── CREDITS.md             third-party assets and tools
    ├── docs/DECISIONS.md      design decisions with evidence and measurements
    ├── project.godot
    ├── player/  range/  debug/  tests/
    └── weapons/  ballistics/  targets/  ui/   (later milestones, empty for now)
```

**Note:** the root `CLAUDE.md` is out of date. It still names the Mobile renderer and lacks the current commit rules. `firing-range/CLAUDE.md` is the current version.

## Requirements

- **Godot 4.7.2 stable**, the standard build (not .NET). The code is GDScript with static typing, and physics uses Jolt, which is built into Godot.
- **Target machine:** MacBook Pro, Intel i5-8259U, 8 GB RAM, Intel Iris Plus Graphics 655, macOS Sequoia.
- **Renderer:** Compatibility (OpenGL). On the target Intel GPU, the Mobile renderer logs shader errors and can't draw a sky or stable sun shadows.

## Quick start

These commands assume `godot` points to the Godot binary. On macOS:

```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot
```

```sh
git clone https://github.com/SamGon24/shooting-range.git
cd shooting-range

# One-time import after cloning (builds the .godot/ cache, which isn't committed)
godot --headless --path firing-range --import

# Play
godot --path firing-range

# Run the test suite (about 50 s)
godot --headless --path firing-range -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Controls, the perf probe, tuning values and the project structure are covered in [`firing-range/README.md`](firing-range/README.md).

## Roadmap

- [x] **1. Movement:** FPS controller and greybox range with distance markers
- [ ] **2. Shooting core:** assault rifle and scoped bolt-action sniper, ADS, reloads, weapon switching, viewmodel, muzzle and impact effects
- [ ] **3. Ballistics and recoil:** simulated projectiles with drag and drop, damage falloff, recoil patterns, bullet-path debug view
- [ ] **4. Targets:** hit-zoned dummies with armor plates, moving targets on rails, swinging steel plates
- [ ] **5. Feedback and HUD:** hitmarkers, damage numbers, dynamic crosshair, ammo counter, range stats, placeholder sounds
- [ ] **6. Polish:** physics props, ragdolls, pause and settings menu, performance pass

Each milestone ends with a play-test before the next one starts.

## Principles

- **Original IP only.** No names, logos, art or sounds from existing games. Assets are greybox or CC0, credited in [`CREDITS.md`](firing-range/CREDITS.md).
- **Text-only project files.** Scenes, resources and scripts are `.tscn`, `.tres` and `.gd`, so every change diffs cleanly.
- **Tested and measured.** Deterministic logic gets unit tests, and every milestone is checked against the 60 fps budget on the target machine.

## License

TBD.
