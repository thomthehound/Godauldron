extends SceneTree
## Real native GDExtension + Vulkan queue and GPU timestamp integration,
## exercised under actual Forward+ software Vulkan. No synthetic device values.

const NativePackage = preload("res://scripts/native_experiment_package.gd")
const Runner = preload("res://scripts/experiment_run.gd")
const SAMPLING_STEPS := 6


func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _verify() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/native-vulkan-provider/manifest.json"))
	if typeof(manifest) != TYPE_DICTIONARY:
		_fail("Native GPU package manifest was not installed")
		return
	var preflight: Dictionary = NativePackage.preflight(manifest)
	if not preflight.get("ok", false) or not ClassDB.class_exists("NativeGpuProbe3D"):
		_fail("Actual native Vulkan GDExtension could not be loaded: " + str(preflight))
		return
	var stage: PackedScene = load(manifest["entry_scene"])
	if stage == null:
		_fail("Native Vulkan experiment scene failed to instantiate")
		return
	var scene: Node = stage.instantiate()
	root.add_child(scene)
	for frame in range(4):
		await process_frame
	var run = Runner.new()
	run.begin(scene, {}, 2, SAMPLING_STEPS, 1.0 / 60.0)
	for frame in range(SAMPLING_STEPS + 2):
		run.advance()
	if run.phase != Runner.Phase.COMPLETED:
		_fail("Native experiment did not finish its sampled-step lifecycle")
		return
	if run.sample_step_submissions.size() != SAMPLING_STEPS:
		_fail("Native submission correlation was not recorded")
		return
	var report: Dictionary = run.make_report("org.godauldron.native-vulkan-device-probe")
	var evidence: Dictionary = report.get("provider_gpu_timeline", {})
	if not bool(evidence.get("available", false)):
		_fail("No genuinely resolved native Vulkan GPU timestamp report: " + str(evidence))
		return
	if int(evidence.get("gpu_events", 0)) != SAMPLING_STEPS * 2 or \
			int(evidence.get("expected_steps", 0)) != SAMPLING_STEPS or \
			int(evidence.get("host_wait_count", 0)) != 1:
		_fail("Native Vulkan intervals or completed fence wait missing")
		return
	if evidence.get("provenance", {}).get("backend") != "Vulkan" or \
			evidence.get("provenance", {}).get("provider") != "native-vulkan-queue-probe":
		_fail("Native device timing provenance was lost")
		return
	var queues: Array = evidence["queues"]
	if queues.size() != 1 or queues[0]["queue"] != "native_compute_transfer_0" or \
			float(queues[0]["covered_gpu_usec"]) <= 0.0:
		_fail("Native queue GPU work lacks actual positive timestamp interval coverage")
		return
	var kinds: Dictionary = evidence["gpu_event_kinds"]
	if not kinds.has("compute") or not kinds.has("transfer") or \
			int(kinds["compute"]["event_count"]) != SAMPLING_STEPS or \
			int(kinds["transfer"]["event_count"]) != SAMPLING_STEPS:
		_fail("Actual Vulkan dispatch and buffer transfer events were not distinguished")
		return
	var previous_end: int = 0
	for i in range(SAMPLING_STEPS):
		var step: Dictionary = evidence["steps"][i]
		if int(step["step_index"]) != i or step["events"].size() != 2:
			_fail("Native sampled-step identity incorrect")
			return
		var compute: Dictionary = step["events"][0]
		var transfer: Dictionary = step["events"][1]
		var begin: int = int(compute["start_ns"])
		var middle: int = int(compute["end_ns"])
		var end: int = int(transfer["end_ns"])
		if begin <= 0 or not (begin < middle and middle <= end) or \
				int(transfer["start_ns"]) != middle or begin < previous_end:
			_fail("Native Vulkan GPU timestamps are not ordered by queue submission")
			return
		if transfer["depends_on"] != [compute["id"]]:
			_fail("Compute-to-copy GPU dependency was not reported")
			return
		previous_end = end
	var waits: Dictionary = evidence["host_waits"]["duration"]
	if int(waits.get("count", 0)) != 1 or float(waits["mean_usec"]) < 0:
		_fail("Native completion fence result not independently measured on host")
		return
	var metrics: Dictionary = report.get("experiment_metrics", {})
	if metrics.has("native_error") and not String(metrics["native_error"]).is_empty():
		_fail("Native GPU reported an execution or verification error")
		return
	if bool(report.get("provider_gpu_timing", {}).get("available", false)):
		_fail("Native timeline was improperly repackaged as legacy GPU durations")
		return
	print("Native Vulkan GDExtension GPU evidence verified: ",
		SAMPLING_STEPS, " compute dispatches, ", SAMPLING_STEPS,
		" buffer copies, resolved device timestamps, completed fence and verified output")
	quit(0)
