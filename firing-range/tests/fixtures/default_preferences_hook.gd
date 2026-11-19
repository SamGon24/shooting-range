extends GutHookScript
## Pre-run hook: tests run against default preferences, not the player's saved
## user://settings.cfg (auto sprint, toggles and so on change movement and
## weapon behaviour). Only the in-memory values change; nothing is saved.


func run() -> void:
	var view_settings: Node = Engine.get_main_loop().root.get_node_or_null("ViewSettings")
	if view_settings == null:
		return
	var defaults: Node = (load("res://player/view_settings.gd") as GDScript).new() as Node
	for key: String in view_settings.get("KEYS"):
		view_settings.set(key, defaults.get(key))
	defaults.free()
