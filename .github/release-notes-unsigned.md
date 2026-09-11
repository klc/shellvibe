
## These builds are not code-signed

There is no code-signing certificate behind this release yet. Your operating
system does not know who built these files, and it will say so. That warning is
accurate: verify the checksums above before you run anything here.

**macOS** refuses the app outright and reports that it cannot be checked for
malware. To open it anyway:

1. Drag ShellVibe to Applications and try to open it once. It will be blocked.
2. Open **System Settings → Privacy & Security**, scroll to Security, and press
   **Open Anyway** next to the ShellVibe message.
3. Confirm with your password.

macOS 15 removed the old Control-click shortcut, so this is the only route, and
you will repeat it after every update.

**Windows** shows "Windows protected your PC" with an unknown publisher. Press
**More info**, then **Run anyway**. The warning will not fade with time:
reputation accumulates against a certificate, and there is none.

**Linux** needs nothing special. `chmod +x` the AppImage and run it.

Signed builds are planned. Until then — if turning off your operating system's
malware protection for an SSH client is not a trade you want to make, which is
a reasonable position — build it yourself instead:

```
git clone https://github.com/klc/shellvibe && cd shellvibe
flutter build macos --release      # or: linux, windows
```
