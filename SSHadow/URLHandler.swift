import AppKit
import Common
import CoreKit
import SwiftData

private let logger = Logger(category: "URLHandler")

final class URLHandler: NSObject, NSApplicationDelegate {
    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task {
                do {
                    try await handle(url)
                } catch {
                    logger.error(
                        "Failed to handle \"\(url)\": \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func handle(_ url: URL) async throws {
        logger.info("Handle \(url)")
        if url.isFileURL {
            // Opening a file with the app grants the sandbox access to it,
            // which is all `create` needs for its private key.
            return
        }
        guard let command = url.host() else {
            throw Error(message: "command is nil")
        }
        switch command {
        case "enable":
            try await enable(name: url.query(for: "name"))
        case "disable":
            try await disable(name: url.query(for: "name"))
        case "create":
            try await create(
                name: url.query(for: "name"),
                host: url.query(for: "host"),
                port: url.optionalQuery(for: "port").map({
                    guard let port = UInt16($0) else {
                        throw Error(message: "invalid port: \"\($0)\"")
                    }
                    return port
                }),
                user: url.optionalQuery(for: "user"),
                path: url.optionalQuery(for: "path"),
                key: url.query(for: "key")
            )
        case "delete":
            try await delete(name: url.query(for: "name"))
        case "quit":
            NSApp.terminate(nil)
        default:
            throw Error(message: "unknown command: \"\(command)\"")
        }
    }

    private func enable(name: String) async throws {
        try await config(for: name).enable()
    }

    private func disable(name: String) async throws {
        try await config(for: name).disable()
    }

    /// Creates a private key profile, replacing any with the same name.
    ///
    /// The sandbox only lets the app read the key once it's been opened with
    /// the app, so pass it alongside the URL:
    ///
    ///     open -a SSHadow.app "sshadow://create?name=…&host=…&key=/path/to/key" /path/to/key
    private func create(
        name: String,
        host: String,
        port: UInt16?,
        user: String?,
        path: String?,
        key: String
    ) async throws {
        let config = ConnectionConfigModel(
            name: name,
            host: host,
            port: port,
            user: user,
            path: path,
            authMethod: .privateKey,
            bookmark: try await bookmark(forPrivateKeyAt: key)
        )

        let context = SSHadowApp.modelContainer.mainContext
        for existing in try configs(named: name) {
            await context.delete(connectionConfig: existing)
        }
        context.insert(config)
        try context.save()
        logger.notice("Profile created: \(config)")
    }

    private func delete(name: String) async throws {
        let context = SSHadowApp.modelContainer.mainContext
        await context.delete(connectionConfig: try config(for: name))
        try context.save()
    }

    /// The file URL that grants access arrives as a separate event, possibly
    /// after this one, so retry briefly. Being able to read the key isn't
    /// enough: some paths are readable before the grant, but a security-scoped
    /// bookmark still needs it.
    private func bookmark(forPrivateKeyAt path: String) async throws -> Data {
        let url = URL(filePath: path)
        let deadline = ContinuousClock.now + .seconds(5)
        while true {
            do {
                return try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                guard ContinuousClock.now < deadline else {
                    throw Error(
                        message: "can't access private key \"\(path)\": "
                            + error.localizedDescription
                    )
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func config(for name: String) throws -> ConnectionConfigModel {
        guard let config = try configs(named: name).first else {
            throw Error(message: "missing config named: \"\(name)\"")
        }
        return config
    }

    private func configs(named name: String) throws -> [ConnectionConfigModel] {
        try SSHadowApp.modelContainer.mainContext.fetch(
            FetchDescriptor<ConnectionConfigModel>(
                predicate: #Predicate { $0.name == name }
            )
        )
    }
}

extension URL {
    fileprivate func query(for name: String) throws -> String {
        guard let value = optionalQuery(for: name) else {
            throw URLHandler.Error(
                message: "missing query parameter: \"\(name)\""
            )
        }
        return value
    }

    fileprivate func optionalQuery(for name: String) -> String? {
        guard
            let value = URLComponents(
                url: self,
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == name })?.value,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
