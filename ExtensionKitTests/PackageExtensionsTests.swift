import Foundation
import Testing

@testable import ExtensionKit

struct PackageExtensionsTests {
    static let systemConfig = URL(
        filePath: "/System/Library/Frameworks/FileProvider.framework/"
            + "Resources/default_factors_COREOS_FPFS_CONFIG_fbs.bin"
    )

    /// Reads `userExtensionPackageAllowlist` from the system's File Provider
    /// config. The file is an undocumented binary format, so rather than
    /// decode it, find the one printable ASCII run that is a long
    /// `;`-separated list.
    static func systemPackageExtensions() throws -> Set<String> {
        let data = try Data(contentsOf: systemConfig)

        var runs = [String]()
        var run = [UInt8]()
        for byte in data {
            if (0x20...0x7e).contains(byte) {
                run.append(byte)
            } else {
                if !run.isEmpty {
                    runs.append(String(decoding: run, as: UTF8.self))
                }
                run.removeAll()
            }
        }
        if !run.isEmpty {
            runs.append(String(decoding: run, as: UTF8.self))
        }

        let lists = runs.filter { $0.count(where: { $0 == ";" }) > 100 }
        try #require(
            lists.count == 1,
            "Expected one extension list in \(systemConfig.path)"
        )
        return Set(lists[0].split(separator: ";").map(String.init))
    }

    // Fails if Apple changes the list. Update `packageExtensions`
    // in PackageExtensions.swift
    @Test func matchesSystemAllowlist() throws {
        let system = try Self.systemPackageExtensions()
        let added = system.subtracting(packageExtensions).sorted()
        let removed = packageExtensions.subtracting(system).sorted()
        #expect(added.isEmpty, "Added to the system list: \(added)")
        #expect(removed.isEmpty, "Removed from the system list: \(removed)")
    }

    @Test func entriesAreLowercase() {
        #expect(packageExtensions.allSatisfy { $0 == $0.lowercased() })
    }
}
