import Foundation

struct ByteFormatter {
    static let shared = ByteFormatter()
    
    private let units = ["B", "KB", "MB", "GB", "TB"]
    
    private init() {}
    
    func format(_ bytes: UInt64, includeSpace: Bool = true) -> String {
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        let space = includeSpace ? " " : ""
        return String(format: "%.1f\(space)%@", value, units[unitIndex])
    }
    
    func formatShort(_ bytes: UInt64) -> String {
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        if unitIndex == 0 {
            return String(format: "%.0f%@", value, units[unitIndex])
        }
        return String(format: "%.1f%@", value, units[unitIndex])
    }
}
