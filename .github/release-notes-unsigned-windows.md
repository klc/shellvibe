
## The Windows installer is not code-signed

There is no Windows code-signing certificate behind this release yet. Windows
shows "Windows protected your PC" with an unknown publisher. Press
**More info**, then **Run anyway**. The warning will not fade with time:
reputation accumulates against a certificate, and there is none. Verify the
checksums above before you run it.

If turning off your operating system's malware protection for an SSH client is
not a trade you want to make, which is a reasonable position, build it
yourself instead:

```
git clone https://github.com/klc/shellvibe && cd shellvibe
flutter build windows --release
```
