# Changelog

All notable changes to ShellVibe are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Settings → Account → Delete Account… opens the web panel's danger zone,
  where the account is deleted after the password is asked for again. Hosts
  and keys on the device are not touched.
- Windows: an MSIX package for the Microsoft Store, which signs it. In that
  build, Start at Login uses the package's startup task, the MCP bridge is
  reached through the `shellvibe-mcp.exe` execution alias, and updates come
  from the Store. The installer and portable zip are unchanged.

### Changed

- On iOS and Android, About no longer offers "Check for updates": those
  builds update through the App Store and Google Play.
- On Windows and Linux the system title bar is gone. Minimise, maximise and
  close sit at the right of a 32px strip in the app's own colours, the strip
  drags the window and a double-click maximises it, the way the macOS build
  already worked. On KDE this replaces the GTK header bar.
- Shortcut hints read `Ctrl+T`, `Ctrl+K` and `Ctrl+1…7` on Windows and Linux
  instead of the macOS `⌘` labels.
- macOS: saved secrets (vault key, account session, sync keys, settings)
  share a single keychain item instead of one each, so a future change in how
  the app is signed asks for the login password once rather than once per
  item. Existing items move over the first time the app reads them.

### Fixed

- On Windows and Linux, launching ShellVibe while it runs (from the Start
  menu, a launcher, or with the window hidden in the tray) brings the
  running copy forward instead of starting a second one on the same
  database. The release build let go of its single-instance lock seconds
  after taking it.
- On Windows the window opens maximised, as on the other desktops, instead
  of being restored to 1280x720 a moment after it was maximised. On a
  machine rendering in software (a VM without a GPU) that double resize
  also left the window white for half a minute or more.

### Security

- AI Access: denying (or not answering) an agent's request for a server no
  longer turns into read-only access to that server once the 10-minute
  cooldown ends.
- AI Access: locking the vault, turning AI Access off or quitting now ends
  everything an agent had in flight: pending approval prompts are refused,
  its terminal sessions close, a runbook it started is cancelled and "This
  session" approvals end. Cut all agent access goes through the same path.
- AI Access: a server approved for "This session" is now granted only for
  that agent connection, as the dialog says, instead of permanently.
- AI Access: "Deny and suspend client" now holds until AI Access restarts;
  the suspended agent no longer gets a fresh identity on its next request.
- AI Access: starting AI Access retires the built-in connection token left
  over from any other workspace.
- AI Access: hiding a server from agents also stops new sessions and
  commands on it, even where access had been granted.
- AI Access: a private key cut in half by the command output limit is now
  masked like a whole one before the output reaches the agent.
- AI Access: searching runbooks no longer matches against secrets the
  runbook listing masks.

## [1.7.0] - 2026-10-01

### Added

- The macOS build is signed with a Developer ID and notarized by Apple, so it
  opens like any other Mac app: no "Open Anyway" trip through Privacy &
  Security, before or after an update. The ticket is stapled into both the
  DMG and the app inside the ZIP, so the first launch works offline too.
- Native Linux packages alongside the AppImage: `.deb` for Debian and Ubuntu,
  `.rpm` for Fedora and RHEL, and `.pkg.tar.zst` for Arch. They put ShellVibe
  in the app menu, pull in the libraries it needs and uninstall cleanly. Each
  one is installed and launched on Ubuntu 22.04 and 24.04, Debian 12 and 13,
  Fedora and Arch before a release is published.
- The tray menu manages the app instead of counting it: open sessions (click
  to focus the tab), active tunnels with Stop, saved tunnels with Start
  without opening the window, and Favorites and Templates to connect from
  there. While the vault is locked it shows counts only.
- Desktop notifications when a session drops, a tunnel fails to start, or a
  terminal rings the bell or sends OSC 9 / OSC 777 while you are not looking
  at it. Clicking one opens the related tab. Settings → Window → Desktop
  notifications.
- The tray icon shows whether a tunnel is active or something failed while
  the window was away.
- Launch at login, per device, with only the tray icon when the tray is
  enabled.
- A host can carry several tags, and tags can be added or removed from the
  host form and the host row.
- "Run Template..." in the new-tab menu, next to "Connect to Host...".
- A "Match App Theme" terminal color scheme that follows the app palette and
  light or dark mode to its terminal counterpart (Gruvbox, Nord, Solarized,
  Tokyo Night, One Dark, Catppuccin), so a light app theme no longer keeps a
  black terminal. New installs start on it; a scheme you already chose is
  kept.

### Changed

- macOS: because the app is now signed by a different identity than 1.6.0
  and earlier, the first launch after updating asks once for each saved
  keychain item to allow ShellVibe to use it. Choose **Always Allow**; later
  launches do not ask again.
- AI Access: `list_hosts` and `describe_host` return `groups` (a sorted list
  of tag names) instead of `group`, and a group-scoped policy rule matches a
  host when any of its tags is that group. Clients that read `group` need
  updating.
- OLED's text uses neutral greys instead of the default theme's blue-violet
  ones, and its light mode has neutral surfaces of its own.

### Fixed

- Menus, dropdowns, dialogs, bottom sheets, chips, switches, snack bars and
  the date picker took colours from outside the chosen palette: white menus
  and a grey selected row on Gruvbox and Solarized Light, pink sheets and
  chips, a pale snack bar on dark palettes, and white or navy select
  popovers. They now come from the palette.
- The selected tab label on the phone bar was violet in every palette.
- Menu and dialog text was hard to read in Solarized Dark (2:1), and their
  secondary text was below 4.5:1 in Dracula, Tokyo Night, One Dark and
  Gruvbox Dark. Nord's idle labels were as bright as the selected one.
- The active terminal tab and the pane around the terminal were painted in
  the app palette's colour rather than the terminal's own, leaving a seam
  where the tab meets the pane.
- Dragging a selection while the terminal scrolled moved its start along with
  the view, so text longer than one screen could not be selected.
- Shift+keypad Enter inserted a stray private-use character in some CLIs
  instead of starting a new line.
- SSH config import showed the selected tag's id instead of its name, and
  replaced a host's tags instead of adding to them.

## [1.6.0] - 2026-09-27

### Changed

- Every interface and terminal font ships with the app. The optional families,
  and the default terminal face Roboto Mono, were fetched from Google's font
  CDN on first use; choosing a font in Settings now makes no network request
  at all, and the "Offline" badge is gone.

### Security

- The sync server could change what an operation does without the sync key:
  whether it is a delete, and its device and clock, sat only in fields outside
  the encryption, enough to turn an edit into a delete or to win
  last-writer-wins. They are now sealed inside the payload and checked when it
  is opened. Operations from earlier builds are accepted as before.
- An MCP "This session" approval answered for every later connection, exactly
  like "Always". It now ends with the connection that granted it.
- In autonomous mode, MCP commands that read credentials (`cat ~/.env`,
  private keys, `printenv`) ran without asking. They now always ask, cannot be
  remembered, and an approval stored for one before is ignored.
- A phone woken after sleeping past the auto-lock delay could show the vault
  unlocked, because the lock ran only on a timer that does not count while the
  device sleeps. Returning to the app now checks the time away as well.

### Fixed

- A synced identity could not log in on any other device: its secrets
  travelled encrypted under the sending device's own vault key. They now
  travel under the sync key and are re-encrypted for the receiving device.
  Identities synced from an earlier build may need their secrets entered again
  on the devices that received them.
- A change made offline, or held back behind a locked vault, could never reach
  the other devices: the operation log was paged by the clock each change was
  recorded with, so one sent late landed behind a cursor that had already
  passed it. Devices now page by the order the server stores operations. This
  takes effect once `api.shellvibe.dev` runs the matching server; until then
  sync works as it did.
- A locked vault no longer stops sync altogether. Hosts and other changes
  still arrive and only sending waits, and unlocking resumes sync at once
  instead of at the next five-minute poll. Joining sync with a locked vault
  says so and picks up on unlock.
- Restoring a sync snapshot no longer drops an unsent local change. Each row
  is compared with the version the snapshot holds for it, and a newer local
  edit is kept and still sent.
- An incoming change carrying no row failed the same page on every pull and
  stalled sync; it is skipped.
- Bookmarks, templates and vault environment variables showed what was there
  before a restore until the app restarted.
- Two first uses of an empty keychain at once — sync applying an identity
  while you save another — each created a vault key, and the second replaced
  the first, leaving whatever was sealed under it unreadable.
- A device that sat closed past its cloud backup interval backs up on
  opening, rather than a quarter of an hour later.
- Every dynamic (`-D`, SOCKS5) forward connection died right after the
  handshake.
- `-L`, `-R` and `-D` forwards closed the SSH channel as soon as either side
  finished sending, dropping the reply to clients that shut their write side
  (`nc -N`, `printf | nc`, HTTP/1.0). A forward whose local client resets the
  connection now closes its channel too.
- The local terminal could freeze for good when output split a multi-byte
  character across reads several times in a row.
- A phone that disconnected while attaching to a Device Link session left the
  desktop tab refusing every later phone with `session_in_use` until the tab
  was closed.
- An MCP command sent while an interrupt rebuilt the shell waited out its
  full timeout, and an interrupt during hang recovery leaked a shell channel.
  Output caps that were not a multiple of five dropped bytes without a
  truncation marker, and approving the same command twice made its next run
  fail.
- On macOS, closing the window with the tray icon off quit the app and took
  every session and tunnel down with it. On a desktop without a tray host,
  turning the tray on could leave the close button doing nothing.
- Switching windows no longer runs a sync round trip and rebinds every Mosh
  session; only hiding or leaving the app counts.
- The window frame takes the selected palette's color instead of the default
  one, and the Device Link pairing screen has window controls and a drag
  strip.
- The command palette's arrow keys move the selection, and a long result no
  longer hides the detail beside it.

## [1.5.0] - 2026-09-25

### Added

- The vault has an Environment view beside Identities for the tokens and keys
  a shell needs, so they no longer sit in a dotfile in the clear. Each value is
  encrypted with the vault key, scoped to the workspace, and synced and backed
  up with identities. Every new local tab and split pane starts with the
  workspace's variables; a locked vault never holds the shell back — it starts
  without them and says so.
- Local shells start with `TERM_THEME` set to `light` or `dark`, following the
  terminal palette rather than the app theme, so CLI tools can pick colors that
  read on the terminal's background.
- Settings → About → Report a problem opens a GitHub issue with the build and
  the recent error log filled in. After a crash, the next launch offers the
  same once. Home folders, IP addresses and `user@host` pairs are masked, the
  report is shown before anything opens, and the app itself sends nothing.

### Fixed

- Numpad digits and operators type as plain text in agent CLIs, such as
  Cursor's, that ask for only the kitty keyboard protocol's disambiguate flag;
  they inserted private-use characters before. Keypad Enter sends a carriage
  return there too. (xterm3 6.3.4)
- On a phone, a starred host's overflow menu no longer runs 20px past the
  screen edge; the star sits beside the host name instead.
- Setting up cloud backup while the server could not be reached stored the new
  passphrase anyway. The next scheduled backup then sealed this device's data
  under a passphrase no other device had and uploaded it over the account's
  backup. Setup now stops and says the server could not be reached.
- A cloud backup no longer lands on top of a newer one from another device
  without asking. Each upload now names the revision it builds on, so a device
  that has not restored another device's later backup gets the "restore first,
  or overwrite" choice instead of silently becoming the newest backup. Devices
  that have joined automatic sync are unaffected, since they already hold what
  the others wrote.

### Changed

- `PRIVACY.md` and the README describe the optional account: what
  `api.shellvibe.dev` stores, what it can and cannot read, how long it keeps
  it, and how to export or delete it. Both still said there was no account and
  no server.

## [1.4.0] - 2026-09-23

### Added

- Eleven light terminal color schemes: GitHub Light, Tokyo Night Day,
  Rosé Pine Dawn, Ayu Light, Everforest Light, Kanagawa Lotus, Nord Light,
  Light Owl, Monokai Pro Light, Flexoki Light and Xcode Light. Light schemes
  were four out of 29.
- The terminal color scheme list marks each scheme with a sun or a moon, so
  light and dark schemes can be told apart in the alphabetical list. The app
  theme mode options carry the same icons, with a monitor for System.

### Changed

- The desktop right-click menus open in 120ms and close in 80ms instead of
  Material's 300ms grow-in, which felt sluggish next to native menus.

### Fixed

- Emoji such as ✅ and ❌ no longer lose their right edge in the terminal.
  A color emoji glyph is wider than two cells of most monospace fonts; it is
  now shrunk to its cells instead of clipped. (xterm3 6.3.3)
- The oh-my-zsh prompt arrow (U+279C) is drawn as an arrow instead of a bare
  `>`. (xterm3 6.3.3)
- The palette swatch beside each terminal color scheme was never painted,
  leaving an empty gap in every row; it shows the scheme's colors again.

## [1.3.0] - 2026-09-23

### Added

**Account, cloud backup and sync**

- An optional ShellVibe account. Nothing requires one: the terminal, SSH, the
  vault and local Device Link all work signed out. Signing in keeps this
  install's device id, so one machine stays one entry in the account's device
  list however often it signs in again.
- Cloud backup uploads the encrypted vault and restores it. The server only
  ever holds the sealed envelope; the passphrase, the keys and the decrypted
  data stay on the device. A recovery code opens the envelope when the
  passphrase is lost.
- Backups can run on a schedule — hourly, daily or weekly, off by default.
  There is no background task on any platform, so "daily" means once a day,
  the first time the app is opened, and Settings says so. A backup that
  changed nothing is not written again.
- A backup, to a file or to the account, carries the categories the user
  picks. Port forwards are locked while hosts are off, since a forward cannot
  exist without its host.
- Automatic sync keeps devices in step in both directions. Joining an account
  never replaces what a device holds: a phone with two hosts joining a desktop
  with sixty ends at sixty-two, whichever joined first, and the join reports
  what it merged.
- A delete that sync carried to every device can be taken back from the trash,
  on every device.
- Cloud backup and cloud sync are on the free plan; the account screen shows
  the storage quota rather than a paywall. (This entry first also listed remote
  Device Link. The app has no relay client: Device Link works over your own
  LAN only.)

**Terminal**

- Tabs can be dragged into a new order. A click still selects a tab; on a
  phone the drag starts after a hold, since a swipe scrolls the strip.
- Right-clicking a tab offers Close Tab, Close Other Tabs, and Close Tabs to
  the Left or to the Right. Split panes close with their tab.

**Templates**

- A template opens every pane at once and connects them side by side. The
  hosts screen and the ⌘K palette switch to the terminal straight away instead
  of after the last host has connected, and a slow host no longer holds up
  the rest of the layout.
- Every template is listed in the ⌘K palette, not only starred ones, and in
  Connect to Host, and both search it by name and description.
- A template can be viewed and edited without running it: each tab with its
  nested panes and the host each connects to, with panes a run would skip
  flagged. Panes can be pointed at another host, split, turned or removed;
  tabs can be added, moved or removed. It opens from the template menu on the
  hosts screen and from the Run Template sheet.

**Desktop**

- ShellVibe keeps running in the system tray (the menu bar on macOS). On
  Windows and Linux closing the window hides it, so tunnels and sessions keep
  running, and the tray menu shows what is still open and holds Quit. It is
  on by default and can be turned off under Settings → Appearance → Window.
- A second launch on Windows or Linux brings the running copy forward instead
  of starting another beside it.

### Changed

- The status bar under the terminal is gone. `user@host:port` is on a split
  pane's header and a single tab's tooltip; a quiet Mosh link and an attached
  Device Link phone are badges on the tab, the Device Link one disconnecting
  on click.
- Settings on a phone opens on an index of sections, each on a page of its
  own, instead of one long scroll. AI Access, which configures a bridge that
  only runs on a desktop, is not shown on a phone, and Device Link shows only
  this device's side of each pairing.
- Backup and Sync are separate sections: a backup is a copy the user takes,
  sync is what runs on its own.

### Fixed

- On macOS, Option-composed characters type in apps that turn on xterm's
  modifyOtherKeys, such as Claude Code. On a Turkish Q layout Option+Q could
  not type `@` there, nor Option+8 `[` and the rest of the Option layer.
  (xterm3 6.3.2)
- Text on the alternate screen stays selectable as a session runs on, and a
  press on blank space starts a selection. (xterm3 6.3.1)
- The search fields were 48px tall with a wide gap before the text; they are
  the height of the controls around them and have a clear button. The
  terminal's find bar no longer draws a second, smaller frame inside itself.
- Light mode gives split pane headers, the active tab and the command approval
  dialog light chrome instead of the dark theme's.
- Sync no longer looks healthy while doing nothing: two devices that switched
  it on together each ended up with their own key, a page boundary could skip
  an operation, the join reported success whatever happened, and automatic
  sync did not run at all. Each of these now either works or says it did not.
- Every Android phone registered on an account as "localhost"; it now takes
  the device's name, or its platform.

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

[Unreleased]: https://github.com/klc/shellvibe/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/klc/shellvibe/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/klc/shellvibe/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/klc/shellvibe/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/klc/shellvibe/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/klc/shellvibe/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/klc/shellvibe/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/klc/shellvibe/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/klc/shellvibe/releases/tag/v1.0.0
