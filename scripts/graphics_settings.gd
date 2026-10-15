extends RefCounted
## Host-side settings only. An experiment may claim keys or "*" for all.
## Presets are starting points, not promises about hardware capability.

const SETTING_KEYS := [
	"scaling_3d_scale", "msaa_3d", "screen_space_aa",
	"use_taa", "use_debanding", "positional_shadow_atlas_size"
]
const PROFILES := {
	"Low": {
		"scaling_3d_scale": 0.75, "msaa_3d": 0, "screen_space_aa": 1,
		"use_taa": false, "use_debanding": false, "positional_shadow_atlas_size": 1024
	},
	"Medium": {
		"scaling_3d_scale": 0.9, "msaa_3d": 2, "screen_space_aa": 0,
		"use_taa": false, "use_debanding": true, "positional_shadow_atlas_size": 2048
	},
	"High": {
		"scaling_3d_scale": 1.0, "msaa_3d": 2, "screen_space_aa": 0,
		"use_taa": false, "use_debanding": true, "positional_shadow_atlas_size": 4096
	},
	"Ultra": {
		"scaling_3d_scale": 1.0, "msaa_3d": 3, "screen_space_aa": 0,
		"use_taa": false, "use_debanding": true, "positional_shadow_atlas_size": 4096
	},
	"Showcase": {
		"scaling_3d_scale": 1.5, "msaa_3d": 3, "screen_space_aa": 0,
		"use_taa": false, "use_debanding": true, "positional_shadow_atlas_size": 8192
	}
}


static func owned_keys(scene: Node, manifest: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	for value in manifest.get("graphics_owned_settings", []):
		if value is String and (value == "*" or SETTING_KEYS.has(value)):
			if not keys.has(value):
				keys.append(value)
	if scene != null and scene.has_method("godauldron_graphics_owned_settings"):
		var declared: Variant = scene.call("godauldron_graphics_owned_settings")
		if declared is PackedStringArray or declared is Array:
			for value in declared:
				if value is String and (value == "*" or SETTING_KEYS.has(value)):
					if not keys.has(value):
						keys.append(value)
	return keys


static func is_owned(key: String, owned: PackedStringArray) -> bool:
	return owned.has("*") or owned.has(key)


static func apply(viewport: SubViewport, settings: Dictionary, owned: PackedStringArray) -> Dictionary:
	# Never write arbitrary engine/project properties from manifest data.
	var applied := {}
	for key in SETTING_KEYS:
		if settings.has(key) and not is_owned(key, owned):
			viewport.set(key, settings[key])
			applied[key] = viewport.get(key)
	return applied


static func read(viewport: SubViewport, owned: PackedStringArray) -> Dictionary:
	var values := {}
	for key in SETTING_KEYS:
		values[key] = viewport.get(key)
	return {
		"effective": values,
		"host_respects_experiment_ownership": true,
		"experiment_owned": Array(owned),
		"scaling_3d_mode": viewport.scaling_3d_mode
	}
