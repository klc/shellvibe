# Terly2

> Cross-platform (iOS, Android, macOS, Windows, Linux) terminal, SSH/SFTP client and remote infrastructure workstation built with **Flutter 3.x / Dart 3.x**.

Terly2 brings modern, hardware-accelerated terminal rendering, a Zero-Knowledge encrypted identity vault, dual-pane SFTP, visual port-forwarding tunnels and multi-step runbook automation to **five platforms from a single codebase** — competing with Termius, Warp, Tabby, Blink Shell and MobaXterm.

## ✨ Features

- **Local Shell** — `flutter_pty` powered local terminal (zsh/bash/pwsh) on macOS, Windows, Linux & Android (iOS sandbox aware).
- **SSHv2** — Pure Dart `dart_ssh2` engine with isolate-offloaded Key Exchange (jank-free) and TOFU host-key verification against a `known_hosts` store.
- **Dual-pane SFTP** — Background transfer queue, atomic uploads (temp + rename), in-app remote file editor, chmod/chown, path-traversal protection.
- **Visual Tunnels** — Local (`-L`), Remote (`-R`) and Dynamic SOCKS5 (`-D`) port forwarding with live throughput stats.
- **Identity Vault** — Argon2id + AES-256-GCM Zero-Knowledge encryption. Master password protected DEK/KEK architecture, brute-force lockout and auto-lock on background.
- **Snippets & Runbooks** — `${INPUT:variable}` parameterised commands and multi-step runbook execution with exit-code / regex output verification.
- **Workspaces** — Isolated workspace scoping for hosts, identities and snippets.
- **E2EE Cloud Sync** — Self-contained encrypted backup export/import (DEK wrapped with backup password, re-wrapping of secrets across devices).
- **Design System** — "Quiet Ops" theme with 7+ dark palettes (OLED, Catppuccin, Nord, Dracula, Solarized, TokyoNight, Gruvbox) via Shadcn UI.

## 🧱 Tech Stack

| Layer | Technology |
| :--- | :--- |
| Framework | Flutter SDK 3.x / Dart SDK `^3.12.2` |
| State | `flutter_riverpod` 3.x + `riverpod_annotation` (codegen) |
| Terminal UI | `xterm2` (maintained fork) |
| SSH / SFTP | `dart_ssh2` (Pure Dart) |
| Local PTY | `flutter_pty` |
| Database | `drift` (SQLite) — 9 tables, schema-versioned migrations |
| Secure Storage | `flutter_secure_storage` (Keychain / KeyStore / Credential Manager) |
| Crypto | `cryptography` — AES-256-GCM + Argon2id |
| Routing | `go_router` (declarative, vault-gated) |
| Desktop | `window_manager`, `tray_manager`, `hotkey_manager`, `desktop_drop` |
| UI Kit | `shadcn_ui`, `lucide_icons_flutter`, `google_fonts` |

## 📁 Project Layout

```
terly2/
└── lib/
    ├── main.dart
    ├── app/            # router, theme, navigation shell
    ├── core/           # crypto, network (SSH/SOCKS5/PTY), sync, utils
    ├── features/       # terminal, hosts, sftp, tunnels, vault, snippets, settings, workspaces
    │   └── <feature>/{data,domain,presentation}
    └── shared/         # drift database (tables/DAOs), providers, secure storage
```

See [`AGENTS.md`](AGENTS.md), [`docs/tech_spec.md`](docs/tech_spec.md) and [`docs/features_and_competitor_analysis.md`](docs/features_and_competitor_analysis.md) for the full architecture specification.

## 🚀 Getting Started

```bash
# Install dependencies
flutter pub get

# Run code generation (Drift, Riverpod)
dart run build_runner build --delete-conflicting-outputs

# Run the app (choose a platform)
flutter run -d macos     # or windows / linux / ios / android

# Static analysis & tests
dart analyze
flutter test
```

> The first build runs Drift & Riverpod code generation. Generated files (`*.g.dart`) are committed so a clean checkout builds without `build_runner`.

## 🔒 Security Model

- SSH host keys are verified (SHA-256) against a `known_hosts` table — mismatched keys are **never** accepted through the normal connect flow (MitM protection).
- Identity secrets (passwords, private keys, passphrases) are encrypted with a random Data Encryption Key (DEK). With a master password configured, the DEK is stored only in its AES-256-GCM wrapped form and the plaintext copy is purged from the keychain.
- Failed unlock attempts trigger exponential back-off lockout (30s → … → 1h).
- SFTP operations mitigate path-traversal (slip) attacks and uploads use atomic temp-file + rename commits.

See the [Technical Architecture Specification](docs/tech_spec.md) for sequence diagrams and edge-case handling.

## 📄 License

Proprietary — `publish_to: 'none'`.

