# AGENTS.md — Agent Operating Guide for Terly2

> **Repository Operating Manual for AI Coding Agents working on Terly2.**  
> Read this document completely before implementing features or modifying code in this codebase.

---

## 1. Primary Directives & Architecture References

Terly2 is a modern, high-performance, cross-platform (iOS, Android, macOS, Windows, Linux) terminal, SSH/SFTP client, and remote infrastructure workstation built with **Flutter SDK 3.x** and **Dart 3.x**.

All agents working on this repository **MUST** adhere to the designs, feature specifications, and technology stack defined in the official project documentation:

1. 📄 [**Feature Specification & Competitor Benchmark**](file:///Users/mkilic/www/klc/terly2/docs/features_and_competitor_analysis.md) (`docs/features_and_competitor_analysis.md`)
   - Detailed product features: Local shell, SSHv2, Mosh, Dual-pane SFTP, Port Forwarding (Local/Remote/Dynamic), Workspaces, Snippets, Runbooks, AI Assistant, and competitor analysis (Termius, Warp, Tabby, Blink Shell, MobaXterm).
2. 📄 [**Technical Architecture Specification**](file:///Users/mkilic/www/klc/terly2/docs/tech_spec.md) (`docs/tech_spec.md`)
   - Mandatory tech stack (`flutter_riverpod`, `xterm3`, `dart_ssh2`, `flutter_pty`, `drift` SQLite, `flutter_secure_storage`, `cryptography` AES-256-GCM / Argon2id).
   - Drift SQLite database schema, Stream Bridge architecture, edge cases, and OS constraints (iOS sandbox, Host key verification, background keep-alive, sticky keys, tab lifecycle).

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

Agents working on Terly2 SHOULD utilize the following installed skills when relevant:

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

*Refer to [`docs/tech_spec.md`](file:///Users/mkilic/www/klc/terly2/docs/tech_spec.md) for full database schemas, sequence diagrams, and module breakdowns.*
