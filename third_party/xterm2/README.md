# xterm2 vendor patch

This directory vendors `xterm2` 5.2.0 (MIT licensed) with a narrow Android
IME fix in `lib/src/ui/custom_text_edit.dart`.

Android virtual keyboards can emit `TextInputAction.newline` before they send
the final collapsed `TextEditingValue` for an active composing range. The
upstream implementation forwarded the action immediately, sending an empty
terminal command, then inserted the delayed text afterwards. The patch commits
the active composing value before forwarding the action and suppresses exactly
the delayed matching commit.

Keep this dependency as a path dependency until an upstream release includes
an equivalent fix. When upgrading, port the regression coverage in
`test/widget/features/terminal/android_ime_input_test.dart` and remove this
vendor only after testing Gboard, Samsung Keyboard, and a CJK IME on hardware.
