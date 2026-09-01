import CoreKit
import Foundation
import SwiftUI

struct RichMenuTransfers: View {
    let transfers: Transfers<ContinuousClock>

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if let transfer = transfers.value.first,
                        transfers.value.count == 1
                    {
                        RichMenuTransfer(transfer: transfer)
                    } else {
                        RichMenuTransfersSummary(transfers: transfers)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, alignment: .center)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(
                        isHovered ? Color.primary : Color.clear
                    )
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(transfers.value) { transfer in
                            RichMenuTransfer(transfer: transfer)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .frame(height: 200)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
