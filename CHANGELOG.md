# Changelog

All notable changes to ShellVibe are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-09-17

### Added

**Port forwarding**

- A forward starts without a terminal session. It needs an authenticated SSH
  client and nothing else, so it now opens one in the background instead of
  refusing until a terminal happened to be connected to the right host. A
  connected tab for that host is still reused, one background connection is
  shared by every rule on a host, and it closes once the last of them stops.
  Jump hosts are dialed through the same chain the terminal walks.

**Terminal**

- Snippets are sent from a picker — ⌘⇧S / Ctrl+Shift+S, or "Send Snippet…" in
  a pane's right-click menu — which searches title, body and tags, and names
  whether the next send lands on the active pane or on a broadcast selection.

**AI access**

- `list_hosts` reports the workspace the calling token is bound to, and
  Settings → AI Access says the same where the token is minted. A token is
  pinned to one workspace for its whole life, so a host saved in another one
  is invisible to it however the window is switched — which used to look
  exactly like a host that had been hidden or had gone missing.

### Changed

- The snippet strip that sat permanently under the panes is gone, and the
  terminal takes those rows back. See the picker above.
- An empty Automation Library draws its "Add" button once, in the empty state,
  rather than there and in the page header.

### Fixed

- A forward started while a terminal was open on a *different* host tunneled
  through that host. The session it reuses is now matched on the rule's own
  host.
- `shellvibe-mcp` exits once the client that launched it is gone. A client
  that died without closing the pipe left the bridge running, so reconnecting
  a few times in one session left a process behind each time.

## [1.1.0] - 2026-09-16

**This release raises the minimum macOS version to 12.0 (Monterey).** Xcode 26
refuses to build for anything older, so 10.15 and 11 are no longer supported
targets. Windows and Linux requirements are unchanged.

### Added

**Terminal**

- Rearrange split panes by dragging. A pane header dropped on another pane
  swaps the two; dropped on the outer quarter of a side it moves into that
  side, splitting the pane it was dropped on. Corners go to the nearer edge.
- A right-click menu on a pane, carrying Copy, Paste and Select All with the
  shortcuts they duplicate, Find, Clear Scrollback, Reconnect on a dropped
  session, the broadcast-input toggle, and the tab bar's own split, transfer
  and template actions aimed at the pane that was clicked. Right-clicking a
  link leads with Open Link and Copy Link Address.
- Pasting clipboard text that carries its own newline now asks first. Such a
  payload runs the moment it lands rather than waiting to be read.

**Bookmarks**

- Hosts and saved layouts can be starred. The star appears on a host row under
  the pointer and stays once the row is starred; a phone toggles it from the
  host's detail panel, and layouts from the template picker.
- Favorites are a filter of their own beside All and Connected. The host list
  is never reordered by it.
- The ⌘K palette now lists bookmarks first and then every other host, so a
  starred server opens from anywhere without going to Hosts first. The
  terminal's empty screen offers the same bookmarks as chips.
- The Connect to Host panel gained a search field, and leads with the same
  Favorites section in the same order as the palette.

### Changed

- A workspace is switched by clicking its card. The separate "use workspace"
  button is gone: the obvious gesture did nothing, and the control that worked
  sat among rename and delete.

### Fixed

- SFTP upload speed is measured on the wire instead of off the local disk.
  Progress followed bytes read from the file rather than bytes the server had
  acknowledged, so short uploads jumped to 100% at an impossible rate and then
  sat there while the pipeline drained. The displayed rate also fell to 0 B/s
  between samples, in both directions.
- The mobile tab bar no longer double-counts the screen insets.
- "Lock now" says why it cannot lock a vault instead of doing nothing.
- The host row stacks its name over its address on a phone rather than
  clipping the address.
- "Save and connect" connects the host it just saved.
- The vault identity row no longer collapses to stubs on a phone.

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

[Unreleased]: https://github.com/klc/shellvibe/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/klc/shellvibe/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/klc/shellvibe/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/klc/shellvibe/releases/tag/v1.0.0
