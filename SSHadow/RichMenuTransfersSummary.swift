import CoreKit
import Foundation
import SwiftUI

struct RichMenuTransfersSummary: View {
    let transfers: Transfers<ContinuousClock>

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(statusColor)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var systemImage: String {
        if transfers.active.isEmpty {
            if transfers.cancelled.isEmpty {
                "checkmark.circle.fill"
            } else {
                "xmark.circle.fill"
            }
        } else {
            if transfers.isUploading && transfers.isDownloading {
                "arrow.up.arrow.down.circle"
            } else if transfers.isUploading {
                "arrow.up.circle"
            } else {
                "arrow.down.circle"
            }
        }
    }

    private var statusColor: AnyShapeStyle {
        if transfers.active.isEmpty {
            if transfers.cancelled.isEmpty {
                AnyShapeStyle(.green)
            } else {
                AnyShapeStyle(.red)
            }
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private var title: String {
        let uploadCount = transfers.activeUploads.count
        let downloadCount = transfers.activeDownloads.count

        if uploadCount == 0 && downloadCount == 0 {
            return "No active transfers"
        }

        var parts: [String] = []
        if uploadCount > 0 {
            parts.append(
                "Uploading \(uploadCount) \(format(items: uploadCount))"
            )
        }
        if downloadCount > 0 {
            parts.append(
                "Downloading \(downloadCount) \(format(items: downloadCount))"
            )
        }
        return parts.joined(separator: ", ")
    }

    private func format(items: Int) -> String {
        return "item\(items == 1 ? "" : "s")"
    }

    private var subtitle: String {
        let finishedCount = transfers.finished.count
        let cancelledCount = transfers.cancelled.count

        var parts: [String] = []
        if transfers.isUploading {
            let uploadThroughput = format(
                throughput: transfers.uploadThroughput
            )
            parts.append("↑ \(uploadThroughput)")
        }
        if transfers.isDownloading {
            let downloadThroughput = format(
                throughput: transfers.downloadThroughput
            )
            parts.append("↓ \(downloadThroughput)")
        }
        if finishedCount > 0 {
            parts.append("\(finishedCount) finished")
        }
        if cancelledCount > 0 {
            parts.append("\(cancelledCount) cancelled")
        }
        return parts.joined(separator: " — ")
    }

    private func format(throughput: Int) -> String {
        let rate = ByteCountFormatter.string(
            fromByteCount: Int64(throughput),
            countStyle: .file
        )
        return "\(rate)/s"
    }
}
