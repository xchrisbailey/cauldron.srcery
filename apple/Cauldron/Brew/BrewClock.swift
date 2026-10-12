import Foundation

/// A time left, as a clock reads it.
enum BrewClock {
  /// "7:02", or "1:05:00" for an hour or more.
  static func text(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let rest = String(format: "%02d", total % 60)
    return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(rest)" : "\(minutes):\(rest)"
  }
}
