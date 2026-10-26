extends SceneTree
## Structured host log contract, capacity, provider boundaries and UI wiring.

const HostDiagnostics = preload("res://scripts/host_diagnostics.gd")
const ExperimentRun = preload("res://scripts/experiment_run.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var log = HostDiagnostics.new()
	if not log.record("info", "host", "ready", "Host initialized", {"count": 1}) or \
			log.record("critical", "host", "bad", "Invalid severity") or \
			log.record("info", "host", "bad", "Object", {"node": Node.new()}):
		_fail("Event validation accepted invalid levels or executable/non-JSON values")
		return
	var events: Array = [
		{"level": "warning", "source": "untrusted", "code": "note", "message": "Valid message", "context": {"sample": 3}},
		{"level": "error", "source": "untrusted", "code": "invalid", "message": "Bad object", "context": {"bad": Vector3.ONE}}
	]
	var ingestion: Dictionary = log.ingest_provider(events, "provider")
	if ingestion != {"accepted": 1, "rejected": 1} or log.entries("warning").size() != 1 or \
			log.entries("error").size() != 0:
		_fail("Post-run provider event ingestion accepted invalid content")
		return
	for i in range(HostDiagnostics.CAPACITY + 12):
		if not log.record("info", "test", "loop", "Bounded log message"):
			_fail("Bounded event ingestion unexpectedly failed")
			return
	var snapshot: Dictionary = log.snapshot()
	if snapshot["event_count"] != HostDiagnostics.CAPACITY or snapshot["dropped_oldest"] != 14 or \
			log.entries().front()["sequence"] != 15:
		_fail("Bounded diagnostics ring did not account for overwritten events")
		return
	var save_root: String = "user://diagnostics-test-%d" % OS.get_process_id()
	var saved: Dictionary = log.export(save_root)
	if not saved.get("ok", false):
		_fail("Atomic diagnostic export failed")
		return
	var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved["path"]))
	if typeof(persisted) != TYPE_DICTIONARY or \
			persisted["event_count"] != HostDiagnostics.CAPACITY or \
			persisted["entries"][0]["sequence"] != 15:
		_fail("Diagnostic JSON export lost ordering or overwrite accounting")
		return
	log.clear()
	if log.snapshot()["event_count"] != 0 or log.snapshot()["dropped_oldest"] != 0:
		_fail("Clearing diagnostics left stale events")
		return

	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var console: VBoxContainer = host.get("_console_panel")
	if console.visible or host.get("_diagnostics").entries("info").size() < 1:
		_fail("Laboratory did not initialize hidden structured messages console")
		return
	host.call("_toggle_diagnostics_console")
	if not console.visible or not (host.get("_console_text") as TextEdit).text.contains("selected"):
		_fail("F3 message console did not render current experiment history")
		return
	(host.get("_console_filter") as OptionButton).select(2)
	host.call("_refresh_diagnostics_console")
	if (host.get("_console_text") as TextEdit).text.contains("selected"):
		_fail("Severity filter kept info events in warning-only view")
		return
	(host.get("_console_filter") as OptionButton).select(0)
	host.call("_refresh_diagnostics_console")
	var source_scene: Node = host.get("_active_scene")
	var viewport: SubViewport = host.get("_viewport")
	viewport.remove_child(source_scene)
	source_scene.queue_free()
	var probe: Node3D = preload("res://tests/fixtures/diagnostic_provider.gd").new()
	viewport.add_child(probe)
	host.set("_active_scene", probe)
	(host.get("_run_steps") as SpinBox).value = 2
	(host.get("_warmup_steps") as SpinBox).value = 0
	var result_folder: String = "user://diagnostic-run-test-%d" % OS.get_process_id()
	host.set("_results_directory", result_folder)
	host.call("_start_run")
	if not bool(host.call("_has_active_run")):
		_fail("Could not launch run to test post-sample provider diagnostics")
		return
	host.call("_toggle_diagnostics_console")
	if not console.visible:
		_fail("Benchmark was allowed to reflow diagnostics console")
		return
	var run: RefCounted = host.get("_run")
	for i in range(2):
		run.advance()
	host.call("_finish_run", true)
	if probe.get("diagnostic_queries") != 1:
		_fail("Post-run provider diagnostic hook was not queried exactly once")
		return
	var files: PackedStringArray = DirAccess.get_files_at(result_folder)
	if files.size() != 1:
		_fail("Run diagnostic test did not save exactly one result")
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_folder.path_join(files[0])))
	if typeof(report) != TYPE_DICTIONARY or \
			int(report.get("diagnostic_events", {}).get("provider_ingestion", {}).get("accepted", -1)) != 1 or \
			int(report.get("diagnostic_events", {}).get("provider_ingestion", {}).get("rejected", -1)) != 1 or \
			report.get("diagnostic_events", {}).get("events", []).is_empty():
		_fail("Completed run did not preserve validated post-run diagnostic evidence")
		return
	var export_folder: String = "user://ui-diagnostics-test-%d" % OS.get_process_id()
	host.set("_diagnostics_directory", export_folder)
	host.call("_export_diagnostics_console")
	if DirAccess.get_files_at(export_folder).size() != 1:
		_fail("Console Export JSON action did not persist structured log")
		return
	print("Godauldron diagnostics console smoke passed: filtering, bounded exports and post-run provider events")
	quit(0)
