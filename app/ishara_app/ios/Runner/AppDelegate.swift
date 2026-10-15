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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
              let root = self.window?.rootViewController
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
