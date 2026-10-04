import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GetCurrentPackageFullNameNative =
    Int32 Function(Pointer<Uint32> length, Pointer<Utf16> name);
typedef _GetCurrentPackageFullName =
    int Function(Pointer<Uint32> length, Pointer<Utf16> name);

/// `APPMODEL_ERROR_NO_PACKAGE`: the process has no package identity.
const _appModelErrorNoPackage = 15700;

/// Whether this Windows process runs with package identity, i.e. was started
/// from its MSIX.
///
/// Asked of Windows rather than read off the install path: a Store install
/// lives under `WindowsApps`, but a package registered from a folder in
/// Developer Mode runs from that folder with the same identity, and behaves
/// the same way. `windows/runner/package_integration.cpp` makes the same call.
bool hasWindowsPackageIdentity() {
  final getCurrentPackageFullName = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        _GetCurrentPackageFullNameNative,
        _GetCurrentPackageFullName
      >('GetCurrentPackageFullName');
  final length = calloc<Uint32>();
  try {
    // With no buffer the call only reports the name's length, or that there
    // is no name to report.
    return getCurrentPackageFullName(length, nullptr) !=
        _appModelErrorNoPackage;
  } finally {
    calloc.free(length);
  }
}
