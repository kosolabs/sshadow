import FileProvider
import OSLog
import SSHadowShared
import SwiftLibSSH

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "FileProviderEnumerator"
)

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let config: ConnectionConfig
    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let anchor = NSFileProviderSyncAnchor(
        "an anchor".data(using: .utf8)!
    )

    init(
        config: ConnectionConfig,
        enumeratedItemIdentifier: NSFileProviderItemIdentifier
    ) {
        logger.debug("init: \(config, privacy: .public)")
        self.config = config
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
    }

    func invalidate() {
        logger.debug("invalidate")
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
                try await SSHClient.withAuthenticatedClient(config: config) {
                    ssh in
                    try await ssh.withSftp { sftp in
                        try await sftp.withDirectory(atPath: config.path) {
                            dir in
                            var items: [any NSFileProviderItemProtocol] = []
                            for try await attrs in dir {
                                items.append(
                                    FileProviderItem(
                                        identifier:
                                            NSFileProviderItemIdentifier(
                                                attrs.name ?? "nil"
                                            )
                                    )
                                )
                            }
                            observer.didEnumerate(items)
                        }
                    }
                }
                logger.debug(
                    "finished enumerating items for \(self.config, privacy: .public)"
                )
                observer.finishEnumerating(upTo: nil)
            } catch {
                logger.error(
                    "error while enumerating items for \(self.config, privacy: .public): \(error, privacy: .public)"
                )
                observer.finishEnumeratingWithError(error)
            }
        }
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
