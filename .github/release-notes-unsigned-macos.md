
## The macOS build is not code-signed

This release was built without the Developer ID certificate. macOS does not
know who built it, and it will say so. That warning is accurate: verify the
checksums above before you run it.

macOS refuses the app outright and reports that it cannot be checked for
malware. To open it anyway:

1. Drag ShellVibe to Applications and try to open it once. It will be blocked.
2. Open **System Settings → Privacy & Security**, scroll to Security, and press
   **Open Anyway** next to the ShellVibe message.
3. Confirm with your password.

macOS 15 removed the old Control-click shortcut, so this is the only route, and
you will repeat it after every update.
