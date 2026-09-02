import CoreKit
import Foundation
import SwiftUI

struct RichMenuTransfersSummary: View {
    let transfers: Transfers<ContinuousClock>

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            ProgressView(
                value: transfers.fractionCompleted,
                label: {
                    Text(title)
                },
                currentValueLabel: {
                    Text(subtitle)
                        .font(.system(size: 10))
                }
            )
            .progressViewStyle(.linear)
        }
    }

    private var systemImage: String {
        if transfers.isUploading && transfers.isDownloading {
            "arrow.up.arrow.down.circle"
        } else if transfers.isUploading {
            "arrow.up.circle"
        } else {
            "arrow.down.circle"
        }
    }

    private var title: String {
        let uploadCount = transfers.activeUploads.count
        let downloadCount = transfers.activeDownloads.count

        var parts: [String] = []
        if uploadCount > 0 {
            parts.append(
                "Uploading \(uploadCount) item\(uploadCount == 1 ? "" : "s")"
            )
        }
        if downloadCount > 0 {
            parts.append(
                "Downloading \(downloadCount) item\(downloadCount == 1 ? "" : "s")"
            )
        }
        return parts.joined(separator: ", ")
    }

    private var subtitle: String {
        var parts: [String] = []
        if transfers.isUploading {
            parts.append(
                progress(
                    label: "↑",
                    completed: transfers.completedUploadUnitCount,
                    total: transfers.totalUploadUnitCount,
                    throughput: transfers.uploadThroughput
                )
            )
        }
        if transfers.isDownloading {
            parts.append(
                progress(
                    label: "↓",
                    completed: transfers.completedDownloadUnitCount,
                    total: transfers.totalDownloadUnitCount,
                    throughput: transfers.downloadThroughput
                )
            )
        }
        return parts.joined(separator: "\n")
    }

    private func progress(
        label: String,
        completed: Int64,
        total: Int64,
        throughput: Int
    ) -> String {
        let completed = ByteCountFormatter.string(
            fromByteCount: completed,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: total,
            countStyle: .file
        )
        var result = "\(label) \(completed) of \(total)"
        if throughput > 0 {
            let rate = ByteCountFormatter.string(
                fromByteCount: Int64(throughput),
                countStyle: .file
            )
            result += " — \(rate)/s"
        }
        return result
    }
}
