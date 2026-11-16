class_name ProjectileHit
extends RefCounted
## What a projectile reports when it hits something.

## World position of the impact.
var position: Vector3
## Surface normal at the impact, pointing away from the surface.
var normal: Vector3
## The physics object that was hit.
var collider: Object
## Projectile velocity at the moment of impact, m/s.
var velocity: Vector3
## Seconds between firing and impact, to the nearest physics tick.
var travel_time: float
## Path length flown, metres.
var travel_distance: float
## What was fired.
var spec: ProjectileSpec
