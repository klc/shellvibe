# Licensing

ShellVibe's source is published under the **Functional Source License, Version
1.1, ALv2 Future License** (`FSL-1.1-ALv2`). The full text is in
[`LICENSE`](LICENSE), and that text — not this page — is what governs. This
page explains what it means in practice.

## What you may do

Read the code, build it, run it, change it, and redistribute your changes. That
covers essentially everything people want from a terminal client's source:
using it at work, auditing the crypto before you trust it with your keys,
patching a bug for your own fleet, teaching from it, forking it to try an idea.
None of that needs to be asked for.

## What you may not do

One thing: a **Competing Use**. You may not take ShellVibe and offer it — or
something substantially like it — to other people as a commercial product or
service. Publishing a rebranded ShellVibe to an app store, or selling a hosted
service built on it, is the case the licence is written to prevent.

That restriction exists because it is the one that actually threatened this
project. A copyleft licence would not have stopped a rebranded fork reaching an
app store; it would only have made the store harder to reach for us. So the
grant is broad and the single carve-out is narrow.

## Not "open source"

`FSL-1.1-ALv2` is not approved by the Open Source Initiative, because it
discriminates against a field of use. We therefore do not call ShellVibe open
source. The accurate terms are **fair source** or **source available**, and we
use those. If a licence checklist in your organisation requires an OSI-approved
licence, this one will not satisfy it — better to know that from the README
than from a lawyer three months in.

## Every release becomes Apache 2.0

The restriction has an expiry date, and the clock is per release. Two years
after we make a given version available, that version is additionally licensed
under the **Apache License, Version 2.0**, irrevocably, with everything Apache
2.0 grants — including its patent licence. Nothing needs to be requested and we
cannot take it back.

So the code you are reading is protected while it is current, and free by any
definition once it is two years old:

```bash
# The tree as it stood two years ago is Apache 2.0 today.
git checkout "$(git rev-list -n 1 --before='2 years ago' main)"
```

## Distribution by us

We hold the copyright, so the licence constrains others and not ourselves. The
same code is published here and shipped as a signed binary through the app
stores and direct downloads. There is no second, hidden edition: what the store
installs is built from this tree.

## Commercial licences

If you want to do something the Permitted Purpose does not cover, that is a
conversation, not a refusal. Write to **licensing@shellvibe.dev** with what you
have in mind.

## Contributions

Contributions are welcome and require a signed Contributor Licence Agreement,
for reasons set out plainly in [`CONTRIBUTING.md`](CONTRIBUTING.md). The short
version: we distribute this code commercially, so we need the right to keep
doing that with the parts you write.

## The name and the logo

The licence covers the code. It does not grant any right to the ShellVibe name
or marks — the FSL says so in its Trademarks clause, and
[`TRADEMARK.md`](TRADEMARK.md) sets out what that means for a fork. Fork the
software freely; ship it under your own name.

## Third-party components

The dependency tree is predominantly MIT, BSD and Apache-2.0, and each of those
licences asks that its notice travel with the distributed binary. The app
carries them: **Settings → About → Open source licenses** renders the notices
Flutter collects from the packages actually linked into the build.

One dependency is our own fork, maintained in the open:

| Component  | Upstream           | Notes                                        |
| :--------- | :----------------- | :------------------------------------------- |
| `xterm3`   | `xterm2` (MIT)     | Published under AGPL-3.0; see its own repo.   |

`dartssh2` used to be a second: we carried a fork while our transport, KEX and
SFTP fixes were in review. They are all upstream as of 4.0.1, so the dependency
is the plain MIT package from pub.dev again.

`xterm3` is licensed separately from ShellVibe. Its AGPL-3.0 terms apply to
anyone taking it on its own; we distribute it inside ShellVibe under our own
copyright as its sole author. If you want `xterm3` in a closed product, that is
a commercial licence question — same address as above.

---

*This file is a summary written for developers, not legal advice. Where it and
[`LICENSE`](LICENSE) disagree, `LICENSE` wins.*
