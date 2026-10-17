import ContactsUI
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  CNContactPickerDelegate
{
  private var pickResult: FlutterResult?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Conversations and emergency contacts never leave the phone (Q-B4,
  /// step 10a review): the folder with the database (Application Support:
  /// ishara.sqlite, its journal, any damaged copy kept aside) is excluded
  /// from iCloud and computer backups. Excluding a folder excludes what is
  /// in it, also files made later.
  private func excludeDataFromBackup() {
    let files = FileManager.default
    guard
      var url = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return }
    try? files.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Talk keeps the screen on while it is visible (S7-5); no package needed.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IsharaScreen") {
      FlutterMethodChannel(name: "ishara/screen", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          if call.method == "keepOn" {
            UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
            result(nil)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
    // Emergency contacts (Q-T4 phase 1): the system contact picker; it
    // needs no contacts permission. WhatsApp: installed or not.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IsharaContacts") {
      FlutterMethodChannel(name: "ishara/contacts", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { [weak self] call, result in
          switch call.method {
          case "pickPhone":
            guard let self = self, self.pickResult == nil,
              let root = self.presenter()
            else {
              result(nil)
              return
            }
            self.pickResult = result
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            picker.predicateForSelectionOfProperty = NSPredicate(
              format: "key == 'phoneNumbers'")
            root.present(picker, animated: true)
          case "hasWhatsApp":
            result(UIApplication.shared.canOpenURL(URL(string: "whatsapp://send")!))
          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }

  /// The app uses scenes (SceneDelegate), so the app delegate's own window
  /// is nil: present from the active scene's key window, on top of whatever
  /// it already shows.
  private func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var top = window?.rootViewController
    while let shown = top?.presentedViewController { top = shown }
    return top
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
    let number = (property.value as? CNPhoneNumber)?.stringValue
    let name = CNContactFormatter.string(from: property.contact, style: .fullName) ?? ""
    pickResult?(number == nil ? nil : ["name": name, "number": number!])
    pickResult = nil
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    pickResult?(nil)
    pickResult = nil
  }
}
