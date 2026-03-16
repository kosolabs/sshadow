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
        logger = Logger(category: "\(manager.name):Enumerator")
        logger.debug("Init \(itemIdentifier.desc)")
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
        yield: @Sendable ([any NSFileProviderItemProtocol]) -> Void
    ) async throws -> NSFileProviderPage? {
        logger.info("Enumerating \(itemIdentifier.desc)")

        if itemIdentifier == .workingSet {
            return nil
        }

        if itemIdentifier == .trashContainer {
            if await !session.exists(for: .trashContainer) {
                return nil
            }
        }

        try await session.withDirectory(for: itemIdentifier) { dir in
            for try await attrs in dir {
                if let name = attrs.name {
                    let childId = await session.itemManager.id(for: itemIdentifier, name: name)
                    let item = await Item(
                        domainName: session.name,
                        itemIdentifier: childId,
                        itemAttributes: attrs,
                        itemManager: session.itemManager
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