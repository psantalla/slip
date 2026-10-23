# Slip

Mac-to-Mac clipboard, files and keyboard/mouse over the LAN. Native Swift menu-bar app, Apple Silicon. No account, no cloud.

## Does

- Clipboard text / images, both ways.
- Files, land in `~/Downloads/Slip`.
- KVM: cursor crosses the screen edge, keyboard follows.
- Clipboard / Files / KVM each toggleable, off-switch for KVM by default.

## Run

`./build.sh`, open `Slip.app` on both Macs, allow Local Network. Host shows a code; Join types it, presses Connect. Saved, reconnects by itself.

## Test

Copy on one, paste on the other. For KVM: turn on Share, drag the Join tile to its side, cross the cursor onto it.

Detail and security: DESIGN.md.
