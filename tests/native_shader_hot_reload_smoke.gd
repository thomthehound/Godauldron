extends SceneTree
## Real native Vulkan hot reload with compiler, pipeline retirement and
## fence-backed rollback. Run under VK_LAYER_KHRONOS_validation in CI.

const Package = preload("res://scripts/native_experiment_package.gd")
const Runner = preload("res://scripts/experiment_run.gd")
const PipelineDiagnostics = preload("res://scripts/provider_pipeline_diagnostics.gd")
const ProviderControls = preload("res://scripts/provider_runtime_controls.gd")
const SAMPLES := 6


func _initialize() -> void:
	call_deferred("_verify")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _run_epoch(scene: Node) -> Dictionary:
	var run := Runner.new()
	run.begin(scene, {}, 2, SAMPLES, 1.0 / 60.0)
	# Real GPU submission must make reload unsafe even if the host UI
	# were bypassed and the request went straight to the native provider.
	# Two warmup steps arm sampling; the third step submits GPU work.
	for i in range(3):
		run.advance()
	var native: Node = scene.get("_native")
	var rejected: Dictionary = native.call("godauldron_replace_shader",
		PackedByteArray([3, 2, 35, 7]))
	if rejected.get("ok", false) or rejected.get("failure_stage") != "in_flight":
		return {"ok": false, "error": "Native GPU allowed replacement during live submissions"}
	var generation: int = int(rejected["generation"])
	for frame in range(2 + SAMPLES + 2):
		if run.phase == Runner.Phase.COMPLETED:
			break
		run.advance()
	if run.phase != Runner.Phase.COMPLETED:
		return {"ok": false, "error": "Native epoch did not finish"}
	var report: Dictionary = run.make_report("org.godauldron.native-vulkan-device-probe")
	var timeline: Dictionary = report.get("provider_gpu_timeline", {})
	if not timeline.get("available", false) or \
			int(timeline.get("expected_steps", -1)) != SAMPLES or \
			int(timeline.get("host_wait_count", 0)) != 1:
		return {"ok": false, "error": "GPU output/fence proof missing: " + str(timeline)}
	var after: Dictionary = PipelineDiagnostics.read(scene)
	if not after.get("available", false) or \
			int(after["pipelines"][0]["reload_generation"]) != generation:
		return {"ok": false, "error": "Reload state changed during measured GPU epoch"}
	return {"ok": true}


func _verify() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/native-vulkan-provider/manifest.json"))
	if typeof(manifest) != TYPE_DICTIONARY or \
			not Package.preflight(manifest).get("ok", false):
		_fail("Native Vulkan experiment package missing")
		return
	var stage: PackedScene = load(manifest["entry_scene"])
	var scene: Node3D = stage.instantiate()
	root.add_child(scene)
	for frame in range(4):
		await process_frame
	var native: Node = scene.get("_native")
	if native == null:
		_fail("Native Vulkan provider did not instantiate")
		return
	var source_path := "res://experiments/native-vulkan-provider/reload_compute.comp"
	if not FileAccess.file_exists(source_path):
		_fail("Editable provider source shader missing from installed package")
		return

	var initial: Dictionary = scene.call("godauldron_reload_shader")
	if not initial.get("ok", false) or int(initial.get("generation", -1)) != 1 or \
			int(initial.get("retired_pipelines", -1)) != 1:
		_fail("Native Vulkan PSO replacement failed: " + str(initial))
		return
	var prepared: Dictionary = PipelineDiagnostics.read(scene)
	if not prepared.get("available", false):
		_fail("Native replacement diagnostic contract invalid: " + str(prepared))
		return
	var details: Dictionary = prepared["pipelines"][0]
	if int(details.get("pipeline_creations", -1)) != 2 or \
			int(details.get("shader_creations", -1)) != 2 or \
			int(details.get("reload_generation", -1)) != 1:
		_fail("Actual shader/module pipeline recompilation was not recorded")
		return

	# Compilation and bytecode failure must leave the generation, PSO
	# identity and already accepted shader intact.
	var bad_file: FileAccess = FileAccess.open("user://bad_native_shader.comp", FileAccess.WRITE)
	if bad_file == null:
		_fail("Could not create shader compilation failure fixture")
		return
	bad_file.store_string("#version 450\nnot_a_shader !!!\n")
	bad_file.close()
	var bad_compile: Dictionary = scene.call("godauldron_reload_shader_from_source",
		"user://bad_native_shader.comp")
	if bad_compile.get("ok", true) or bad_compile.get("stage") != "compile":
		_fail("Broken GLSL was not rejected before touching the native PSO")
		return
	var incompatible: FileAccess = FileAccess.open("user://bad_native_binding.comp",
		FileAccess.WRITE)
	if incompatible == null:
		_fail("Could not write shader binding contract fixture")
		return
	incompatible.store_string("#version 450\nlayout(local_size_x=64) in;\n" +
		"layout(set=0,binding=1,std430) buffer Counters { uint values[]; } c;\n" +
		"void main(){atomicAdd(c.values[gl_GlobalInvocationID.x],1u);}\n")
	incompatible.close()
	var bad_interface: Dictionary = scene.call("godauldron_reload_shader_from_source",
		"user://bad_native_binding.comp")
	if bad_interface.get("ok", true) or bad_interface.get("stage") != "shader":
		_fail("Incompatible shader resource binding was accepted for old native descriptor set")
		return
	var bad_bytes: Dictionary = scene.call("godauldron_replace_shader_bytes",
		PackedByteArray([5, 6, 7, 8]))
	if bad_bytes.get("ok", true) or bad_bytes.get("failure_stage") != "shader" or \
			int(bad_bytes.get("generation", -1)) != 1:
		_fail("Malformed SPIR-V candidate replaced the working native pipeline")
		return
	var after_failure: Dictionary = PipelineDiagnostics.read(scene)
	var source_result: Dictionary = after_failure.get("source_reload", {})
	if not after_failure.get("available", false) or \
			int(after_failure["pipelines"][0].get("reload_retired_pipelines", -1)) != 1 or \
			int(after_failure["pipelines"][0].get("reload_failures", -1)) != 2 or \
			int(source_result.get("failures", -1)) != 2 or \
			int(source_result.get("attempts", -1)) != 3 or \
			source_result.get("last_stage") != "shader" or \
			not PipelineDiagnostics.summary(after_failure).contains("descriptor"):
		_fail("Shader failure failed to preserve resource ownership/provenance")
		return

	# The same set/binding numbers cannot disguise a different resource.
	# These candidates compile to valid SPIR-V but violate the existing PSO
	# descriptor type/count or push-constant ABI. Reject before Vulkan calls.
	for broken in [
		{"name": "storage_image", "source":
			"#version 450\nlayout(local_size_x=64) in;\n" +
			"layout(set=0,binding=0,r32ui) uniform uimage2D image_out;\n" +
			"void main(){imageAtomicAdd(image_out,ivec2(gl_GlobalInvocationID.x,0),1u);}\n"},
		{"name": "uniform_buffer", "source":
			"#version 450\nlayout(local_size_x=64) in;\n" +
			"layout(set=0,binding=0) uniform Params { uint delta; } p;\n" +
			"void main(){uint unused_value=p.delta;}\n"},
		{"name": "descriptor_array", "source":
			"#version 450\nlayout(local_size_x=64) in;\n" +
			"layout(set=0,binding=0,std430) buffer Counters { uint value[4096]; } c[2];\n" +
			"void main(){atomicAdd(c[0].value[gl_GlobalInvocationID.x],1u);}\n"},
		{"name": "push_constant", "source":
			"#version 450\nlayout(local_size_x=64) in;\n" +
			"layout(set=0,binding=0,std430) buffer Counters { uint value[]; } c;\n" +
			"layout(push_constant) uniform Params { uint delta; } p;\n" +
			"void main(){atomicAdd(c.value[gl_GlobalInvocationID.x],p.delta);}\n"}
	]:
		var path: String = "user://native_reload_wrong_%s.comp" % broken["name"]
		var source_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if source_file == null:
			_fail("Could not stage incompatible shader: " + path)
			return
		source_file.store_string(broken["source"])
		source_file.close()
		var rejected: Dictionary = scene.call("godauldron_reload_shader_from_source", path)
		if rejected.get("ok", true) or rejected.get("stage") != "shader" or \
				int(rejected.get("generation", -1)) != 1:
			_fail("Incompatible shader resource type/count was accepted: " +
				String(broken["name"]) + " " + str(rejected))
			return
	var after_abi: Dictionary = PipelineDiagnostics.read(scene)
	if not after_abi.get("available", false) or \
			int(after_abi["pipelines"][0]["reload_generation"]) != 1 or \
			int(after_abi["pipelines"][0]["reload_retired_pipelines"]) != 1:
		_fail("Rejecting incompatible candidate damaged the active native pipeline")
		return

	var first_epoch: Dictionary = _run_epoch(scene)
	if not first_epoch.get("ok", false):
		_fail("Retained replacement failed real GPU/fence verification: " + str(first_epoch))
		return
	var second: Dictionary = scene.call("godauldron_reload_shader")
	if not second.get("ok", false) or int(second.get("generation", -1)) != 2 or \
			int(second.get("retired_pipelines", -1)) != 2:
		_fail("Completed GPU work did not permit safe old-pipeline retirement: " + str(second))
		return
	var second_epoch: Dictionary = _run_epoch(scene)
	if not second_epoch.get("ok", false):
		_fail("Reloaded shader failed second real GPU epoch: " + str(second_epoch))
		return
	# The shader-language selector uses the same provider runtime-control
	# protocol as any other live provider setting; no host-owned compiler path.
	var selected: Dictionary = ProviderControls.apply(scene, "forward_plus",
		"shader_reload_language", "hlsl")
	if not selected.get("ok", false):
		_fail("Cannot select provider-owned HLSL mode: " + str(selected))
		return
	var hlsl_path := "res://experiments/native-vulkan-provider/reload_compute.hlsl"
	if not FileAccess.file_exists(hlsl_path):
		_fail("Installed provider does not include editable HLSL")
		return
	var hlsl_applied: Dictionary = scene.call("godauldron_reload_shader")
	if not hlsl_applied.get("ok", false) or \
			hlsl_applied.get("source_language") != "hlsl" or \
			int(hlsl_applied.get("generation", -1)) != 3 or \
			int(hlsl_applied.get("retired_pipelines", -1)) != 3:
		_fail("DXC HLSL did not replace the Vulkan native pipeline: " + str(hlsl_applied))
		return
	var third_epoch: Dictionary = _run_epoch(scene)
	if not third_epoch.get("ok", false):
		_fail("DXC HLSL pipeline failed GPU output/fence verification: " + str(third_epoch))
		return

	# HLSL syntax failures must preserve the active HLSL pipeline.
	var hlsl_failure: FileAccess = FileAccess.open("user://native_shader_bad.hlsl",
		FileAccess.WRITE)
	if hlsl_failure == null:
		_fail("Could not stage HLSL compiler error")
		return
	hlsl_failure.store_string("not valid HLSL @@@")
	hlsl_failure.close()
	var bad_hlsl: Dictionary = scene.call("godauldron_reload_shader_from_source",
		"user://native_shader_bad.hlsl")
	if bad_hlsl.get("ok", true) or bad_hlsl.get("stage") != "compile":
		_fail("Broken HLSL source was not rejected by DXC: " + str(bad_hlsl))
		return
	var diag_after_hlsl: Dictionary = PipelineDiagnostics.read(scene)
	var source: Dictionary = diag_after_hlsl.get("source_reload", {})
	if not diag_after_hlsl.get("available", false) or \
			source.get("language") != "hlsl" or \
			source.get("active_language") != "hlsl" or \
			source.get("last_stage") != "compile" or \
			int(diag_after_hlsl["pipelines"][0]["reload_generation"]) != 3:
		_fail("HLSL compiler failure lost accepted pipeline or provenance: " +
			str(diag_after_hlsl))
		return
	var final_diag: Dictionary = PipelineDiagnostics.read(scene)
	if not final_diag.get("available", false) or \
			int(final_diag["pipelines"][0].get("reload_generation", -1)) != 3:
		_fail("Reloaded HLSL bytecode was not retained over provider setup")
		return
	print("Native Vulkan shader hot reload passed: GLSL and DXC HLSL compiled, three fenced GPU epochs correct, invalid source/ABI rejected without PSO retirement")
	quit(0)
