class_name GuardData
extends Resource
## Gameplay collider, independent of the animated shield viewmodel.
@export var size_m: Vector3 = Vector3(0.65, 1.25, 0.08)
@export var eye_offset_m: Vector3 = Vector3(0, -0.25, -0.6)
@export_flags_3d_physics var collision_layer: int = 8
