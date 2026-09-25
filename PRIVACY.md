# Privacy

**Last updated:** 2026-09-25 · Applies to ShellVibe 1.5.0 for macOS,
Windows and Linux.

ShellVibe is a terminal, SSH and SFTP client. It runs on your machine and talks
to the servers you point it at. This document describes every case in which it
sends anything anywhere, because for a tool that holds server credentials that
is the only part of a privacy policy worth reading.

## The short version

ShellVibe has no analytics, no telemetry and no automatic crash reporting.

**Without an account** — the default — nothing you type, no host you connect
to and no credential you store is transmitted to us. The app works fully
signed out.

**With an account**, which is optional and exists for cloud backup and sync
between your devices, we run a server at `api.shellvibe.dev`. It holds your
name, your email address, a list of your signed-in devices, and your backups
and sync history **in encrypted form**. The passphrase that encrypts them never
leaves your devices, so we cannot read your hosts, credentials, snippets or
anything else inside them.

The rest of this page is the detail behind those two paragraphs.

## What is stored on your device

Everything ShellVibe knows lives in a database file on your own machine, in the
per-user application-support directory your operating system provides:

| Data | Notes |
| --- | --- |
| Hosts, groups, ports, usernames, jump hosts | Plain text in the local database |
| Identities (SSH keys, passwords) | Encrypted before they are written |
| Environment variables kept in the vault | Names in plain text; values encrypted before they are written |
| Known host keys | The fingerprints your client has accepted |
| Snippets, runbooks, saved layouts, workspaces | Plain text in the local database |
| Settings | Theme, fonts, timers, preferences |
| Account session, backup passphrase, recovery code | In the operating system's keychain or credential store, only when you sign in and set up backup |
| Crash logs | A local file; see **Crashes** below |

Identity secrets are encrypted with a key derived from your master password and
held in your operating system's keychain or credential store. Without that
password the encrypted rows are not readable, including by anyone who copies the
database file.

## When ShellVibe uses the network

**The servers you connect to.** SSH, Mosh and SFTP sessions go directly from
your machine to the host you named. There is no relay and no proxy of ours in
between. What travels is what you typed and what the server answered.

**Checking for updates — only when you ask.** Settings → About has a "check for
updates" button. Pressing it makes one unauthenticated HTTPS request to GitHub's
public releases API for this project. The request carries no identifier of any
kind; GitHub sees what it sees for any anonymous visitor, namely your IP address
and your HTTP client's user agent, under
[GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement).
ShellVibe never performs this check on its own, on a schedule or at launch.

**Fonts you choose.** ShellVibe ships with its interface and terminal fonts
bundled, and those need no network. If you pick one of the optional families in
Settings, it is downloaded once from Google's font CDN (`fonts.googleapis.com`,
`fonts.gstatic.com`) and cached on disk; Google sees that request. Staying on a
bundled font — the default in both cases — means no font request is ever made.

**Device Link.** Pairing a phone with a desktop session communicates over your
local network, directly between the two devices. Nothing leaves your network.
This version has no relay for Device Link.

**Your ShellVibe account — only if you sign in.** Everything in the next
section happens only while you are signed in. Signing out stops it.

## Your account and our server

### What the server holds

| Data | Readable by us? | Kept for |
| --- | --- | --- |
| Name and email address you registered with | Yes | Until you delete the account |
| Password | No — stored as a bcrypt hash | Until you delete the account |
| Each device you signed in on: its name, platform (macOS, Windows, …), app version and when it was last seen | Yes | Until you delete the account. Removing a device signs it out but keeps the entry, marked removed |
| Public keys each device generated for itself | Public by design | Until you delete the account |
| Cloud backups | **No** — encrypted on your device with your backup passphrase (Argon2id, AES-256-GCM) | The newest 10 revisions; older ones are deleted automatically |
| Size, checksum, time and originating device of each backup | Yes | As long as the backup it describes |
| Sync history: one encrypted record per change | **No** — encrypted with a key that exists only on your devices and inside your encrypted backups | 90 days |
| Order, time and originating device of each sync record | Yes | 90 days |

A device's name is your computer's network name as the operating system
reports it (for example `alices-macbook`).

Sync records are labelled with keyed hashes rather than the names of what
changed, so we cannot tell a host from a snippet. What the metadata above does
reveal is *when* you made changes, *from which device*, and roughly *how many*.

The recovery code shown when you set up backup can open your backups if you
forget the passphrase. We never receive it. If you lose both, nobody —
including us — can recover the contents.

### The web panel

`shellvibe.dev/panel` lets you sign in from a browser to see your devices and
backups. Viewing a backup's contents there asks for your backup passphrase and
decrypts **inside your browser**; the passphrase is not sent to us. The code
that does this is served by our server, so using the panel means trusting that
code the same way you trust the app. The panel uses a session cookie while you
are signed in.

### Server logs

Our server records each request's time, method, path, status, duration and the
account or device it came from, and the web server that terminates TLS records
the requesting IP address. Authorization headers, cookies and tokens are
stripped before anything is written. Logs are used to operate and secure the
service and for nothing else.

### Where it runs

The server runs on a virtual machine we rent from Contabo GmbH. Copies of its
database are kept for 14 days, so data you delete disappears from them within
14 days.

We do not sell or share account data, send marketing email, or use it for
advertising. No one else receives it except the hosting provider that stores it
on our behalf.

## Backups to a file

The encrypted backup in Settings can also be written to a file at a location you
choose. It is encrypted before it is written, and ShellVibe does not upload it
anywhere. Where that file then goes — an external disk, a synced folder, a cloud
drive — is your decision, and that destination's privacy terms apply to it
rather than ours.

## Crashes

If ShellVibe crashes it appends the error and stack trace to a log file on your
machine. The app never transmits it.

On the next launch after a crash, and from Settings → About → Report a problem,
ShellVibe offers to open a **public** GitHub issue with the error log filled in.
Your home folder, IP addresses and `user@host` pairs are masked first, but a
host name or a path can still slip through, so read the report before you
submit it. Nothing is sent unless you submit the issue yourself in your
browser, under GitHub's privacy statement.

## Children

ShellVibe is a tool for system administration and software development. It is
not directed at children and does not knowingly collect data from them.

## Your rights

Under the GDPR, the Turkish KVKK and comparable laws you have rights of access,
rectification, erasure and portability over personal data we hold. Most of them
are self-service in the web panel:

- **Export** — the panel's account export downloads everything the server holds
  about you. Backup contents are listed there and downloaded from the panel's
  backup page, since each can be several megabytes.
- **Erase** — the panel's danger zone deletes your account, every device, every
  backup and your sync history immediately. Database copies age it out within
  14 days.
- **Rectify, or anything else** — write to the contact below.

Data that never left your device is under your control there; deleting the
application's data directory removes it.

## Changes

This document is versioned in the repository alongside the code. Material
changes are noted in `CHANGELOG.md` and this file's "last updated" date moves.

## Contact

The data controller is Mustafa Kılıç. Privacy requests and security reports:
`security@shellvibe.dev` (see `SECURITY.md`). Anything else: open an issue in
the repository.
