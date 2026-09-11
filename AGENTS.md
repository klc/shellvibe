# AGENTS.md — Agent Operating Guide for ShellVibe

> **Repository Operating Manual for AI Coding Agents working on ShellVibe (shellvibe.dev).**  
> Read this document completely before implementing features or modifying code in this codebase.

---

## 1. Primary Directives & Architecture References

ShellVibe is a modern, high-performance, cross-platform (iOS, Android, macOS, Windows, Linux) terminal, SSH/SFTP client, and remote infrastructure workstation built with **Flutter SDK 3.x** and **Dart 3.x**. Official website: `https://shellvibe.dev`.

**Scope.** Local shell, SSHv2, Mosh with roaming and local-echo prediction,
dual-pane SFTP, port forwarding (local, remote, dynamic), workspaces, snippets,
runbooks, an encrypted identity vault, Device Link, and an MCP bridge for AI
clients.

**The stack is not a preference.** `flutter_riverpod` for state, `xterm3` for
the terminal, `dartssh2` for SSH and SFTP, `flutter_pty` for the local shell,
`drift` over SQLite for storage, `flutter_secure_storage` for the key material,
and `cryptography` for AES-256-GCM with Argon2id. Reach for something else only
with a reason that survives being written down in the commit message.

**Constraints that shape the code**, each load-bearing rather than incidental:
host keys are verified against a `known_hosts` table and a mismatch is never
accepted through the connect flow; identity secrets are encrypted with a DEK
that a master password wraps; the macOS sandbox is off so Local Shell can exec
a login shell, which means path handling is not contained by the OS; and the
terminal's write path is paced, because an unpaced PTY will out-run the frame
budget and freeze the app.

---

## 2. Key Architectural Guidelines for Agents

### 2.1. Clean Layered Architecture
Maintain strict separation of concerns across layers:
- **`lib/features/<feature_name>/presentation`**: UI Widgets, Screens, and Riverpod Notifiers/AsyncNotifiers.
- **`lib/features/<feature_name>/domain`**: Entities, Value Objects, and Use Cases / Repository Interfaces.
- **`lib/features/<feature_name>/data`**: Repositories, Data Sources, Data Mappers, and Drift DAOs.
- **`lib/core`**: Encryption engines, network isolates, stream bridges, and common utilities.
- **`lib/shared`**: Shared database (`drift`), storage, and global models.

### 2.2. State Management & Asynchronous Streams
- Use **`flutter_riverpod` (v2.x+)** with `@riverpod` code generation for state management.
- Business logic, SSH stream handlers, and socket listeners **MUST NOT** depend on `BuildContext`.
- Always use `autoDispose` for tab-specific or session-specific providers to ensure sockets, streams, and terminal buffer memory are destroyed on tab close.

### 2.3. Terminal & Network Stream Bridge
- UI terminal rendering **MUST** use `xterm3`.
- SSH & SFTP networking **MUST** use `dart_ssh2` (Pure Dart engine with isolate-offloaded KEX).
- Local terminal execution on macOS, Windows, Linux, and Android **MUST** use `flutter_pty`.
- Wire `terminal.onResize` to `session.resizeTerminal` and `terminal.onOutput` to `session.write`.

### 2.4. Data Persistence & Security Contracts
- All relational application data (Hosts, Groups, Tunnels, Snippets) **MUST** be persisted in `drift` SQLite.
- Passwords, SSH Private Keys, and Passphrases **MUST NEVER** be stored in plain text. They must be encrypted via `cryptography` (AES-256-GCM using Argon2id-derived Master Key) and stored using `flutter_secure_storage`.
- SSH Host Fingerprints (`SHA-256`) **MUST** be verified against the `known_hosts` Drift table to prevent Man-in-the-Middle (MitM) attacks.

---

## 3. Development Workflow & Verification Rules

Before declaring any task done or presenting changes to the user:

1. **Static Analysis:** Run `dart analyze` to ensure zero warnings or lint errors.
2. **Testing:** Run `flutter test` to verify all unit and widget tests pass.
3. **No Unrequested Changes:** Touch only files relevant to the task; preserve house style and docstrings.
4. **No Placeholders:** Write fully functional, production-ready code with proper error handling.

---

## 4. Recommended Agent Skills

Agents working on ShellVibe SHOULD utilize the following installed skills when relevant:

### 4.1. Architecture, Layout & Routing
- `flutter-apply-architecture-best-practices`: Enforce layered architecture principles (Presentation, Domain, Data).
- `flutter-build-responsive-layout`: Build responsive layouts for mobile and desktop screens.
- `flutter-setup-declarative-routing`: Configure `go_router` for tabbed and deep-link routing.
- `dart-use-pattern-matching`: Use Dart 3.x pattern matching and switch expressions.
- `dart-use-primary-constructors`: Use Dart 3.x primary constructor syntax.

### 4.2. Development, Package & Error Diagnostics
- `dart-resolve-package-conflicts`: Resolve `pubspec.yaml` dependency version conflicts.
- `dart-run-static-analysis`: Run `dart analyze` and `dart fix --apply` during development.
- `dart-fix-runtime-errors`: Locate active stack traces and apply runtime fixes.
- `flutter-fix-layout-issues`: Resolve `RenderFlex` overflow and unbounded height errors.

### 4.3. Testing & Quality Assurance
- `dart-add-unit-test`: Write unit tests for stream bridges, encryption, and SOCKS5 logic.
- `flutter-add-widget-test`: Write component tests for terminal UI, keyboard bar, and host screens.
- `dart-generate-test-mocks`: Generate mock objects with `mockito` and `build_runner`.
- `flutter-add-integration-test`: Configure end-to-end integration tests.
- `dart-collect-coverage`: Generate LCOV test coverage reports.

### 4.4. Platform Tools
- `android-cli`: Manage Android SDK, emulator, and build processes.
- `flutter-setup-localization`: Configure multi-language support (TR/EN).

---

*The Drift table definitions under `lib/shared/database/` are the schema of record; the DAOs beside them are the only sanctioned way to reach it.*
