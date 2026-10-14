import AppKit
import Common
import CoreKit
import SwiftData

private let logger = Logger(category: "TestCommands")

final class TestCommands {
    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let enabled = ProcessInfo.processInfo.arguments.contains(
        "-enableTestCommands"
    )

    static let notification = Notification.Name("com.kosolabs.SSHadow.command")

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.notification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let object = notification.object
            Task { @MainActor in
                do {
                    try await self.handle(Self.params(from: object))
                } catch {
                    logger.error(
                        "Failed to handle \(String(describing: object)): \(error.localizedDescription)"
                    )
                }
            }
        }
        logger.notice("Test commands enabled")
    }

    private static func params(from object: Any?) throws -> [String: String] {
        guard let string = object as? String,
            let params = try? JSONDecoder().decode(
                [String: String].self,
                from: Data(string.utf8)
            )
        else {
            throw Error(message: "invalid command")
        }
        return params
    }

    private func handle(_ params: [String: String]) async throws {
        logger.notice("Handle \(params)")
        let command = try params.required("command")
        switch command {
        case "enable":
            try await enable(name: params.required("name"))
        case "disable":
            try await disable(name: params.required("name"))
        case "poll":
            try await poll(name: params.required("name"))
        case "create":
            try await create(
                name: params.required("name"),
                host: params.required("host"),
                port: params.optional("port").map({
                    guard let port = UInt16($0) else {
                        throw Error(message: "invalid port: \"\($0)\"")
                    }
                    return port
                }),
                user: params.optional("user"),
                path: params.optional("path"),
                key: params.required("key")
            )
        case "delete":
            try await delete(name: params.required("name"))
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

extension [String: String] {
    fileprivate func required(_ name: String) throws -> String {
        guard let value = optional(name) else {
            throw TestCommands.Error(message: "missing parameter: \"\(name)\"")
        }
        return value
    }

    fileprivate func optional(_ name: String) -> String? {
        guard let value = self[name], !value.isEmpty else { return nil }
        return value
    }
}
