// Test-only haptic boundary. Never linked into the Watch app.
public enum WKHapticType { case click }
public final class WKInterfaceDevice {
    public static var played = 0
    public static func current() -> WKInterfaceDevice { WKInterfaceDevice() }
    public func play(_ type: WKHapticType) { Self.played += 1 }
}
