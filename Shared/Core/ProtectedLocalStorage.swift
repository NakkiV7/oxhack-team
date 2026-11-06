import Foundation

public enum ProtectedLocalStorage {
    public static func prepare(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try protect(folder)
    }
    public static func protect(_ url: URL) throws {
        var value = url
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try value.setResourceValues(attributes)
        #if os(iOS) || os(watchOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    public static func write(_ data: Data, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try protect(url)
    }
}
