import Common
import FileProvider

private let logger = Logger(category: "Enumerator")

public class Enumerator: NSObject, NSFileProviderEnumerator {
    private let agent: AgentClient
    private let itemIdentifier: NSFileProviderItemIdentifier

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
            yield([item])
        }

        return nil
    }

    public func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        logger.debug("Enumerating changes for \(itemIdentifier.desc)")
        let trace = StackTrace.capture()

        Task {
            do {
                let (nextAnchor, changes) = try await agent.changes(
                    since: anchor.value
                )

                var updates: [FPItem] = []
                var deletes: [NSFileProviderItemIdentifier] = []
                for change in changes {
                    switch change {
                    case .delete(let itemId):
                        deletes.append(NSFileProviderItemIdentifier(itemId))
                    case .update(let item):
                        updates.append(FPItem(item: item))
                    }
                }

                if !updates.isEmpty {
                    observer.didUpdate(updates)
                }
                if !deletes.isEmpty {
                    observer.didDeleteItems(withIdentifiers: deletes)
                }
                observer.finishEnumeratingChanges(
                    upTo: NSFileProviderSyncAnchor(nextAnchor),
                    moreComing: false
                )
            } catch {
                trace.log(logger, error: error)
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    public func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        logger.debug("Current sync anchor for \(itemIdentifier.desc)")
        let trace = StackTrace.capture()

        Task {
            do {
                let anchor = try await agent.currentAnchor()
                completionHandler(NSFileProviderSyncAnchor(anchor))
            } catch {
                trace.log(logger, error: error)
                completionHandler(nil)
            }
        }
    }
}
