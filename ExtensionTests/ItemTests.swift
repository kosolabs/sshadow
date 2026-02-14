import Testing
import FileProvider
import UniformTypeIdentifiers
import SwiftLibSSH

@testable import Extension

struct ItemTests {

    // MARK: - Filename Tests
    
    @Test func filenameIsDerivedFromIdentifier() {
        let identifier = NSFileProviderItemIdentifier("folder/document.pdf")
        
        let item = Item(
            domainName: "test",
            itemIdentifier: identifier,
            itemAttributes: SFTPAttributes()
        )
        
        #expect(item.filename == "document.pdf")
    }
    
    // MARK: - Document Size Tests
    
    @Test func documentSizeIsMappedFromAttributes() {
        let attributes = SFTPAttributes(size: 2048)
        
        let item = Item(
            domainName: "test",
            itemIdentifier: NSFileProviderItemIdentifier("file"),
            itemAttributes: attributes
        )
        
        #expect(item.documentSize?.intValue == 2048)
    }
    
    // MARK: - Content Modification Date Tests
    
    @Test func contentModificationDateIsMappedFromAttributes() {
        // Use an integer timestamp to avoid floating point precision issues
        let timestamp: TimeInterval = 1600000000
        let date = Date(timeIntervalSince1970: timestamp)
        let attributes = SFTPAttributes(modifyTime: date)
        
        let item = Item(
            domainName: "test",
            itemIdentifier: NSFileProviderItemIdentifier("file"),
            itemAttributes: attributes
        )
        
        #expect(item.contentModificationDate == date)
    }
    
    // MARK: - Content Type Tests
    
    @Test func contentTypeIsFolderForDirectoryType() {
        let attributes = SFTPAttributes(type: .directory)
        
        let item = Item(
            domainName: "test",
            itemIdentifier: NSFileProviderItemIdentifier("folder"),
            itemAttributes: attributes
        )
        
        #expect(item.contentType == .folder)
    }
    
    @Test func contentTypeIsTextForFileType() {
        let attributes = SFTPAttributes(type: .regular)
        
        let item = Item(
            domainName: "test",
            itemIdentifier: NSFileProviderItemIdentifier("file.txt"),
            itemAttributes: attributes
        )
        
        #expect(item.contentType == .text)
    }
}
