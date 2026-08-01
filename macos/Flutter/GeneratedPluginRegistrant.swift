//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_drop
import flutter_secure_storage_darwin
import hotkey_manager_macos
import local_auth_darwin
import screen_retriever_macos
import tray_manager
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  DesktopDropPlugin.register(with: registry.registrar(forPlugin: "DesktopDropPlugin"))
  FlutterSecureStorageDarwinPlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
  HotkeyManagerMacosPlugin.register(with: registry.registrar(forPlugin: "HotkeyManagerMacosPlugin"))
  LocalAuthPlugin.register(with: registry.registrar(forPlugin: "LocalAuthPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  TrayManagerPlugin.register(with: registry.registrar(forPlugin: "TrayManagerPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
