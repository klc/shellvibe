# Changelog

All notable changes to ShellVibe are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-09-12

First public release. There is no previous version to compare against, so this
entry describes what ShellVibe is rather than what changed.

### Added

**Terminal**

- A local shell on macOS, Windows and Linux, running the user's real login
  shell through a PTY.
- SSHv2 sessions, with the PTY read on its own isolate and output paced into
  frame-sized writes so a burst of output cannot out-run the frame budget.
- Mosh transport with network roaming and local-echo prediction, for links that
  change address or drop.
- Tabs and split panes, saved layouts, and search through the scrollback
  (⌘F / Ctrl+Shift+F).
- Twenty-nine terminal colour schemes, and twenty-two fonts to set them in —
  seven of them Nerd Fonts bundled with the app, so prompt glyphs render
  without a network.

**Files and forwarding**

- Dual-pane SFTP with an atomic upload commit — written to a temporary name and
  renamed — and path-traversal checks on every remote path.
- A transfer queue that survives navigation, with pause, resume and retry.
- Local, remote and dynamic (SOCKS5) port forwarding.

**Hosts and credentials**

- Workspaces, host groups, jump hosts, and import from an existing
  `~/.ssh/config`.
- An encrypted vault for identities. Secrets are sealed with a data encryption
  key that a master password wraps with Argon2id; without the password the
  stored rows are unreadable, including to anyone who copies the database file.
- Host keys are verified against a known-hosts table. A changed key is never
  accepted through the connect flow, and an unknown host requires an explicit
  confirmation rather than being trusted on first use.
- Failed unlock attempts back off exponentially, from 30 seconds to an hour.
- Encrypted backup to a `.shellvibebak.json` file you choose, encrypted with
  the master password before it is written.

**Automation**

- Snippets and runbooks, with variable prompts.
- An MCP bridge (`shellvibe-mcp`) that lets an AI client drive a session under
  a per-workspace access policy, with an audit log and a one-press control that
  cuts every agent's access at once.

**Device Link**

- Pair a phone with a live desktop terminal session over the local network. The
  connection is TLS with the certificate pinned to the key in the pairing QR
  code; nothing is relayed through a server of ours, because there is no server
  of ours.

**Interface**

- Nocturne: slabs floating on a night ground, lit from above, separated by
  whitespace rather than divider rules. Mono type is reserved for machine data.
- Ten application palettes, including the true-black OLED theme it starts on
  and the ShellVibe Teal brand palette.
- Ten interface fonts, starting on the bundled Inter Tight so a first launch
  with no network still renders in the app's own face.
- One button component across the whole app, and one icon button, so a control
  cannot drift a few pixels or a shade away from its neighbours.

### Security

- The SSH stack is `dartssh2` 4.1.0, which implements strict key exchange
  (`kex-strict-c-v00@openssh.com`), the countermeasure against the Terrapin
  prefix-truncation attack (CVE-2023-48795).
- `~/.shellvibe/mcp-endpoint.json` is locked to `0600` before the MCP bearer
  token is written into it, and the `chmod` result is checked: a failure
  deletes the file and raises rather than leaving a token at default
  permissions.
- No analytics, no telemetry and no crash reporting. The update check runs only
  when pressed. `PRIVACY.md` accounts for every case in which the app touches
  the network.

### Known limitations

- **The binaries are not code-signed.** macOS and Windows will warn that they
  cannot tell who built them, and the release notes explain the route through
  each warning. Building from source avoids the question entirely.
- Linux ships as an AppImage and a portable tarball; there are no `.deb`,
  `.rpm` or Flatpak packages yet.
- The update check reports that a newer version exists but does not download or
  install it.
- iOS and Android are not released. The code builds for them and they are not
  part of this release.

[Unreleased]: https://github.com/klc/shellvibe/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/klc/shellvibe/releases/tag/v1.0.0
