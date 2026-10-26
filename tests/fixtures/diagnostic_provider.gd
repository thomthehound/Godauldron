extends Node3D
## Malformed provider data cannot enter the report or execute commands.
var diagnostic_queries: int = 0


func godauldron_setup(_params: Dictionary) -> void:
	diagnostic_queries = 0


func godauldron_step(_delta: float) -> void:
	pass


func godauldron_diagnostics() -> Array:
	diagnostic_queries += 1
	return [
		{"level": "info", "source": "provider", "code": "work_completed",
			"message": "Prepared native results", "context": {"work_items": 32}},
		{"level": "error", "source": "provider", "code": "invalid_object",
			"message": "Refuse object in diagnostic context", "context": {"object": self}}
	]
