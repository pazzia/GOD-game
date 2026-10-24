extends "res://tests/review_app_host.gd"
var blocked_level: String=""
func _json(path: String) -> Dictionary:
	if not blocked_level.is_empty() and path.ends_with("/"+blocked_level+".json"):return {}
	return super._json(path)
