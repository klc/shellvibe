# Contributing to ShellVibe

Contributions are welcome. Before you spend an evening on a patch, two things
are worth knowing up front — one about the licence, one about the code.

## First: this is a commercial product, and contributions need a CLA

ShellVibe is published under a fair-source licence
([`LICENSE`](LICENSE), explained in [`LICENSING.md`](LICENSING.md)) and sold as
a signed binary through app stores and direct download. That is how the project
is funded.

Shipping a commercial binary means we need the right to distribute every line
in it under terms of our choosing — including the proprietary terms an app
store requires. We hold that right for the code we wrote. We do not
automatically hold it for the code you write: absent an agreement, you keep
your copyright and we may only use your patch under the repository's licence.
One unsigned contribution merged into a release is enough to make that release
undistributable as it stands.

So: **every pull request requires a signed Contributor Licence Agreement**, the
text of which is [`CLA.md`](CLA.md). It is a broad licence grant, not a
copyright assignment — you keep ownership of your work and remain free to use
it anywhere else.

We would rather say this in the first paragraph than have you discover it after
the work is done. If it is a dealbreaker for you, that is a legitimate position
and no hard feelings; the code is here to read and fork either way.

### How signing works

1. Open your pull request as normal.
2. A bot comments with a link on the first PR you open.
3. You sign with your GitHub account. It takes about a minute and is once per
   person, not once per PR.
4. The check goes green and the PR becomes mergeable.

Unsigned pull requests will not be merged, including one-line fixes. A
threshold for "trivial" changes sounds reasonable and turns out to be
impossible to draw, so there isn't one. We also will not reimplement a rejected
patch from memory — that is a derivative work and no cleaner than merging it.

If you are contributing on behalf of an employer, make sure whoever owns your
work output has authorised it; `CLA.md` section 8 covers this.

## Second: how to get a patch accepted

### Before opening a PR

Anything larger than a bug fix, open an issue first. The architecture is
opinionated — layered features under `lib/features/<name>/{data,domain,presentation}`,
Riverpod for state, Drift DAOs as the only way to the database — and a design
that cuts across it is better discussed than rewritten.

### The bar

Every change must clear the same two gates CI enforces on Linux, macOS and
Windows:

```bash
dart analyze     # zero issues, not "zero new issues"
flutter test
```

Beyond that:

- **Stay inside the layering.** `presentation` / `domain` / `data` per feature,
  with `core` and `shared` beneath. Business logic, SSH stream handlers and
  socket listeners must not depend on `BuildContext`.
- **Session-scoped providers are `autoDispose`.** A leaked socket or terminal
  buffer outlives the tab that owned it and is a real bug, not a tidiness one.
- **Secrets are never plaintext.** Passwords, private keys and passphrases go
  through `cryptography` (AES-256-GCM under an Argon2id-derived master key)
  into `flutter_secure_storage`. Host fingerprints are verified against the
  `known_hosts` table. Patches that weaken either will be declined regardless
  of what else they do.
- **Tests come with the change.** New behaviour needs coverage; a bug fix needs
  the test that fails without it.
- **Match the house style.** Read the surrounding file, keep its naming and
  comment density, and touch only what the change requires.

### Security issues do not go here

Do not open a public issue or PR for a vulnerability. Email
**security@shellvibe.dev** — see [`SECURITY.md`](SECURITY.md).

### The name

The licence covers the code; the brand is separate. If your change touches
`assets/brand/`, or adds a use of the ShellVibe name or marks, read
[`TRADEMARK.md`](TRADEMARK.md) first.

## Questions

Licensing and CLA questions: **licensing@shellvibe.dev**. Everything else: open
an issue.
