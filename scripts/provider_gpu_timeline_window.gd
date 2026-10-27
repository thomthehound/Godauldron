extends Window
## Display a completed, provider-sourced GPU timeline without combining clock
## domains or adding overlapping GPU and CPU durations.

const MAX_DISPLAY_STEPS := 24
const MAX_EVENTS_PER_STEP := 16

var _description: Label
var _tree: Tree
var _record: Dictionary = {}


func _ready() -> void:
	title = "Godauldron · Native provider GPU lanes"
	size = Vector2i(1040, 730)
	min_size = Vector2i(600, 420)
	close_requested.connect(hide)
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_description)
	_tree = Tree.new()
	_tree.columns = 4
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.set_column_title(0, "Event / lane")
	_tree.set_column_title(1, "Device clock / queue")
	_tree.set_column_title(2, "Time (ms)")
	_tree.set_column_title(3, "Scope / evidence")
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_tree)


func _item(parent: TreeItem, label: String, lane: String, timing: String,
		meaning: String) -> TreeItem:
	var entry: TreeItem = _tree.create_item(parent)
	entry.set_text(0, label)
	entry.set_text(1, lane)
	entry.set_text(2, timing)
	entry.set_text(3, meaning)
	return entry


func show_timeline(result: Dictionary) -> bool:
	if not bool(result.get("available", false)):
		return false
	_record = result.duplicate(true)
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var provenance: Dictionary = result.get("provenance", {})
	_description.text = "Provider: %s | Backend: %s | Device: %s | %d events across %d sampled steps\nDevice timestamps and host CPU waits are different clocks. GPU time across lanes may overlap; do not add it to Godot viewport timing." % [
		String(provenance.get("provider", "unknown")),
		String(provenance.get("backend", "unknown")),
		String(provenance.get("device", "unknown")),
		int(result.get("gpu_events", 0)), int(result.get("expected_steps", 0))
	]
	var queues_section: TreeItem = _item(root, "GPU queue covered intervals", "",
		"", "Union of device-timestamp intervals within one queue and clock")
	for entry in result.get("queues", []):
		_item(queues_section, String(entry["queue"]), String(entry["clock_domain"]),
			"%.3f" % (float(entry["covered_gpu_usec"]) / 1000.0),
			"union; %d intervals" % int(entry["interval_count"]))
	var overlap_section: TreeItem = _item(root, "Simultaneous queue intervals", "", "",
		"Pairwise overlap ONLY when GPU clock domains match")
	var overlaps: Array = result.get("same_clock_queue_overlaps", [])
	for entry in overlaps:
		_item(overlap_section,
			"%s ∩ %s" % [entry["queue_a"], entry["queue_b"]],
			String(entry["clock_domain"]),
			"%.3f" % (float(entry["overlap_usec"]) / 1000.0),
			"intersection; already counted inside both queue unions")
	if overlaps.is_empty():
		_item(overlap_section, "No comparable queue pairs", "", "—",
			"Absent same-clock evidence does not imply no concurrency")
	var kinds: TreeItem = _item(root, "Individual GPU event categories", "", "",
		"Duration distributions; categories are NOT additive")
	var grouped: Dictionary = result.get("gpu_event_kinds", {})
	var kind_keys: Array = grouped.keys()
	kind_keys.sort()
	for key in kind_keys:
		var kind: Dictionary = grouped[key]
		var distribution: Dictionary = kind["event_duration"]
		_item(kinds, String(key), "all reported GPU queues",
			"%.3f" % (float(distribution["p50_usec"]) / 1000.0),
			"per-event p50; count %d" % int(kind["event_count"]))
	var waits: TreeItem = _item(root, "Host CPU synchronization waits", "", "",
		"CPU wall time, not additional GPU execution")
	var wait_kinds: Dictionary = result.get("host_waits", {}).get("by_kind", {})
	var wait_keys: Array = wait_kinds.keys()
	wait_keys.sort()
	for key in wait_keys:
		var distribution: Dictionary = wait_kinds[key]
		_item(waits, String(key), "host CPU monotonic clock",
			"%.3f" % (float(distribution["p50_usec"]) / 1000.0),
			"per-wait p50; count %d" % int(distribution["count"]))
	if wait_keys.is_empty():
		_item(waits, "No completed CPU waits reported", "", "—", "")
	var steps: Array = result.get("steps", [])
	var samples: TreeItem = _item(root, "Sample-step details", "", "",
		"Callback identity, not a verified renderer GPU frame")
	for i in range(mini(steps.size(), MAX_DISPLAY_STEPS)):
		var sample: Dictionary = steps[i]
		var parent: TreeItem = _item(samples, "Sample %d" % int(sample["step_index"]),
			"", "", "%d reported GPU intervals" % (sample["events"] as Array).size())
		var events: Array = sample["events"]
		for j in range(mini(events.size(), MAX_EVENTS_PER_STEP)):
			var event: Dictionary = events[j]
			var duration: float = float(int(event["end_ns"]) - int(event["start_ns"])) / 1000000.0
			_item(parent, "%s: %s" % [event["kind"], event["id"]],
				"%s / %s" % [event["clock_domain"], event["queue"]],
				"%.3f" % duration, "raw GPU interval; may overlap others")
		if events.size() > MAX_EVENTS_PER_STEP:
			_item(parent, "Additional events omitted from view", "", "—",
				"Complete records retained in saved JSON")
	if steps.size() > MAX_DISPLAY_STEPS:
		_item(samples, "Additional steps omitted from view", "", "—",
			"Complete records retained in saved JSON")
	popup_centered()
	return true
