import Common
import FileProvider
import Testing
import UniformTypeIdentifiers

@testable import ExtensionKit

private func template(
    _ contentType: UTType,
    symlinkTargetPath: String? = nil
) -> ItemTemplate {
    ItemTemplate(
        filename: "item",
        contentType: contentType,
        symlinkTargetPath: symlinkTargetPath
    )
}

struct TemplateKindTests {
    @Test func symlinkWithTargetIsSymlink() throws {
        let kind = TemplateKind(
            template(.symbolicLink, symlinkTargetPath: "target.txt")
        )
        #expect(kind == .symlink(target: "target.txt"))
    }

    @Test func symlinkWithoutTargetIsUnknown() {
        let kind = TemplateKind(
            template(.symbolicLink, symlinkTargetPath: nil)
        )
        #expect(kind == .unknown)
    }

    @Test(arguments: [
        UTType.folder,
        UTType("com.apple.framework"),
        UTType("com.apple.bundle"),
    ])
    func directoriesThatAreNotPackagesAreFolders(type: UTType?) throws {
        let type = try #require(type)
        #expect(TemplateKind(template(type)) == .folder)
    }

    @Test(arguments: [
        UTType.package,
        UTType("com.apple.xcode.dsym"),
        UTType("com.apple.application-bundle"),
        UTType("com.apple.rtfd"),
    ])
    func packagesAreExcluded(type: UTType?) throws {
        let type = try #require(type)
        #expect(TemplateKind(template(type)) == .package)
    }

    @Test(arguments: [
        UTType.plainText,
        UTType.png,
        UTType.aliasFile,
        UTType(filenameExtension: "xyzzy"),
    ])
    func dataIsFile(type: UTType?) throws {
        let type = try #require(type)
        #expect(TemplateKind(template(type)) == .file)
    }

    @Test(arguments: [
        UTType.mountPoint,
        UTType.item,
    ])
    func everythingElseIsExcluded(type: UTType?) throws {
        let type = try #require(type)
        #expect(TemplateKind(template(type)) == .unknown)
    }

    @Test func excludedFromSyncMapsToFileProviderExcludedFromSync() {
        let nsError = CoreError.excludedFromSync.asNSError as NSError
        #expect(nsError.domain == NSFileProviderErrorDomain)
        #expect(nsError.code == NSFileProviderError.excludedFromSync.rawValue)
    }
}
