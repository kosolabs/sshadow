import Common
import FileProvider
import SwiftData
import SwiftRussh

private let logger = Logger(category: "ConnectionConfigModel")

@Model
public class ConnectionConfigModel: CustomStringConvertible {
    public enum AuthMethod: Codable, CustomStringConvertible, Sendable {
        case password
        case privateKey

        public var description: String {
            switch self {
            case .password:
                return ".password"
            case .privateKey:
                return ".privateKey"
            }
        }
    }

    @Attribute(.unique) public var id: UUID
    public var name: String?
    public var enabled: Bool
    public var host: String
    public var port: UInt16?
    public var user: String?
    public var path: String?
    public var authMethod: AuthMethod
    public var bookmark: Data?
    public var ignoreFilenames: [String]?
    public var hostKey: String?

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        enabled: Bool = false,
        host: String = "",
        port: UInt16? = nil,
        user: String? = nil,
        path: String? = nil,
        authMethod: AuthMethod = .password,
        bookmark: Data? = nil,
        ignoreFilenames: [String]? = nil,
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.authMethod = authMethod
        self.bookmark = bookmark
        self.ignoreFilenames = ignoreFilenames
    }

    // MARK: - Effective Values

    public var socket: String {
        var result = "\(host)"
        if let port = port, port != 22 {
            result += ":\(port)"
        }
        return result
    }

    public var url: String {
        var result = "\(effectiveUser)@\(socket)"
        if !effectivePath.isEmpty {
            result += ":\(effectivePath)"
        }
        return result
    }

    public var sshCommand: String {
        var result = "ssh"
        if effectivePort != 22 {
            result += " -p \(effectivePort)"
        }
        return result + " \(effectiveUser)@\(host)"
    }

    public var displayName: String {
        host.isEmpty ? "New Connection" : name ?? url
    }

    public var displayUrl: String {
        host.isEmpty ? "New Connection" : url
    }

    public var effectivePort: UInt16 {
        port ?? 22
    }

    public var effectiveUser: String {
        user ?? NSUserName()
    }

    public var effectivePath: String {
        let p = path ?? ""
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }

    public var effectiveIgnoreFilenames: [String] {
        ignoreFilenames ?? [".sshadowignore"]
    }

    public var description: String {
        "ConnectionProfile(id: \(id), name: \(name ?? "-"), enabled: \(enabled), url: \(url), authMethod: \(authMethod))"
    }

    public var domain: NSFileProviderDomain {
        NSFileProviderDomain(id: id, displayName: displayName)
    }

    // MARK: - Enable / Disable

    public func isEnabled() -> Bool {
        return enabled
    }

    public func setEnabled(_ enabled: Bool) {
        Task { await enabled ? enable() : disable() }
    }

    public func enable() async {
        do {
            try validate()
            if effectiveHostKey == nil {
                await Connections.shared.beginHostKeyCheck(id: id)
                do {
                    try await resolveHostKey()
                } catch {
                    await Connections.shared.failHostKeyCheck(id: id, error: error)
                    throw error
                }
            }
            do {
                let config = try ConnectionConfig(from: self)
                try await DomainRegistry.shared.connect(config: config)
            } catch {
                await Connections.shared.endHostKeyCheck(id: id)
                throw error
            }
            await Connections.shared.endHostKeyCheck(id: id)
            self.enabled = true
            save()
            logger.notice("Profile enabled: \(self)")
        } catch {
            logger.error("Failed to enable \(self): \(error)")
        }
    }

    public func reconnectOnLaunch() async {
        guard effectiveHostKey != nil else {
            await enable()
            return
        }
        do {
            let config = try ConnectionConfig(from: self)
            try await DomainRegistry.shared.reconnect(config: config)
        } catch {
            logger.error("Failed to reconnect \(self): \(error)")
        }
    }

    public func disable() async {
        await Connections.shared.endHostKeyCheck(id: id)
        await DomainRegistry.shared.disable(domain: domain)
        self.enabled = false
        save()
        logger.notice("Profile disabled: \(self)")
    }

    private func save() {
        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to save \(self): \(error)")
        }
    }

    public func pause() async {
        await DomainRegistry.shared.pause(domain: domain)
    }

    public func clearFailure() async {
        await Connections.shared.endHostKeyCheck(id: id)
        if enabled {
            await pause()
        } else {
            await DomainRegistry.shared.disable(domain: domain)
        }
    }

    public func poll() async {
        do {
            try await DomainRegistry.shared.poll(domain: domain)
        } catch {
            logger.error("Failed to poll \(self): \(error)")
        }
    }

    // MARK: - Password Management

    private var passwordKey: String {
        Keychain.shared.getPasswordKey(id: id)
    }

    public func getPassword() -> String? {
        Keychain.shared.get(passwordKey)
    }

    public func setPassword(_ password: String) {
        Keychain.shared.set(passwordKey, to: password)
    }

    public func deletePassword() {
        Keychain.shared.delete(passwordKey)
    }

    public func privateKeyUrl() throws -> URL {
        try resolveBookmark()
    }

    public func getPrivateKeyContents()
        throws(ConnectionConfig.ValidationError) -> String
    {
        guard
            let url = try? resolveBookmark(),
            url.startAccessingSecurityScopedResource()
        else {
            throw .privateKeyMissing
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard
            let base64PrivateKey = try? String(
                data: Data(contentsOf: url),
                encoding: .utf8
            )
        else {
            throw .privateKeyMissing
        }
        return base64PrivateKey
    }

    private func resolveBookmark() throws -> URL {
        guard let bookmark = bookmark else {
            throw ConnectionConfig.ValidationError.privateKeyMissing
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            guard url.startAccessingSecurityScopedResource() else {
                return url
            }
            defer { url.stopAccessingSecurityScopedResource() }
            self.bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return url
    }

    // MARK: - Host Key Management

    var effectiveHostKey: SSHHostKey? {
        trustedHostKey(for: socket)
    }

    public func trustHostKey(_ key: SSHHostKey) {
        trust(key, for: socket)
    }

    func resolveHostKey() async throws(ConnectionError) {
        let socket = socket
        do {
            let key = try await SSHClient.serverHostKey(
                host: host,
                port: effectivePort
            )
            trust(key, for: socket)
        } catch {
            eventLog.error(
                "Failed to connect to \(displayName)",
                detail: error.detail
            )
            throw error
        }
    }

    private func trust(_ key: SSHHostKey, for socket: String) {
        let replaced = trustedHostKey(for: socket)
        hostKey = "\(socket) \(key)"
        save()
        logger.notice("Trusted host key for \(socket): \(key.fingerprint)")
        var detail = "\(key.fingerprint) for \(socket)"
        if let replaced, replaced != key {
            detail += ", replacing \(replaced.fingerprint)"
        }
        eventLog.notice("Trusted host key for \(displayName)", detail: detail)
    }

    private func trustedHostKey(for socket: String) -> SSHHostKey? {
        guard let hostKey else { return nil }
        let fields = hostKey.split(separator: " ", maxSplits: 1)
        guard fields.count == 2, fields[0] == socket else { return nil }
        return SSHHostKey(String(fields[1]))
    }

    private var eventLog: Events<ContinuousClock>.Logger {
        Events.shared.logger(
            for: .connection,
            source: Event.Source(name: displayName, url: url)
        )
    }

    // MARK: - Ignore Files

    public var customizesIgnoreFiles: Bool {
        get { ignoreFilenames != nil }
        set { ignoreFilenames = newValue ? effectiveIgnoreFilenames : nil }
    }

    public func validate() throws(ConnectionConfig.ValidationError) {
        _ = try resolveConfigAuthMethod()
        try validateIgnoreFilenames()
    }

    fileprivate func validateIgnoreFilenames()
        throws(ConnectionConfig.ValidationError)
    {
        let invalid = effectiveIgnoreFilenames.contains {
            $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("/")
        }
        if invalid {
            throw .ignoreFilenameInvalid
        }
    }

    // MARK: - Private Key Passphrase Management

    private var privateKeyPassphraseKey: String {
        Keychain.shared.getPrivateKeyPassphraseKey(id: id)
    }

    public func getPrivateKeyPassphrase() -> String? {
        Keychain.shared.get(privateKeyPassphraseKey)
    }

    public func setPrivateKeyPassphrase(_ passphrase: String) {
        Keychain.shared.set(privateKeyPassphraseKey, to: passphrase)
    }

    public func deletePrivateKeyPassphrase() {
        Keychain.shared.delete(privateKeyPassphraseKey)
    }

    fileprivate func resolveConfigAuthMethod()
        throws(ConnectionConfig.ValidationError) -> ConnectionConfig.AuthMethod
    {
        switch authMethod {
        case .password:
            guard let password = getPassword(), !password.isEmpty else {
                throw .passwordMissing
            }
            return .password(password)
        case .privateKey:
            let contents = try getPrivateKeyContents()
            let passphrase = getPrivateKeyPassphrase()
            do {
                _ = try SSHPrivateKey(
                    contents: contents,
                    passphrase: passphrase
                )
            } catch {
                guard case .privateKey(let failure, _)? = error as? SSHError
                else {
                    throw .privateKeyInvalid
                }
                throw ConnectionConfig.ValidationError(failure)
            }
            return .privateKey(
                contents: contents,
                passphrase: passphrase
            )
        }
    }
}

extension ConnectionConfig.ValidationError {
    init(_ failure: SSHError.PrivateKeyFailure) {
        switch failure {
        case .unreadable:
            self = .privateKeyUnreadable
        case .passphraseRequired:
            self = .passphraseRequired
        case .invalid:
            self = .privateKeyInvalid
        }
    }
}

extension ModelContext {
    public func delete(
        connectionConfig config: ConnectionConfigModel
    ) async {
        await config.disable()
        config.deletePassword()
        config.deletePrivateKeyPassphrase()
        self.delete(config)
        logger.notice("Profile deleted: \(config)")
    }
}

extension ConnectionConfig {
    public init(from profile: ConnectionConfigModel) throws(ValidationError) {
        try self.init(from: profile, authMethod: profile.resolveConfigAuthMethod())
    }

    init(
        from profile: ConnectionConfigModel,
        authMethod: AuthMethod
    ) throws(ValidationError) {
        try profile.validateIgnoreFilenames()
        guard let hostKey = profile.effectiveHostKey else {
            throw .hostKeyUnknown
        }
        self.init(
            id: profile.id,
            name: profile.displayName,
            host: profile.host,
            port: profile.effectivePort,
            user: profile.effectiveUser,
            path: profile.effectivePath,
            authMethod: authMethod,
            ignoreFilenames: profile.effectiveIgnoreFilenames,
            hostKey: hostKey
        )
    }
}
