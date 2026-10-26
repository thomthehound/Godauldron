# Laboratory diagnostic event console

The laboratory's **Messages (F3)** console records structured events from the Godauldron host. The panel is collapsed by default and supports Info/Warning/Error filtering, a bounded recent-message display, Clear, and explicit atomic **Export JSON** to `user://diagnostics`.

This is an inspection and troubleshooting facility, **not a reimplementation of Godot's engine debugger**. Godauldron does not automatically intercept stderr, engine `push_error`, validation-layer diagnostics, graphics driver logging, native `printf`, or the GPU debug-marker stream. Those sources require explicit native/engine integration; the console must never imply they were monitored when they were not.

## Events and run evidence

Currently emitted structured events include laboratory startup, experiment selection, native extension preflight rejection, measured benchmark lifecycle, campaign lifecycle, and screenshot output success/failure. Each event has level, source, event code, message, UTC timestamp, monotonic tick and bounded JSON-safe scalar context. The in-memory ring holds the latest **500** events and records the number of overwritten older events. The panel displays the latest 100 matching items without rerendering in the middle of measured step callbacks. Export writes versioned JSON, including dropped-event counts and an explicit source-scope warning.

A native experiment may supply an optional **post-run** `godauldron_diagnostics() -> Array` callback, returning at most 100 dictionaries shaped like:

```gdscript
{
    "level": "warning",
    "source": "provider",
    "code": "pipeline_fallback",
    "message": "Using the validated CPU fallback",
    "context": {"dispatch_count": 128}
}
```

Levels are `info`, `warning`, or `error`. Context keys and values are small, finite JSON scalars only. Nodes, resources, executable callables, nested arbitrary objects, control characters or oversized diagnostic payloads are not admitted. A malformed event is rejected and counted, without executing provider-supplied text. The host owns the effective event source as `provider` regardless of that field in untrusted data.

Crucially, the hook executes **only after a benchmark has ended**, outside the measured step callback and before report persistence. Its cost is part of report preparation, not GPU time or sampled callback time. A report embeds the run-specific host/provider diagnostic excerpt and acceptance/rejection count. No callback is polled each frame and no external GPU readback is done.

## Controls and measurement integrity

The console cannot be opened/closed, cleared or exported during benchmark sampling or asynchronous image capture, because changing the UI layout or writing files in those phases could contaminate timing/capture. Any visible console remains at the same size during measurement. F3 toggles it outside measured work; the header button provides the same operation. Both paths share one guard.

Reports and diagnostic exports are append-only, new files; an export is written to a staging file and renamed after the complete JSON payload is closed. This console is not a persistent global log database: entries remain in memory until exported or until the session ends.

## Future native diagnostics

Native SDK integration can supply explicit validation-layer events, queue timestamps, shader compilation warnings, device-loss details and resource residency telemetry once real adapters expose and attribute them. Do not infer them from unrelated Godot host messages or conflate a provider diagnostic callback with completed GPU work.
