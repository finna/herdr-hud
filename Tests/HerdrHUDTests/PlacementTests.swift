import XCTest
@testable import HerdrHUD

final class PlacementTests: XCTestCase {
    func testScreenEdgesNeverPushNotificationUnderButton() {
        for screen in [NSRect(x:0,y:30,width:2560,height:1380),NSRect(x:-1920,y:-200,width:1920,height:1050)] {
            for x in [screen.minX,screen.midX,screen.maxX-64] {
                for y in [screen.minY,screen.midY,screen.maxY-64] {
                    let bubble = NSRect(x:x,y:y,width:64,height:64)
                    let toast = notificationFrame(bubble:bubble,size:NSSize(width:320,height:92),visibleFrame:screen)
                    XCTAssertTrue(screen.contains(toast))
                    XCTAssertFalse(toast.intersects(bubble.insetBy(dx:-9,dy:-9)))
                }
            }
        }
    }
    func testAbovePreferredAndBelowAtTopEdge() {
        let screen = NSRect(x:0,y:0,width:1000,height:800)
        let middle = NSRect(x:700,y:350,width:64,height:64)
        let above = notificationFrame(bubble:middle,size:NSSize(width:320,height:92),visibleFrame:screen)
        XCTAssertEqual(above.minY,middle.maxY+10)
        let top = NSRect(x:936,y:736,width:64,height:64)
        let below = notificationFrame(bubble:top,size:NSSize(width:320,height:92),visibleFrame:screen)
        XCTAssertEqual(below.maxY,top.minY-10)
        XCTAssertFalse(below.intersects(top))
    }
}
