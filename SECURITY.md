# Security Policy

ShellVibe is an SSH client and a credential vault. A vulnerability here does
not cost a user a session — it costs them their servers. Reports are treated
accordingly.

## Reporting a vulnerability

Email **security@shellvibe.dev**. Please do not open a public issue for a
security problem, and please do not disclose it publicly before we have had a
chance to ship a fix.

Include whatever you have:

- what you found, and what an attacker gets out of it
- the steps to reproduce it, or a proof of concept
- the ShellVibe version and platform you saw it on (Settings → About shows
  both, and copies them to the clipboard)
- whether you believe it is already being exploited

If you would rather encrypt the report, say so in a first message without
details and we will send a key.

## What to expect

| Stage | Target |
| --- | --- |
| Acknowledgement that a human has read it | 48 hours |
| First assessment — severity, whether we can reproduce it | 7 days |
| Fix released, or a written plan with a date | 90 days |

We will tell you when the fix ships, and we will credit you in the release
notes unless you ask us not to. We do not run a paid bounty program.

## Scope

In scope — the parts of the product we control:

- The application itself: the vault and its Argon2id/AES-256-GCM encryption,
  the SSH and Mosh transports, host key verification and the `known_hosts`
  store, SFTP, port forwarding, Device Link pairing and its transport, the
  local MCP server and the `shellvibe-mcp` bridge, and the E2EE cloud sync
  payload format.
- The build and release pipeline, including anything that would let a third
  party influence what a published artifact contains.

Out of scope:

- Vulnerabilities in third-party dependencies, unless ShellVibe's particular
  use of them is what creates the problem. Report those upstream; tell us too
  if we are affected.
- Anything that requires an attacker to already have code execution as the
  user running ShellVibe. The application deliberately runs unsandboxed on
  desktop so it can exec a real login shell, and every local file it writes is
  protected by OS permissions and nothing more. That is a documented design
  decision, not a finding.
- Findings that depend on a user pasting attacker-supplied commands into their
  own terminal.
- Reports produced by a scanner with no demonstrated impact.

## Supported versions

ShellVibe has not had a stable release yet. Until 1.0.0 ships, only the current
`main` branch is supported, and fixes land there. Once 1.0.0 is out this table
will name the versions that receive security fixes.
