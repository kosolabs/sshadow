import Common
import CoreKit
import SwiftUI

struct RichMenuTransfer: View {
    let transfer: Transfer

    private var isCompleted: Bool {
        transfer.progress.isFinished
    }

    private var systemImage: String {
        if isCompleted {
            return "checkmark.circle.fill"
        }
        switch transfer.progress.fileOperationKind {
        case .uploading: return "arrow.up.circle"
        default: return "arrow.down.circle"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(
                    isCompleted
                        ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
                )
                .frame(width: 20, alignment: .center)

            if isCompleted {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.name)
                    Text(transfer.progress.report)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView(
                    value: transfer.progress.fractionCompleted,
                    label: {
                        Text(transfer.name)
                    },
                    currentValueLabel: {
                        Text(transfer.progress.report)
                            .font(.system(size: 10))
                    }
                )
                .progressViewStyle(.linear)
            }
        }
    }
}
