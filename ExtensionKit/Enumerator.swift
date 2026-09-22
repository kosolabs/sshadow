import Common
import FileProvider

private let logger = Logger(category: "Enumerator")

public class Enumerator: NSObject, NSFileProviderEnumerator {
    private let client: CoreClient
    private let itemIdentifier: NSFileProviderItemIdentifier

    init(
        client: CoreClient,
        itemIdentifier: NSFileProviderItemIdentifier
    ) {
        self.client = client
        self.itemIdentifier = itemIdentifier

        super.init()

        observe()
    }

    public func invalidate() {
        unobserve()
    }

    private func observe() {
        Task {
            do {
                try await client.watch(itemId: itemIdentifier)
            } catch {
                logger.error("Failed to watch \(itemIdentifier): \(error)")
            }
        }
    }

    private func unobserve() {
        Task {
            do {
                try await client.unwatch(itemId: itemIdentifier)
            } catch {
                logger.error("Failed to unwatch \(itemIdentifier): \(error)")
            }
        }
    }

    public func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let trace = StackTrace.capture()

        Task {
            do throws(CoreError) {
                let upTo = try await enumerateItems(startingAt: page) { items in
                    observer.didEnumerate(items)
                }
                observer.finishEnumerating(upTo: upTo)
            } catch {
                trace.log(logger, error: error)
                observer.finishEnumeratingWithError(error.asNSError)
            }
        }
    }

    func enumerateItems(
        startingAt page: NSFileProviderPage,
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void,
    ) async throws(CoreError) -> NSFileProviderPage? {
        logger.info("Enumerate \(itemIdentifier)")

        if itemIdentifier == .workingSet {
            return nil
        }

        let entries = try await client.list(for: itemIdentifier)
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
        let trace = StackTrace.capture()

        Task {
            do throws(CoreError) {
                let nextAnchor = try await enumerateChanges(
                    from: anchor,
                    update: { item in
                        observer.didUpdate([item])
                    },
                    delete: { itemId in
                        observer.didDeleteItems(withIdentifiers: [itemId])
                    }
                )
                observer.finishEnumeratingChanges(
                    upTo: nextAnchor,
                    moreComing: false
                )
            } catch {
                trace.log(logger, error: error)
                observer.finishEnumeratingWithError(error.asNSError)
            }
        }
    }

    func enumerateChanges(
        from anchor: NSFileProviderSyncAnchor,
        update: @Sendable (any NSFileProviderItemProtocol) -> Void,
        delete: @Sendable (NSFileProviderItemIdentifier) -> Void
    ) async throws(CoreError) -> NSFileProviderSyncAnchor {
        logger.info("Enumerate changes for \(itemIdentifier)")

        let (nextAnchor, changes) = try await client.changes(
            since: anchor.value
        )

        for change in changes {
            switch change {
            case .delete(let itemId):
                delete(NSFileProviderItemIdentifier(itemId))
            case .update(let item):
                update(FPItem(item: item))
            }
        }

        return NSFileProviderSyncAnchor(nextAnchor)
    }

    public func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        logger.info("Current sync anchor for \(itemIdentifier)")

        let trace = StackTrace.capture()

        Task {
            do throws(CoreError) {
                let anchor = try await client.currentAnchor()
                completionHandler(NSFileProviderSyncAnchor(anchor))
            } catch {
                trace.log(logger, error: error)
                completionHandler(nil)
            }
        }
    }
}
