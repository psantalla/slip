# Contributing

## Build and run

```
./build.sh                    # release, assemble + sign Slip.app
swift build                   # debug build
swift run slip --selftest     # validate: loopback TLS-PSK + framing
```

- Run `--selftest` before and after any change to Link/Wire.
- Apple Silicon only.

## Scope

- Scoped and terse. One feature solid before the next. No bloat.
- Native only. No Electron/Tauri/daemon/third-party deps.
- Secure by default: encrypted + authenticated, no plaintext fallback.
- KVM opt-in and gated.
- Validate often (`swift build` + `swift run slip --selftest`).

## Code style

- Comments: only for non-obvious why (hidden constraint, invariant, workaround). Terse.
- Match the surrounding code.
- Commits, branch names, PR titles/bodies, comments: English.

## Compatibility

- Both Macs must run the same build to pair.
- Do not break the wire format (frame layout, header kinds) without a version bump.
- Do not rename or repurpose UserDefaults keys without a version bump.
