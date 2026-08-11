import SwiftUI

struct WindowListRow: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: window.isOnScreen ? "rectangle.on.rectangle" : "rectangle.dashed")
                .foregroundColor(isSelected ? .white : window.isOnScreen ? .secondary : .secondary.opacity(0.4))
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title.isEmpty ? window.appName : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : window.isOnScreen ? .primary : .secondary.opacity(0.5))
                    .lineLimit(1)

                if !window.title.isEmpty {
                    Text(window.appName)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(Int(window.frame.width))x\(Int(window.frame.height))")
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .white.opacity(0.6) : .secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}