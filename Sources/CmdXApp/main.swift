import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory keeps CmdX out of the Dock and out of the app switcher. This is
// belt-and-braces alongside LSUIElement in Info.plist, which is what actually
// governs launch behaviour.
app.setActivationPolicy(.accessory)
app.run()
