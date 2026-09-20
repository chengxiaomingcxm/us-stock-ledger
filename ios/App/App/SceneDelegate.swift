import UIKit
import SwiftUI
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    // 2.0：原生 SwiftUI 界面替换 WebView；Capacitor 仅保留构建与既有插件依赖，不再承载界面。
    @MainActor
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        // 诊断日志：启动时先核对上次是否正常结束，再写本次运行环境。
        Diagnostics.start()
        window?.rootViewController = UIHostingController(rootView: RootView().environmentObject(AppState()))
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

// Local plugin: no third-party key storage or network service.
class LedgerBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() { bridge?.registerPluginInstance(LedgerSecretsPlugin()) }
}

import Security
@objc(LedgerSecretsPlugin)
public class LedgerSecretsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LedgerSecretsPlugin"
    public let jsName = "LedgerSecrets"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTheme", returnType: CAPPluginReturnPromise)
    ]
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.personal.stockledger.market", kSecAttrAccount as String: "configuration"] }
    @objc func setTheme(_ call: CAPPluginCall) {
        let theme = call.getString("theme") ?? "system"
        DispatchQueue.main.async {
            self.bridge?.viewController?.view.window?.overrideUserInterfaceStyle = theme == "dark" ? .dark : theme == "light" ? .light : .unspecified
            self.bridge?.webView?.isOpaque = false
            self.bridge?.webView?.backgroundColor = .systemBackground
            self.bridge?.webView?.scrollView.backgroundColor = .systemBackground
            self.bridge?.viewController?.setNeedsStatusBarAppearanceUpdate()
            call.resolve()
        }
    }
    @objc func read(_ call: CAPPluginCall) {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { call.resolve([:]); return }
        guard status == errSecSuccess, let bytes = result as? Data,
            let value = String(data: bytes, encoding: .utf8) else { call.reject("无法读取系统钥匙串"); return }
        call.resolve(["value": value])
    }
    @objc func write(_ call: CAPPluginCall) {
        guard let value = call.getString("value"), let bytes = value.data(using: .utf8) else { call.reject("设置格式无效"); return }
        let attributes: [String: Any] = [kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            for (key, value) in attributes { q[key] = value }
            status = SecItemAdd(q as CFDictionary, nil)
        }
        if status == errSecSuccess { call.resolve() } else { call.reject("无法保存到系统钥匙串") }
    }
}
