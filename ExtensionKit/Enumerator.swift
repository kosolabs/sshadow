import Common
import FileProvider
import SwiftLibSSH

private let logger = Logger(category: "Enumerator")

public class Enumerator: NSObject, NSFileProviderEnumerator {
    private let agent: AgentClient
    private let manager: SessionManager
    private let itemIdentifier: NSFileProviderItemIdentifier
    private let anchor = NSFileProviderSyncAnchor(
        "an anchor".data(using: .utf8)!
    )

    init(
        agent: AgentClient,
        manager: SessionManager,
        itemIdentifier: NSFileProviderItemIdentifier
    ) {
        logger.debug("Init \(itemIdentifier.desc)")
        self.agent = agent
        self.manager = manager
        self.itemIdentifier = itemIdentifier
        super.init()
    }

    public func invalidate() {
        logger.debug("Invalidate \(itemIdentifier.desc)")
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
        let trace = StackTrace.capture()

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
                trace.log(logger, error: error)
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    private func enumerateItems(
        startingAt page: NSFileProviderPage,
        session: Session,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void,
    ) async throws -> NSFileProviderPage? {
        let itemRef = await session.id(of: itemIdentifier)
        logger.info("Enumerating \(itemRef)")

        if itemIdentifier == .workingSet {
            return nil
        }

        if itemIdentifier == .trashContainer {
            if try await agent.exists(for: .trashContainer) {
                return nil
            }
        }

        try await session.enumerateItems(for: itemIdentifier, yield: yield)

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
        logger.debug("Enumerating changes for \(itemIdentifier.desc)")
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    public func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        logger.debug("Current sync anchor for \(itemIdentifier.desc)")
        completionHandler(anchor)
    }
}
