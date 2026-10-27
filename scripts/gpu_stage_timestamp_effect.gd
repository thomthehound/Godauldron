extends CompositorEffect
## Render-thread marker only. This effect never reads pixels or submits native SDK work.
var _owner: WeakRef
var _label: String


func _init(stage: int, owner: RefCounted, label: String) -> void:
	effect_callback_type = stage
	_owner = weakref(owner)
	_label = label
	enabled = true


func _render_callback(callback_type: int, _render_data: RenderData) -> void:
	if callback_type != effect_callback_type:
		return
	var recorder: RefCounted = _owner.get_ref()
	if recorder != null:
		recorder.record_stage(_label)
