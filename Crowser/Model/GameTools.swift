import GameController
import UIKit
import WebKit

/// A keyboard key a web game can be sent from the on-screen pad or a controller.
enum GameKey: String, CaseIterable, Identifiable, Hashable {
    case up, down, left, right
    case w, a, s, d
    case space, enter, shift, escape
    case z, x, c, e, f, q, r, j, k

    var id: String { rawValue }

    /// KeyboardEvent.key, KeyboardEvent.code and the legacy keyCode.
    var event: (key: String, code: String, keyCode: Int) {
        switch self {
        case .up: return ("ArrowUp", "ArrowUp", 38)
        case .down: return ("ArrowDown", "ArrowDown", 40)
        case .left: return ("ArrowLeft", "ArrowLeft", 37)
        case .right: return ("ArrowRight", "ArrowRight", 39)
        case .space: return (" ", "Space", 32)
        case .enter: return ("Enter", "Enter", 13)
        case .shift: return ("Shift", "ShiftLeft", 16)
        case .escape: return ("Escape", "Escape", 27)
        default:
            let letter = rawValue
            let code = Int(letter.uppercased().unicodeScalars.first?.value ?? 65)
            return (letter, "Key" + letter.uppercased(), code)
        }
    }

    var label: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .space: return "Space"
        case .enter: return "Enter"
        case .shift: return "Shift"
        case .escape: return "Esc"
        default: return rawValue.uppercased()
        }
    }

    /// Keys offered for the two pad buttons.
    static let buttonChoices: [GameKey] = [.space, .enter, .shift, .z, .x, .c, .e, .f, .q, .r, .j, .k, .w, .up, .escape]

    /// The four keys a stick presses.
    static func stick(_ style: String) -> (up: GameKey, down: GameKey, left: GameKey, right: GameKey) {
        style == "wasd" ? (.w, .s, .a, .d) : (.up, .down, .left, .right)
    }
}

extension PageScripts {
    /// Lets Crowser press keys in the page and every frame inside it (many web games run in an iframe).
    static let keys = """
    (function(){
    if(window.__crowserKeys)return;window.__crowserKeys=true;
    function target(){var a=document.activeElement;if(a&&a!==document.body&&a!==document.documentElement)return a;return document.querySelector('canvas')||document.body||document;}
    function fire(k,c,n,down){
      var t=target();
      var o={key:k,code:c,keyCode:n,which:n,bubbles:true,cancelable:true,composed:true};
      var e=new KeyboardEvent(down?'keydown':'keyup',o);
      try{Object.defineProperty(e,'keyCode',{get:function(){return n}});Object.defineProperty(e,'which',{get:function(){return n}});}catch(_){}
      t.dispatchEvent(e);
      if(down&&k.length===1){var p=new KeyboardEvent('keypress',{key:k,code:c,charCode:k.charCodeAt(0),keyCode:n,which:n,bubbles:true,cancelable:true});t.dispatchEvent(p);}
    }
    window.__crowserKey=function(k,c,n,down){
      fire(k,c,n,down);
      for(var i=0;i<window.frames.length;i++){try{window.frames[i].postMessage({__crowserKey:[k,c,n,down]},'*');}catch(_){}}
    };
    window.addEventListener('message',function(m){var d=m.data&&m.data.__crowserKey;if(d&&m.source===window.parent)window.__crowserKey(d[0],d[1],d[2],d[3]);});
    })();
    """
}

// MARK: - Tab: keys, pad, rotation

extension BrowserTab {
    private var gameSite: SiteSetting { store?.sites.setting(for: url) ?? SiteSetting() }

    var padStick: String { gameSite.padStick }
    var padA: GameKey { GameKey(rawValue: gameSite.padA) ?? .space }
    var padB: GameKey { GameKey(rawValue: gameSite.padB) ?? .enter }
    var controllerKeys: Bool { gameSite.controllerKeys }

    /// Presses or releases a key in the page.
    func press(_ key: GameKey, _ down: Bool) {
        guard down != heldKeys.contains(key) else { return }
        if down { heldKeys.insert(key) } else { heldKeys.remove(key) }
        let event = key.event
        let escaped = event.key.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript(
            "window.__crowserKey&&window.__crowserKey('\(escaped)','\(event.code)',\(event.keyCode),\(down));",
            completionHandler: nil
        )
    }

    func releaseKeys() {
        for key in heldKeys { press(key, false) }
    }

    func togglePad() {
        let on = !padOn
        store?.sites.update(url) { $0.pad = on }
        padOn = on
        if on { webView.evaluateJavaScript(PageScripts.keys, completionHandler: nil) } else { releaseKeys() }
        Haptics.select()
    }

    func setPadStick(_ style: String) {
        store?.sites.update(url) { $0.padStick = style }
        objectWillChange.send()
    }

    func setPadButton(a: GameKey? = nil, b: GameKey? = nil) {
        store?.sites.update(url) { site in
            if let a { site.padA = a.rawValue }
            if let b { site.padB = b.rawValue }
        }
        objectWillChange.send()
    }

    func toggleControllerKeys() {
        let on = !controllerKeys
        store?.sites.update(url) { $0.controllerKeys = on }
        if on { webView.evaluateJavaScript(PageScripts.keys, completionHandler: nil) }
        objectWillChange.send()
        Haptics.select()
    }

    /// nil follows the phone; "portrait" or "landscape" locks this site.
    func setOrientation(_ value: String?) {
        store?.sites.update(url) { $0.orientation = value }
        orientation = value
        Haptics.select()
    }
}

// MARK: - Rotation lock

enum OrientationLock {
    @MainActor static var mask: UIInterfaceOrientationMask = .all

    @MainActor static func apply(_ value: String?) {
        let wanted: UIInterfaceOrientationMask
        switch value {
        case "portrait": wanted = .portrait
        case "landscape": wanted = .landscape
        default: wanted = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
        guard wanted != mask else { return }
        mask = wanted
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted)) { _ in }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ControllerBridge.shared.start()
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        ControllerBridge.shared.store?.sleepBackgroundTabs(force: true)
    }
}

// MARK: - Controller → keys

/// For web games that only understand a keyboard: a controller's stick, d-pad and buttons press keys.
/// Games that use the gamepad API already get the controller directly from WebKit.
@MainActor
final class ControllerBridge {
    static let shared = ControllerBridge()
    weak var store: BrowserStore?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller) }
        }
        GCController.controllers().forEach(attach)
    }

    private func attach(_ controller: GCController) {
        controller.handlerQueue = .main
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] gamepad, _ in
            Task { @MainActor in self?.update(gamepad) }
        }
        store?.showToast("\(controller.vendorName ?? "Controller") connected")
    }

    private func update(_ pad: GCExtendedGamepad) {
        guard let tab = store?.current, tab.gameMode, tab.controllerKeys else { return }
        let keys = GameKey.stick(tab.padStick)
        let x = pad.leftThumbstick.xAxis.value + pad.dpad.xAxis.value
        let y = pad.leftThumbstick.yAxis.value + pad.dpad.yAxis.value
        tab.press(keys.up, y > 0.4)
        tab.press(keys.down, y < -0.4)
        tab.press(keys.left, x < -0.4)
        tab.press(keys.right, x > 0.4)
        tab.press(tab.padA, pad.buttonA.isPressed)
        tab.press(tab.padB, pad.buttonB.isPressed)
        tab.press(.shift, pad.buttonX.isPressed)
        tab.press(.escape, pad.buttonMenu.isPressed)
    }
}
