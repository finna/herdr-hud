import Foundation

func notificationFrame(bubble: NSRect, size: NSSize, visibleFrame: NSRect, gap: CGFloat = 10) -> NSRect {
    let size = NSSize(width:min(size.width,visibleFrame.width),height:min(size.height,visibleFrame.height))
    func fit(_ origin: NSPoint) -> NSRect {
        NSRect(x:min(max(origin.x,visibleFrame.minX),visibleFrame.maxX-size.width),
               y:min(max(origin.y,visibleFrame.minY),visibleFrame.maxY-size.height),width:size.width,height:size.height)
    }
    // Cocoa coordinates increase upward. Try above and below before either side.
    let candidates = [
        NSPoint(x:bubble.midX-size.width/2,y:bubble.maxY+gap),
        NSPoint(x:bubble.midX-size.width/2,y:bubble.minY-size.height-gap),
        NSPoint(x:bubble.maxX+gap,y:bubble.midY-size.height/2),
        NSPoint(x:bubble.minX-size.width-gap,y:bubble.midY-size.height/2)
    ].map(fit)
    let clearance = bubble.insetBy(dx:-gap,dy:-gap)
    return candidates.first(where:{ !$0.intersects(clearance) }) ?? candidates.min(by: {
        let a = $0.intersection(bubble), b = $1.intersection(bubble)
        return max(0,a.width)*max(0,a.height) < max(0,b.width)*max(0,b.height)
    })!
}
