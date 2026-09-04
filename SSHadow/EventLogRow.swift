import Common
import CoreKit
import SwiftUI

struct EventLogRow: View {
    let event: Event

    private var systemImage: String {
        switch event.level {
        case .info: "info.circle"
        case .notice: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch event.level {
        case .info: .secondary
        case .notice: .blue
        case .warning: .yellow
        case .error: .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .lineLimit(2)

                HStack(alignment: .center, spacing: 8) {
                    Text(
                        event.timestamp.formatted(
                            date: .omitted,
                            time: .standard
                        )
                    )
                    .monospacedDigit()

                    Text(event.category.label)

                    if let detail = event.detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let source = event.source {
                    Text(source.name)
                    Text(source.url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
