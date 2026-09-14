import AppKit
if CommandLine.arguments.contains("--roster") {
    print(encode(HerdrClient().snapshot()))
} else if let command = CommandLine.arguments.dropFirst().first, ["--open","--close","--toggle","--hide","--show","--snapshot","--inspect","--verify-ui"].contains(command) {
    DistributedNotificationCenter.default().postNotificationName(HUDApp.channel,object:String(command.dropFirst(2)),userInfo:nil,deliverImmediately:true)
} else {
    let identifier = Bundle.main.bundleIdentifier ?? "org.herdr.community.hud"
    let existing = NSRunningApplication.runningApplications(withBundleIdentifier:identifier).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !existing.isEmpty { DistributedNotificationCenter.default().postNotificationName(HUDApp.channel,object:"toggle",userInfo:nil,deliverImmediately:true) }
    else { let app = NSApplication.shared; let delegate = HUDApp(); app.delegate = delegate; app.run() }
}
