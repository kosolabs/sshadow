import CoreKit
import SwiftUI

struct RichMenuTransfer: View {
    let transfer: Transfer

    private var systemImage: String {
        switch transfer.progress.fileOperationKind {
        case .uploading: "arrow.up.circle"
        default: "arrow.down.circle"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            ProgressView(
                value: transfer.progress.fractionCompleted,
                label: {
                    Text(transfer.name)
                },
                currentValueLabel: {
                    Text(transfer.progress.localizedAdditionalDescription)
                        .font(.system(size: 10))
                }
            )
            .progressViewStyle(.linear)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
