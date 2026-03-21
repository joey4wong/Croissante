import Foundation

struct DailyRecord: Identifiable {
    let id = UUID()
    let date: Date
    let level: Int
}
