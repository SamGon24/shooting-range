class_name ProjectileSpec
extends Resource
## What a weapon fires. Units are SI. Milestone 3 adds drag and damage
## fields here; nothing that uses this resource needs to change for that.

## Speed leaving the barrel, m/s.
@export_range(50.0, 1500.0, 1.0, "suffix:m/s") var muzzle_velocity: float = 850.0
## Multiplies world gravity for this projectile. 1 is real gravity.
@export_range(0.0, 2.0, 0.01) var gravity_scale: float = 1.0
## The projectile is removed after this long without hitting anything.
@export_range(0.1, 10.0, 0.1, "suffix:s") var max_lifetime: float = 3.0
