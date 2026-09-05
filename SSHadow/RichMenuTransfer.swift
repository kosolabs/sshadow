import Common
import CoreKit
import SwiftUI

struct RichMenuTransfer: View {
    let transfer: Transfer

    private var isSuccess: Bool {
        transfer.progress.isFinished
    }

    private var isFailed: Bool {
        transfer.progress.isCancelled
    }

    private var systemImage: String {
        if isSuccess {
            return "checkmark.circle.fill"
        }
        if isFailed {
            return "xmark.circle.fill"
        }
        switch transfer.progress.fileOperationKind {
        case .uploading: return "arrow.up.circle"
        default: return "arrow.down.circle"
        }
    }

    private var statusColor: AnyShapeStyle {
        if isSuccess { return AnyShapeStyle(.green) }
        if isFailed { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(statusColor)
                .frame(width: 20, alignment: .center)

            ProgressView(
                value: transfer.progress.fractionCompleted,
                label: {
                    Text(transfer.name)
                },
                currentValueLabel: {
                    Text(transfer.progress.report)
                        .font(.caption)
                }
            )
            .progressViewStyle(.linear)
        }
    }
}
