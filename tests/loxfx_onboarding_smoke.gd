extends SceneTree
## Consumer contract: native package failure isolation, editable studio stages,
## provider attachment points and deterministic untimed stage playback.
## No LoxFX binaries or synthetic LoxFX hair simulation are shipped.

const NativePackage = preload("res://scripts/native_experiment_package.gd")
const Playback = preload("res://scripts/experiment_playback.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _select(host: Node, identifier: String) -> bool:
	var manifests: Array = host.get("_experiments")
	for index in range(manifests.size()):
		if manifests[index].get("id") == identifier:
			host.call("_select_experiment", index)
			return true
	return false


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var manifests: Array = host.get("_experiments")
	var reference: int = -1
	for index in range(manifests.size()):
		if manifests[index].get("id") == "org.godauldron.reference":
			reference = index
	if reference < 0:
		_fail("Baseline experiment was not discovered")
		return

	# A bad extension must fail before tearing down a working experiment.
	host.call("_select_experiment", reference)
	var working: Node = host.get("_active_scene")
	var missing: Dictionary = manifests[reference].duplicate(true)
	missing["id"] = "org.godauldron.native-missing"
	missing["display_name"] = "Uninstalled GDExtension"
	missing["native_extensions"] = ["res://experiments/native-missing/not-installed.gdextension"]
	manifests.append(missing)
	(host.get("_list") as ItemList).add_item("Uninstalled GDExtension")
	var run_steps: SpinBox = host.get("_run_steps")
	run_steps.value = 6
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_select_experiment", manifests.size() - 1)
	if host.get("_active_scene") != working or not bool(host.call("_has_active_run")):
		_fail("An unavailable native package stopped/replaced the running experiment")
		return
	if not (host.get("_status") as Label).text.contains("descriptor missing"):
		_fail("Missing native dependency did not provide a useful error")
		return
	host.call("_stop_run")

	for kind in ["portrait", "inspection"]:
		var template: String = "res://scenes/showcase/%s_stage.tscn" % kind
		var scene: PackedScene = load(template) as PackedScene
		if scene == null:
			_fail("Cannot edit/instantiate studio template: " + template)
			return
		if not _select(host, "org.godauldron.showcase-" + kind):
			_fail("Studio stage not discoverable through manifest: " + kind)
			return
		var stage: Node3D = host.get("_active_scene")
		var anchor: Node3D = stage.get_node("SubjectMotion/SubjectAnchor")
		var placeholder: Node3D = stage.get_node("SubjectMotion/NeutralSubject")
		var camera: Camera3D = stage.get_node("StageCamera")
		var world: WorldEnvironment = stage.get_node("StageEnvironment")
		var key_light: DirectionalLight3D = stage.get_node("KeySoft")
		var fill: OmniLight3D = stage.get_node("FillSoft")
		var rim: OmniLight3D = stage.get_node("RimBack")
		if anchor == null or camera == null or not camera.current or world == null or \
				key_light == null or fill == null or rim == null:
			_fail("A showcase stage lacks its editable camera/light/attachment rig")
			return
		# Adding provider-owned nodes to the anchor must not be disturbed by
		# stage stepping or by hiding the optional neutral reference subject.
		var provided := Node3D.new()
		provided.name = "ProviderOwnedVisual"
		anchor.add_child(provided)
		stage.call("godauldron_preview", {
			"motion": "turn", "show_placeholder": false, "background": "light"
		})
		if placeholder.visible or provided.get_parent() != anchor:
			_fail("Optional placeholder toggle destroyed or displaced provider content")
			return
		var clock = Playback.new()
		var parameters := {"motion": "turn", "show_placeholder": false, "background": "light"}
		clock.bind(stage, parameters, 1.0 / 60.0)
		if not clock.reset():
			_fail("A stage cannot reset its presentation timeline")
			return
		var origin: Vector3 = stage.get_node("SubjectMotion").rotation
		for step in range(90):
			if not clock.step():
				_fail("Deterministic stage step unavailable")
				return
		var moved: Vector3 = stage.get_node("SubjectMotion").rotation
		if moved.distance_to(origin) < 0.01:
			_fail("Moving stage anchor did not animate")
			return
		if not clock.seek(0) or stage.get_node("SubjectMotion").rotation.distance_to(origin) > 0.000001:
			_fail("Stage did not return to its baseline pose")
			return
		if not clock.seek(90) or stage.get_node("SubjectMotion").rotation.distance_to(moved) > 0.000001:
			_fail("Stage did not reproduce the same pose at a specified frame")
			return
		stage.call("godauldron_preview", {
			"motion": "still", "show_placeholder": true, "background": "slate"
		})
		clock.bind(stage, {"motion": "still", "show_placeholder": true}, 1.0 / 60.0)
		clock.reset()
		var still: Vector3 = stage.get_node("SubjectMotion").rotation
		if not clock.seek(120) or stage.get_node("SubjectMotion").rotation.distance_to(still) > 0.000001:
			_fail("Stationary visual reference did not remain stationary")
			return
		if stage.get_node("SubjectMotion/SubjectAnchor/ProviderOwnedVisual") != provided:
			_fail("Presentation resets removed an experiment-owned visual node")
			return
		var metadata: Dictionary = stage.call("godauldron_capture_metadata")
		if metadata.get("stage_kind") != kind or not metadata.has("stage_camera_fov"):
			_fail("Stage capture metadata omitted presentation conditions")
			return
		if bool(stage.call("godauldron_metrics").get("simulation_performance_claimed", true)):
			_fail("Presentation-stage metrics claim simulation performance")
			return

	# Confirm the actual host playback UI remains independent of timed runs.
	if not _select(host, "org.godauldron.showcase-portrait"):
		_fail("Could not return to portrait stage")
		return
	host.call("_reset_playback")
	host.call("_step_playback")
	if bool(host.call("_has_active_run")) or host.get("_run") != null:
		_fail("Interactive stage stepping incorrectly created a benchmark")
		return
	if int((host.get("_playback")).snapshot().get("steps", -1)) != 1:
		_fail("Single-step playback did not advance exactly once")
		return
	host.call("_seek_playback", 1.0)
	if int((host.get("_playback")).snapshot().get("steps", -1)) != 60:
		_fail("Timeline UI failed to seek to a reproducible frame")
		return
	host.call("_toggle_playback")
	host.call("_process", 0.1)
	host.call("_toggle_playback")
	var paused: int = (host.get("_playback")).step_index
	if paused <= 60 or (host.get("_playback")).playing:
		_fail("Play/Pause failed to advance then stop the unmeasured stage timeline")
		return
	host.call("_process", 0.1)
	if (host.get("_playback")).step_index != paused or host.get("_run") != null:
		_fail("Paused stage continued moving or fabricated measured samples")
		return
	run_steps.value = 2
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")):
		_fail("Measured stage fixture did not finish after interactive playback")
		return

	var label: Dictionary = NativePackage.display_path({"visualization_path": "diagnostic_cpu_bridge"})
	if label["kind"] != "diagnostic_cpu_bridge" or not String(label["disclaimer"]).contains("not production"):
		_fail("CPU diagnostic display was mislabeled as native production performance")
		return
	if not _select(host, "org.godauldron.technical-gallery"):
		_fail("Missing negative-control experiment without simulation step")
		return
	host.call("_toggle_playback")
	if (host.get("_playback")).playing:
		_fail("Experiment without a step callback entered fake playback")
		return
	print("Godauldron native package and showcase-stage smoke passed")
	quit(0)
