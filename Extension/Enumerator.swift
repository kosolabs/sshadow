import Common
import FileProvider
import OSLog
import SwiftLibSSH

class Enumerator: NSObject, NSFileProviderEnumerator {
    private let logger: Logger
    private let config: ConnectionConfig
    private let itemIdentifier: NSFileProviderItemIdentifier
    private let anchor = NSFileProviderSyncAnchor(
        "an anchor".data(using: .utf8)!
    )

    init(
        config: ConnectionConfig,
        itemIdentifier: NSFileProviderItemIdentifier
    ) {
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: "Enumerator.\(config.name)"
        )
        logger.debug(
            "init: \(itemIdentifier.rawValue, privacy: .public)"
        )
        self.config = config
        self.itemIdentifier = itemIdentifier
        super.init()
    }

    func invalidate() {
        // TODO: perform invalidation of server connection if necessary
    }

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        /* TODO:
         - inspect the page to determine whether this is an initial or a follow-up request
        
         If this is an enumerator for a directory, the root container or all directories:
         - perform a server request to fetch directory contents
         If this is an enumerator for the active set:
         - perform a server request to update your local database
         - fetch the active set from your local database
        
         - inform the observer about the items returned by the server (possibly multiple times)
         - inform the observer that you are finished with this page
         */

        Task {
            do {
                let upTo = try await enumerateItems(startingAt: page) { items in
                    observer.didEnumerate(items)
                }
                observer.finishEnumerating(upTo: upTo)
            } catch {
                logger.error(
                    "error while enumerating items for \(self.config.name, privacy: .public): \(error, privacy: .public)"
                )
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateItems(
        startingAt page: NSFileProviderPage,
        yield: ([any NSFileProviderItemProtocol]) -> Void
    ) async throws -> NSFileProviderPage? {
        if itemIdentifier == .trashContainer {
            return nil
        }

        if itemIdentifier == .workingSet {
            return nil
        }

        try await SSHClient.withSession(config: config) { _, sftp in
            let path = itemIdentifier.fullPath(base: config.path)
            try await sftp.withDirectory(atPath: path) { dir in
                for try await attrs in dir {
                    if let name = attrs.name {
                        let item = Item(
                            domainName: config.name,
                            itemIdentifier: itemIdentifier.child(name: name),
                            itemAttributes: attrs
                        )
                        yield([item])
                    }
                }
            }
        }

        return nil
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        /* TODO:
         - query the server for updates since the passed-in sync anchor
        
         If this is an enumerator for the active set:
         - note the changes in your local database
        
         - inform the observer about item deletions and updates (modifications + insertions)
         - inform the observer when you have finished enumerating up to a subsequent sync anchor
         */
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        completionHandler(anchor)
    }
}
