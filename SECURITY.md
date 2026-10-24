# Security

## Threat model

- Two Macs, same owner, on a trusted LAN.
- Not for hostile or public networks.
- One paired connection, LAN only.

## What protects the link

- TLS 1.2 ECDHE-PSK. Forward secrecy: a captured handshake stays undecryptable even if the code is later cracked.
- PSK derived from the pairing code via PBKDF2-HMAC-SHA256, 200k iterations.
- Pairing code: ~50 bits (10 Crockford-base32 chars), shown on Host, typed on Join.
- A new connection is adopted only after it authenticates, so an unauth connector can't drop the live link.

## Known caveats

- A live MITM who guesses the ~50-bit code (slowed by PBKDF2) could impersonate a peer.
- Security assumes same-owner LAN. Do not use on untrusted networks.

## Reporting a vulnerability

- Report privately. Do not open a public issue.
- Open a private GitHub security advisory on this repo (Security > Advisories > Report a vulnerability).
