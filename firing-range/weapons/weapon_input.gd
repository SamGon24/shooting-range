class_name WeaponInput
extends RefCounted
## One tick of player intent for a weapon. Filled by `WeaponController` from
## the input map, or by tests directly.

## Trigger is down this tick.
var trigger_held: bool = false
## Trigger went down this tick.
var trigger_pressed: bool = false
## Aim button is down this tick.
var aim_held: bool = false
## Reload was pressed this tick.
var reload_pressed: bool = false
## The player is sprinting, which blocks firing and aiming.
var sprinting: bool = false
