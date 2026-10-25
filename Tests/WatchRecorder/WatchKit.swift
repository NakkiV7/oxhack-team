// Test-only haptic boundary. Never linked into the Watch app.
public enum WKHapticType { case click }
public final class WKInterfaceDevice {
    public static func current() -> WKInterfaceDevice { WKInterfaceDevice() }
    public func play(_ type: WKHapticType) {}
}
