import Common
import FileProvider
import SwiftLibSSH

public class Enumerator: NSObject, NSFileProviderEnumerator {
    private let logger: Logger
    private let manager: SessionManager
    private let itemIdentifier: NSFileProviderItemIdentifier
    private let anchor = NSFileProviderSyncAnchor(
        "an anchor".data(using: .utf8)!
    )

    init(
        manager: SessionManager,
        itemIdentifier: NSFileProviderItemIdentifier
    ) {
        logger = Logger(category: "Enumerator.\(manager.name)")
        logger.debug(
            "init: \(itemIdentifier.rawValue)"
        )
        self.manager = manager
        self.itemIdentifier = itemIdentifier
        super.init()
    }

    public func invalidate() {
        // TODO: perform invalidation of server connection if necessary
    }

    public func enumerateItems(
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
                let session = try await manager.getSession()
                let upTo = try await enumerateItems(
                    startingAt: page,
                    session: session
                ) { items in
                    observer.didEnumerate(items)
                }
                observer.finishEnumerating(upTo: upTo)
            } catch {
                logger.error(
                    "Failed to enumerate items for \(itemIdentifier): \(error)"
                )
                observer.finishEnumeratingWithError(remap(error: error))
            }
        }
    }

    private func enumerateItems(
        startingAt page: NSFileProviderPage,
        session: Session,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void,
    ) async throws -> NSFileProviderPage? {
        if itemIdentifier == .trashContainer {
            return nil
        }

        if itemIdentifier == .workingSet {
            return nil
        }

        let path = session.path(for: itemIdentifier)
        logger.debug("Enumerating items at: \(path)")
        try await session.sftp.withDirectory(atPath: path) { dir in
            for try await attrs in dir {
                if let name = attrs.name {
                    let item = Item(
                        domainName: session.name,
                        itemIdentifier: itemIdentifier.child(name: name),
                        itemAttributes: attrs
                    )
                    yield([item])
                }
            }
        }

        return nil
    }

    public func enumerateChanges(
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

    public func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        completionHandler(anchor)
    }
}

