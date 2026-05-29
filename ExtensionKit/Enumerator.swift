import Common
import FileProvider

private let logger = Logger(category: "Enumerator")

public class Enumerator: NSObject, NSFileProviderEnumerator {
    private let agent: AgentClient
    private let itemIdentifier: NSFileProviderItemIdentifier
    private let anchor = NSFileProviderSyncAnchor(
        "an anchor".data(using: .utf8)!
    )

    init(
        agent: AgentClient,
        itemIdentifier: NSFileProviderItemIdentifier
    ) {
        logger.debug("Init \(itemIdentifier.desc)")
        self.agent = agent
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
                let upTo = try await enumerateItems(startingAt: page) { items in
                    observer.didEnumerate(items)
                }
                observer.finishEnumerating(upTo: upTo)
            } catch {
                trace.log(logger, error: error)
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateItems(
        startingAt page: NSFileProviderPage,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void,
    ) async throws -> NSFileProviderPage? {
        logger.debug("Enumerate \(itemIdentifier.desc)")

        if itemIdentifier == .workingSet {
            return nil
        }

        let entries = try await agent.list(for: itemIdentifier)
        for entry in entries {
            let item = FPItem(item: entry)
            if item.id == .sshadowContainer {
                continue
            }
            yield([item])
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
