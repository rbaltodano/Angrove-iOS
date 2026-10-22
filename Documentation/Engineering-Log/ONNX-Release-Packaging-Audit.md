# ONNX Runtime release packaging audit

Build 4 uses ONNX Runtime 1.24.2 through Microsoft's Swift package. The package declares its
product as a static library. Its native iOS arm64 archive SHA-256 is
`6cd9d2a7e174f2de317861331bc4454729bab187da92562f8163dee1be8cb55a`.

The exported `Frameworks/onnxruntime.framework/onnxruntime` is an Xcode compatibility stub.
`otool -l` finds one `__TEXT,__text` section of size zero and `LC_SYMTAB nsyms 0`;
`dyld_info -imports -exports` lists no imported or exported symbols. The SDK's executable code
is statically linked into the application. This empty stub has no required-reason API use.
The packaging audit accepts only this structural evidence, never an SDK-name exemption.
A future framework containing code still fails the missing-manifest gate.

The original native archive imports `stat`, `fstat`, monotonic clock functions, `sysctl` and
`sysctlbyname`. The application's privacy manifest declares File Timestamp C617.1 and System
Boot Time 35F9.1, covering local model-file metadata and elapsed timing; it also declares the
app's UserDefaults use. Angrove runs ONNX only for local MiniLM embedding, with local model
files and inputs. The [pinned runtime source](https://github.com/microsoft/onnxruntime/blob/v1.24.2/onnxruntime/core/platform/posix/env.cc)
uses file metadata for local model loading and hardware information for execution configuration.
This integration does not add a separate tracking or data-collection declaration on Microsoft's
behalf. Network observation and App Privacy answers remain separate release checks.

Evidence commands are recorded in `build/testflight-build4/onnx-imports.txt` and the release
packaging report; repeat the stub inspection on the final exported IPA after source changes.

## Build 4 processing rejection and build 5 correction

Apple's ITMS-90208 processing email rejected build 4 after the uploader reported successful
transfer. The compatibility stub has `LC_BUILD_VERSION minos 26.4`, but its copied vendor
Info.plist retains `MinimumOSVersion = 15.1`. The old audit inspected signing/privacy and
recognized the empty binary, but did not compare these two OS declarations. That omission
allowed the bad package through the local checks.

The app's final build phase runs `scripts/fix_onnx_framework_metadata.py` after copying the
framework. It reads the actual binary minimum, raises the copied plist's declaration to match,
refuses a binary newer than the app deployment target, and re-signs the framework. It does not
alter the runtime binary, vendor cache, or app deployment target. Build 5 contains this packaging
correction. The release audit now checks OS declarations against binaries for the app, extensions,
and every framework, and explicitly verifies framework signatures. The rejected build 4 is a
regression fixture: the new gate identifies its exact ONNX 15.1/26.4 mismatch.

Related [Microsoft package report](https://github.com/microsoft/onnxruntime/issues/27396) documents
copied ONNX minimum-OS metadata problems. Our diagnosis comes from the exact exported binary and
plist, rather than assuming every instance of ITMS-90208 has the same cause.
