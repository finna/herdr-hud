import AppKit
import CoreGraphics
// An isolated fullscreen fixture. Does not type into or modify any user app.
final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var previous: NSRunningApplication?
    var completed = false
    func applicationDidFinishLaunching(_ notification:Notification) {
        previous=NSWorkspace.shared.frontmostApplication
        window=NSWindow(contentRect:NSRect(x:100,y:100,width:1000,height:650),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Herdr HUD fullscreen verification"; window.delegate=self;window.collectionBehavior=[.fullScreenPrimary]
        window.backgroundColor=NSColor(calibratedRed:0.12,green:0.17,blue:0.23,alpha:1)
        let label=NSTextField(labelWithString:"Herdr HUD fullscreen check\n\nThis temporary window closes automatically.")
        label.frame=NSRect(x:100,y:180,width:800,height:180);label.font=NSFont.systemFont(ofSize:28);label.textColor = .white;window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        DispatchQueue.main.asyncAfter(deadline:.now()+1){self.window.toggleFullScreen(nil)}
        DispatchQueue.main.asyncAfter(deadline:.now()+25){if !self.completed {self.finish(["error":"Fullscreen transition timed out"])} }
    }
    func windowDidEnterFullScreen(_ notification:Notification) {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.herdr.community.hud.control"),object:"open",userInfo:nil,deliverImmediately:true)
        DispatchQueue.main.asyncAfter(deadline:.now()+5) {
            let windows=(CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]]) ?? []
            let own=windows.firstIndex{($0[kCGWindowNumber as String] as? Int)==self.window.windowNumber}
            let diagnosticURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Herdr HUD/diagnostics.json")
            let diagnostic=(try? Data(contentsOf:diagnosticURL)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]} ?? [:]
            let hudPID=diagnostic["pid"] as? Int32
            let hud=windows.enumerated().filter{($0.element[kCGWindowOwnerPID as String] as? Int32)==hudPID}
            let front=NSWorkspace.shared.frontmostApplication
            let data:[String:Any] = ["fullscreen":self.window.styleMask.contains(.fullScreen),"fixtureWindowID":self.window.windowNumber,"fixtureBounds":own.map{windows[$0][kCGWindowBounds as String] ?? [:]} ?? [:],"fixtureIndex":own ?? -1,"hudWindows":hud.map{["index":$0.offset,"layer":$0.element[kCGWindowLayer as String] ?? -1,"bounds":$0.element[kCGWindowBounds as String] ?? [:]]},"hudAboveFullscreen":own.map{index in hud.contains{$0.offset<index}} ?? false,
            "overlapsFullscreen":own.map{ index in
                guard let frame=windows[index][kCGWindowBounds as String] as? [String:Any],let rect=CGRect(dictionaryRepresentation:frame as CFDictionary) else{return false}
                return hud.allSatisfy{ element in
                    guard let bounds=element.element[kCGWindowBounds as String] as? [String:Any],let hudRect=CGRect(dictionaryRepresentation:bounds as CFDictionary) else{return false}
                    return rect.intersects(hudRect)
                } && hud.count >= 2
            } ?? false,"fixtureStillFrontmost":front?.processIdentifier==ProcessInfo.processInfo.processIdentifier,"frontmost":front?.localizedName ?? "unknown","capturePermission":CGPreflightScreenCaptureAccess()]
            self.finish(data)
        }
    }
    func finish(_ data:[String:Any]) {
        guard !completed else{return};completed=true
        let path=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/herdr-hud-desktop/.evidence/fullscreen-probe.json")
        try? FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        try? JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:path)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.herdr.community.hud.control"),object:"close",userInfo:nil,deliverImmediately:true)
        if window.styleMask.contains(.fullScreen){window.toggleFullScreen(nil)}
        DispatchQueue.main.asyncAfter(deadline:.now()+2){self.previous?.activate(options:[]);NSApp.terminate(nil)}
    }
}
let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=Probe();app.delegate=delegate;app.run()
