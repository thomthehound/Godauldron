extends SceneTree
## Consumer onboarding contract: native package isolation and deterministic,
## untimed visual reference playback. No LoxFX binary is bundled in CI.

const NativePackage = preload("res://scripts/native_experiment_package.gd")
const Playback = preload("res://scripts/experiment_playback.gd")


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _vertices(scene: Node) -> PackedVector3Array:
	var head: Node3D = scene.get_node("HeadMotion")
	var hair: MeshInstance3D = head.get_node("CPUHairRibbons_Diagnostic")
	return hair.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _equivalent(a: PackedVector3Array, b: PackedVector3Array, epsilon: float = 0.00001) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].distance_to(b[i]) > epsilon:
			return false
	return true


func _verify() -> void:
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var manifest_list: Array = host.get("_experiments")
	var reference_index: int = -1
	var hair_index: int = -1
	for i in range(manifest_list.size()):
		match String(manifest_list[i].get("id", "")):
			"org.godauldron.reference":
				reference_index = i
			"org.godauldron.hair-reference":
				hair_index = i
	if reference_index < 0 or hair_index < 0:
		_fail("Reference and hair experiment packages were not discovered")
		return

	# Reject an absent extension BEFORE disrupting a valid active benchmark.
	host.call("_select_experiment", reference_index)
	var working: Node = host.get("_active_scene")
	var bad: Dictionary = manifest_list[reference_index].duplicate(true)
	bad["id"] = "org.godauldron.native-missing"
	bad["display_name"] = "Uninstalled native extension"
	bad["native_extensions"] = ["res://experiments/native-missing/loxfx.gdextension"]
	manifest_list.append(bad)
	(host.get("_list") as ItemList).add_item("Uninstalled native extension")
	var run_steps: SpinBox = host.get("_run_steps")
	run_steps.value = 6
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_select_experiment", manifest_list.size() - 1)
	if host.get("_active_scene") != working or not bool(host.call("_has_active_run")):
		_fail("Missing native binary destroyed the working experiment or run")
		return
	if not (host.get("_status") as Label).text.contains("descriptor missing"):
		_fail("Missing native extension did not surface a useful error")
		return
	host.call("_stop_run")

	if not bool(NativePackage.preflight(manifest_list[hair_index]).get("ok", false)):
		_fail("Portable visual-only experiments should require no native binaries")
		return
	host.call("_select_experiment", hair_index)
	var stage: Node3D = host.get("_active_scene")
	if stage == null or not stage.has_method("godauldron_seek"):
		_fail("Hair studio did not load its deterministic playback interface")
		return
	var values: Dictionary = {
		"groom": "long_waves", "motion": "turn", "seed": 23,
		"density": 120, "background": "slate", "guides": true
	}
	var playback = Playback.new()
	playback.bind(stage, values, 1.0 / 60.0)
	if not playback.reset():
		_fail("Hair reference cannot reset independently of benchmark runs")
		return
	var initial: PackedVector3Array = _vertices(stage)
	if initial.size() != 120 * 12 * 6:
		_fail("Hair fixture density was not applied to generated geometry")
		return
	for step in range(90):
		if not playback.step():
			_fail("A deterministic hair playback step was rejected")
			return
	var stepped: PackedVector3Array = _vertices(stage)
	if _equivalent(initial, stepped):
		_fail("Moving diagnostic groom did not change between head poses")
		return
	if not playback.seek(0):
		_fail("Rewinding an analytic groom failed")
		return
	if not _equivalent(initial, _vertices(stage)):
		_fail("Returning to timeline origin failed to reproduce original strands")
		return
	if not playback.seek(90) or not _equivalent(stepped, _vertices(stage)):
		_fail("Seeking to an exact step did not reproduce deterministic hair")
		return
	playback.bind(stage, values, 1.0 / 60.0)
	playback.reset()
	for step in range(90):
		playback.step()
	if not _equivalent(stepped, _vertices(stage)):
		_fail("Repeated fixed-input playback has diverged")
		return

	values["motion"] = "still"
	playback.bind(stage, values, 1.0 / 60.0)
	playback.reset()
	var still: PackedVector3Array = _vertices(stage)
	if not playback.seek(120) or not _equivalent(still, _vertices(stage)):
		_fail("Stationary hair comparison changed over timeline")
		return
	var camera: Camera3D = stage.get_node("PortraitCamera")
	if camera == null or not camera.current:
		_fail("Hair stage did not supply an inspection camera")
		return
	var snapshot: Dictionary = stage.call("godauldron_capture_metadata")
	if snapshot.get("display_path") != "host_cpu_procedural_ribbon_reference":
		_fail("Diagnostic hair path was mislabeled")
		return

	# UI playback must not create reports or count performance samples.
	host.call("_reset_playback")
	host.call("_step_playback")
	if host.get("_run") != null or bool(host.call("_has_active_run")):
		_fail("Manual playback was incorrectly recorded as a measured run")
		return
	var ui: Dictionary = (host.get("_playback")).snapshot()
	if int(ui.get("steps", -1)) != 1:
		_fail("Manual single-step did not advance one fixed timestep")
		return
	host.call("_seek_playback", 1.0)
	if int((host.get("_playback")).snapshot()["steps"]) != 60:
		_fail("Timeline UI could not seek to a reproducible second")
		return
	run_steps.value = 2
	host.call("_start_run")
	host.call("_process", 1.0 / 60.0)
	host.call("_process", 1.0 / 60.0)
	if bool(host.call("_has_active_run")):
		_fail("Measured run did not finish independently of previous playback")
		return
	var label: Dictionary = NativePackage.display_path(manifest_list[hair_index])
	if label["kind"] != "diagnostic_cpu_bridge" or not String(label["disclaimer"]).contains("not production"):
		_fail("Diagnostic display was presented as production simulation performance")
		return
	print("Godauldron native onboarding and animated hair playback smoke passed")
	quit(0)
