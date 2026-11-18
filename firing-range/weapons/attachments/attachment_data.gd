class_name AttachmentData
extends Resource

@export var id: StringName
@export var display_name: String
@export var slot: WeaponTypes.Slot
@export var compatible_classes: PackedInt32Array
@export var modifiers: Array[StatModifier] = []
@export var part_scene: PackedScene
@export var part_mount: NodePath = NodePath("Mount")
## -1 inherits the base weapon optic. Others select presentation explicitly.
@export_enum("Inherit:-1", "Iron:0", "Red dot:1", "2x:2", "4x:3", "8x:4", "Hybrid 3.5x:5") var optic_kind: int = -1
@export var optic_fov_degrees: float = 45.0
@export var optic_sight_height_m: float = 0.05


func accepts(weapon_class: WeaponTypes.Class) -> bool:
	return WeaponTypes.allows_slot(weapon_class, slot) and compatible_classes.has(weapon_class)

## Nonzero only for optics whose zoom follows the selected player FOV.
@export var optic_magnification: float = 0.0
