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
		# Scene-authoring authority: default preview must preserve camera
		# rotations and the editor-authored environment.
		var authored_rotation: Vector3 = camera.rotation_degrees
		var authored_background: Color = world.environment.background_color
		stage.call("godauldron_preview", {
			"motion": "still", "show_placeholder": true, "background": "as_authored"
		})
		if not camera.rotation_degrees.is_equal_approx(authored_rotation) or 				not world.environment.background_color.is_equal_approx(authored_background):
			_fail("Stage startup/preview replaced Godot-authored camera or backdrop")
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
		# Pure translational motion is independently reproducible and moves
		# provider-owned attachments without rotating their transforms.
		clock.bind(stage, {"motion": "translate", "show_placeholder": false}, 1.0 / 60.0)
		if not clock.reset():
			_fail("Cannot reset stage translation fixture")
			return
		var authored_origin: Vector3 = stage.get_node("SubjectMotion").position
		var original_subject_rotation: Vector3 = stage.get_node("SubjectMotion").rotation
		if not clock.seek(60):
			_fail("Translation timeline could not seek to frame 60")
			return
		var translated: Vector3 = stage.get_node("SubjectMotion").position
		if translated.distance_to(authored_origin) < 0.10 or \
				not stage.get_node("SubjectMotion").rotation.is_equal_approx(original_subject_rotation):
			_fail("Generic translation was missing or inadvertently rotated subject")
			return
		if not clock.seek(0) or not stage.get_node("SubjectMotion").position.is_equal_approx(authored_origin):
			_fail("Translation reset did not preserve authored rig origin")
			return
		if not clock.seek(60) or stage.get_node("SubjectMotion").position.distance_to(translated) > 0.000001:
			_fail("Identical fixed input did not reproduce translation")
			return
		if provided.get_parent() != anchor:
			_fail("Translation displaced provider-owned attached node")
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

	# An entirely experiment-owned scene inherits the lighting/camera stage
	# while adding a native/provider payload node under SubjectAnchor.
	var composed: PackedScene = load("res://experiments/showcase-example/scenes/portrait_with_project_subject.tscn") as PackedScene
	if composed == null or not _select(host, "org.godauldron.project-owned-scene"):
		_fail("Example project-owned scene was not loadable by generic discovery")
		return
	var authored: Node3D = host.get("_active_scene")
	var example_node: Node = authored.get_node_or_null("SubjectMotion/SubjectAnchor/ExampleSubjectMarker")
	if example_node == null or not example_node is MeshInstance3D:
		_fail("Inherited project stage lost independently authored scene content")
		return
	authored.call("godauldron_seek", 0.9)
	if example_node.get_parent() != authored.get_node("SubjectMotion/SubjectAnchor"):
		_fail("Stage motion displaced externally authored content")
		return

	# The optional portrait reference must be a real imported textured
	# MakeHuman GLB rather than another group of procedural spheres.
	if not _select(host, "org.godauldron.portrait-reference-head"):
		_fail("Bundled CC0 portrait head is not discoverable")
		return
	var portrait: Node3D = host.get("_active_scene")
	var human_root: Node = portrait.get_node_or_null(
		"SubjectMotion/SubjectAnchor/MakeHumanBodyOrigin/MakeHumanReference"
	)
	if human_root == null:
		_fail("CC0 reference model did not load into portrait stage")
		return
	var nodes: Array[Node] = [human_root]
	var meshes: int = 0
	var vertices: int = 0
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		if node is MeshInstance3D:
			var item: MeshInstance3D = node
			if item.mesh != null:
				meshes += 1
				vertices += item.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		for child in node.get_children():
			nodes.append(child)
	if meshes == 0 or vertices < 4000:
		_fail("Imported reference lacks substantive human mesh detail")
		return
	var markers: Node3D = portrait.get_node("SubjectMotion/SubjectAnchor/ScalpLandmarks_PROVISIONAL")
	if markers.visible or markers.get_child_count() < 5:
		_fail("Provisional scalp locations must be available but hidden by default")
		return
	var human_origin: Node3D = portrait.get_node("SubjectMotion/SubjectAnchor/MakeHumanBodyOrigin")
	if not is_equal_approx(human_origin.position.y, -1.55):
		_fail("Reference character scale/rig origin changed unexpectedly")
		return
	var portrait_playback = Playback.new()
	portrait_playback.bind(portrait, {
		"motion": "translate", "show_placeholder": false, "background": "as_authored"
	}, 1.0 / 60.0)
	portrait_playback.reset()
	var portrait_root_origin: Vector3 = human_root.global_position
	if not portrait_playback.seek(60) or human_root.global_position.distance_to(portrait_root_origin) < 0.10:
		_fail("Reference portrait did not follow generic attachment translation")
		return
	if not portrait_playback.seek(0) or human_root.global_position.distance_to(portrait_root_origin) > 0.000001:
		_fail("Imported reference changed position after translation rewind")
		return
	# This validates Godot import and scene composition only; image quality
	# and vertex-accurate scalp attachment remain hardware visual checks.

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
