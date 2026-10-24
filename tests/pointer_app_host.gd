extends "res://tests/review_app_host.gd"
var ui_commands: Array=[]
func _command(kind: String,payload: Dictionary={}) -> bool:
	var accepted: bool=super._command(kind,payload)
	ui_commands.append({"type":kind,"payload":payload.duplicate(true),"accepted":accepted})
	return accepted
