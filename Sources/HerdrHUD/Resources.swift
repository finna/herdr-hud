import Foundation
enum HUDResources {
    static var root: URL {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url:resources.appendingPathComponent("HerdrHUD_HerdrHUD.bundle")),
           let root = bundle.url(forResource:"Resources",withExtension:nil) { return root }
        return Bundle.module.url(forResource:"Resources",withExtension:nil)!
    }
}
