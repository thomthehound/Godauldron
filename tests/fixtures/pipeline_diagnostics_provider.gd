extends Node3D
## Shape-validation fixture. No shader/pipeline is actually compiled here.
var evidence: Dictionary = {
	"provider": "pipeline-contract-fixture",
	"backend": "test",
	"pipelines": [{
		"name": "fixture_compute",
		"shader_origin": "test_fixture_not_native",
		"phase": "prepared",
		"prepare_attempts": 1,
		"prepare_failures": 0,
		"shader_creations": 1,
		"pipeline_creations": 1,
		"descriptor_creations": 1,
		"pipeline_binds": 3,
		"shader_create_host_usec": 20,
		"pipeline_create_host_usec": 140,
		"descriptor_create_host_usec": 10,
		"prepare_total_host_usec": 200,
		"last_prepare_error": "",
		"last_prepare_failure_stage": "",
		"cache_hit_observation": "not_reported",
		"timing_source": "steady_host_wall_microseconds"
	}]
}


func godauldron_pipeline_diagnostics() -> Dictionary:
	return evidence.duplicate(true)
