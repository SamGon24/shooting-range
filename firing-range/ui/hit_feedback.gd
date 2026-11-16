class_name HitFeedback
extends RefCounted
## Presentation priority for one authoritative target damage event.

enum Kind { HIT, ARMOR_BREAK, KILL }


static func pick(plate_breaks: int, killed: bool) -> Kind:
	if killed:
		return Kind.KILL
	return Kind.ARMOR_BREAK if plate_breaks > 0 else Kind.HIT
