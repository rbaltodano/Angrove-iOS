# llama framework privacy packaging — October 17, 2026

The build 6 archive inspection found the bundled llama framework missing its privacy manifest.
The production model remains Gemma 4 E4B; the Bonsai model switch is disabled in Release.
The framework is nevertheless dynamically linked and embedded, so its own API declaration is required.

The integration-supplied manifest declares System Boot Time, reason `35F9.1`, for elapsed
inference/performance timing. It does not assert a new tracking or data-collection policy.
The iPhone binary imports `clock_gettime`. In the exact vendored Prism release,
`ggml_time_ms` and `ggml_time_us` use `clock_gettime(CLOCK_MONOTONIC)` to compute elapsed intervals.
No direct imports of `stat`, `fstat`, `getattrlist`, `statfs`, `statvfs`, `mach_absolute_time`,
or `NSUserDefaults` appeared in the iPhone binary inventory. This symbol inventory is limited
to direct imports; it does not prove the absence of every indirect API call or network behavior.
The iPhone binary SHA-256 is `e4fff05d8c7af90da4b5a20a1bdd8c3d5fff5457d5aa89b83803f12593870001`.

The same manifest is included in each vendored framework slice; binaries are unchanged.
The versioned Mac framework stores it in `Versions/A/Resources`; iOS slices use the framework root.
Xcode signs the copied frameworks during the normal build/export pipeline.
This supplements, rather than replaces, the existing app/SDK privacy and crypto review.

Sources:
- [Pinned ggml timing implementation](https://github.com/PrismML-Eng/llama.cpp/blob/prism-b10777-e3de715/ggml/src/ggml.c#L560)
- [Apple: required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
