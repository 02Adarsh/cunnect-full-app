import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // ⭐ v63: cunnect:// deep link (password reset from email) — same
  // 'cunnect/deeplink' channel contract as Android's MainActivity.
  private var pendingLink: String?
  private var linkChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Cold start from a cunnect:// link
    if let url = launchOptions?[.url] as? URL, url.scheme == "cunnect" {
      pendingLink = url.absoluteString
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "cunnect/deeplink",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialLink" {
          result(self?.pendingLink)
          self?.pendingLink = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      linkChannel = channel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // cunnect:// link arrives while the app is running
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "cunnect" {
      pendingLink = url.absoluteString
      linkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
