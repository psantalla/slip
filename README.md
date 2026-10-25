# Slip

Native Swift macOS menu-bar app, Apple Silicon only. Syncs clipboard, files and keyboard/mouse between two Macs over the LAN. No account, no cloud.

## Archived

Not maintained. A single cursor across two Macs leaves a residual cursor on an external display, a macOS limitation also hit by deskflow (#10225); not cleanly solvable in software. For two-Mac keyboard/mouse sharing, Beamer (https://beamerapp.co.uk) is recommended.

An exploration project for native Swift app architecture on macOS. Personal-use, loosely reviewed; some parts are deliberate quick patches.

## Does

- Clipboard text and images, both ways.
- Files, land in `~/Downloads/Slip`.
- KVM (opt-in): cursor crosses the screen edge onto the other Mac, keyboard follows.
- Clipboard / Files / KVM each toggleable. KVM off by default.

## Build and run

- `./build.sh` (release build, assembles and signs `Slip.app`).
- Open `Slip.app` on both Macs, allow Local Network when prompted.
- Host shows a code. Join types it and presses Connect.
- Pairing is saved; it reconnects by itself.

Apple Silicon only.

## Security

Paired over TLS 1.2 ECDHE-PSK (forward secrecy) from a one-time code. LAN only, same owner both ends. Detail: [DESIGN.md](DESIGN.md).

## License

MIT. See [LICENSE](LICENSE).

## Contributing

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
