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

    static let enabled = ProcessInfo.processInfo.arguments.contains(
        "-enableURLCommands"
    )

    override init() {
        super.init()
        if Self.enabled {
            logger.notice("URL commands enabled")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard Self.enabled else {
            logger.notice("URL commands disabled, ignoring: \(urls)")
            return
        }
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
        if url.isFileURL {
            logger.notice("Opened file: \(url.path(percentEncoded: false))")
            return
        }
        logger.notice("Handle \(url)")
        guard let command = url.host() else {
            throw Error(message: "command is nil")
        }
        switch command {
        case "enable":
            try await enable(name: url.query(for: "name"))
        case "disable":
            try await disable(name: url.query(for: "name"))
        case "poll":
            try await poll(name: url.query(for: "name"))
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

    private func poll(name: String) async throws {
        try await config(for: name).poll()
    }

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
            bookmark: try bookmark(forPrivateKeyAt: key)
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

    private func bookmark(forPrivateKeyAt path: String) throws -> Data {
        do {
            return try URL(filePath: path).bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw Error(
                message: "can't access private key \"\(path)\": "
                    + error.localizedDescription
            )
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
