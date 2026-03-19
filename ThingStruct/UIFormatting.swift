import Foundation

extension Int {
    var formattedTime: String {
        let hour = self / 60
        let minute = self % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

extension LocalDay {
    var titleText: String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else {
            return description
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
