extends SceneTree
## Native-authored C++ compute shader, descriptors, push constant, pipeline
## and commands recorded through Godot RenderingDevice on Godot's VkImage.
## This test rejects the legacy script-authored shader/dispatch path.

const Package = preload("res://scripts/native_experiment_package.gd")
const EXPECTED_ELEMENTS := 64


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus" or \
			RenderingServer.get_current_rendering_driver_name() != "vulkan":
		_fail("Actual Vulkan Forward+ renderer required")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/native-vulkan-provider/manifest.json"))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false):
		_fail("Native GDExtension was not installed or did not load")
		return
	var host: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	var viewport: SubViewport = host.get("_viewport")
	var old_scene: Node = host.get("_active_scene")
	viewport.remove_child(old_scene)
	old_scene.queue_free()
	var stage: Node3D = (load(manifest["entry_scene"]) as PackedScene).instantiate()
	viewport.add_child(stage)
	host.set("_active_scene", stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	stage.add_child(world)
	for i in range(7):
		await process_frame
	var native: Object = stage.get("_native")
	var camera: Camera3D = viewport.get_camera_3d()
	if native == null or camera == null or \
			not native.has_method("inspect_godot_vulkan_image") or
			not native.has_method("record_godot_image_compute") or camera.compositor != null:
		_fail("Native resource-witness method or active scene-owned camera missing")
		return
	var effect_script: GDScript = load(
		"res://experiments/native-vulkan-provider/godot_shared_device_effect.gd")
	if effect_script == null:
		_fail("Installed same-device compositor effect is missing")
		return
	var effect: CompositorEffect = effect_script.new(native, true)
	var original: Compositor = camera.compositor
	var temporary := Compositor.new()
	var effects: Array[CompositorEffect] = [effect]
	temporary.compositor_effects = effects
	camera.compositor = temporary
	if not effect.request():
		_fail("Godot-owned VkImage inspection could not be armed")
		return
	var state: Dictionary = {}
	for i in range(180):
		await process_frame
		state = effect.status()
		if state.get("state") in ["ready", "failed"]:
			break
	if state.get("state") != "ready":
		_fail("Shared Vulkan resource proof did not resolve: " + str(state))
		return
	var result: Dictionary = effect.take_result()
	var witness: Dictionary = result.get("witness", {})
	var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
	var native_record: Dictionary = result.get("native_record", {})
	if not result.get("ok", false) or bytes.size() != EXPECTED_ELEMENTS * 4 or \
			not witness.get("available", false) or \
			witness.get("backend") != "Vulkan" or \
			witness.get("resource_owner") != "godot_global_rendering_device" or \
			witness.get("queue_submission_owner") != "godot_rendering_device" or \
			int(witness.get("image_required_bytes", -1)) != EXPECTED_ELEMENTS * 4 or \
			int(witness.get("image_allocation_requirement_bytes", 0)) < EXPECTED_ELEMENTS * 4 or
			native_record.get("native_execution") != "native_cpp_recorded_godot_rendering_device_commands" or
			native_record.get("shader_source") != "native_build_embedded_compiled_spirv" or
			int(native_record.get("seed", -1)) != 37 or
			int(native_record.get("local_invocations", -1)) != EXPECTED_ELEMENTS or
			native_record.has("owned_rids") or
			native_record.get("queue_submission_owner") != "godot_rendering_device":
		_fail("Native VkDevice/VkImage identity or actual GPU readback was unavailable")
		return
	for i in range(EXPECTED_ELEMENTS):
		if bytes.decode_u32(i * 4) != 37 + i:
			_fail("Native-authored compute produced incorrect spatial data at pixel %d" % i)
			return
	# Do not free Godot-owned image or native device. The compositor no longer
	# owns the frame after this capture; the witness kept no raw handles.
	camera.compositor = original
	if camera.compositor != null or not ClassDB.class_exists("NativeGpuProbe3D"):
		_fail("Shared-device diagnostic leaked compositor ownership")
		return
	if RenderingServer.get_current_rendering_driver_name() != "vulkan":
		_fail("Renderer driver unexpectedly changed")
		return
	print("Native-authored Godot RD compute verified: C++ embedded SPIR-V, engine-managed descriptors, ",
		EXPECTED_ELEMENTS, " distinct shader-written pixels, push constant, GPU readback")
	quit(0)
