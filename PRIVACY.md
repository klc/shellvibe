# Privacy

**Last updated:** 2026-09-11 · Applies to ShellVibe 1.0.0 for macOS, Windows and Linux.

ShellVibe is a terminal, SSH and SFTP client. It runs on your machine and talks
to the servers you point it at. This document describes every case in which it
sends anything anywhere, because for a tool that holds server credentials that
is the only part of a privacy policy worth reading.

## The short version

ShellVibe has no account, no analytics, no telemetry and no crash reporting. It
does not phone home. Nothing you type, no host you connect to, and no credential
you store is transmitted to us — we operate no server that could receive it.

## What is stored, and where

Everything ShellVibe knows lives in a database file on your own machine, in the
per-user application-support directory your operating system provides:

| Data | Notes |
| --- | --- |
| Hosts, groups, ports, usernames, jump hosts | Plain text in the local database |
| Identities (SSH keys, passwords) | Encrypted before they are written |
| Known host keys | The fingerprints your client has accepted |
| Snippets, runbooks, saved layouts, workspaces | Plain text in the local database |
| Settings | Theme, fonts, timers, preferences |
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

## Backups

The encrypted backup in Settings writes a file to a location you choose. It is
encrypted with your master password before it is written, and ShellVibe does not
upload it anywhere. Where that file then goes — an external disk, a synced
folder, a cloud drive — is your decision, and that destination's privacy terms
apply to it rather than ours.

## Crashes

If ShellVibe crashes it appends the error and stack trace to a log file on your
machine. The file is never transmitted. If you choose to attach it to a bug
report, read it first: a stack trace from a terminal client can contain a host
name or a path.

## Children

ShellVibe is a tool for system administration and software development. It is
not directed at children and collects no data from anyone, of any age.

## Your rights

Under the GDPR, the Turkish KVKK and comparable laws, data subjects have rights
of access, rectification, erasure and portability over personal data held by a
controller. We hold none: there is no account, no server and no record of you.
The data described above is under your control on your own device, and deleting
the application's data directory removes it.

## Changes

This document is versioned in the repository alongside the code. Material
changes are noted in `CHANGELOG.md` and this file's "last updated" date moves.

## Contact

Security reports: see `SECURITY.md`. Anything else: open an issue in the
repository.
