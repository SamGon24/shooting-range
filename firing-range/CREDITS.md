# Credits

Every third-party asset used in the game is listed here with its source and license.

## Assets

None from third parties.

- **Geometry:** greybox, built in-engine (range, viewmodels, targets and physics props).
- **Sound effects:** placeholder gunshots, clicks, impact ticks, steel rings and hit / armor-break / kill confirmation chirps are synthesised at startup from noise and sine tones by `weapons/effects/sfx_factory.gd`. Confirmation chirps use swept sine tones with an inharmonic overtone; steel rings use decaying tones. They are original to this project; no recordings or samples are used.

## Tooling (not shipped in the game)

- [GUT 9.7.1](https://github.com/bitwes/Gut) by Butch Wesley, MIT. Unit test framework, vendored in `addons/gut/`.
