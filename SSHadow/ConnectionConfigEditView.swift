import Common
import CoreKit
import SwiftData
import SwiftRussh
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(category: "ConnectionConfigEditView")

struct ConnectionConfigEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Connections.self) private var connections
    @Environment(\.openWindow) private var openWindow
    @Query private var storedSettings: [SettingsModel]

    var config = ConnectionConfigModel()
    @State private var isImportingKey: Bool = false
    @State private var passwordText: String = ""
    @State private var validationError: ConnectionConfig.ValidationError?
    @State private var changedHostKey: SSHHostKey?

    private var name: Binding<String> {
        Binding<String>(
            get: { config.name ?? "" },
            set: { config.name = $0.isEmpty ? nil : $0 }
        )
    }

    private var enabled: Binding<Bool> {
        Binding<Bool>(
            get: { config.isEnabled() },
            set: { config.setEnabled($0) }
        )
    }

    private var locked: Bool {
        config.enabled && !connections.isOffline(id: config.id)
    }

    private var host: Binding<String> {
        Binding<String>(
            get: { config.host },
            set: { config.host = $0 }
        )
    }

    private var port: Binding<String> {
        Binding<String>(
            get: { config.port.map(String.init) ?? "" },
            set: { config.port = $0.isEmpty ? nil : UInt16($0) }
        )
    }

    private var user: Binding<String> {
        Binding<String>(
            get: { config.user ?? "" },
            set: { config.user = $0.isEmpty ? nil : $0 }
        )
    }

    private var usePrivateKey: Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .privateKey = config.authMethod {
                    return true
                }
                return false
            },
            set: {
                config.authMethod = $0 ? .privateKey : .password
            }
        )
    }

    private var privateKeyPassphrase: Binding<String> {
        Binding<String>(
            get: { config.getPrivateKeyPassphrase() ?? "" },
            set: {
                if $0.isEmpty {
                    config.deletePrivateKeyPassphrase()
                } else {
                    config.setPrivateKeyPassphrase($0)
                }
                validate()
            }
        )
    }

    private var path: Binding<String> {
        Binding<String>(
            get: { config.path ?? "" },
            set: { config.path = $0.isEmpty ? nil : $0 }
        )
    }

    private var settings: SettingsModel {
        storedSettings.first ?? SettingsModel()
    }

    private var customizesIgnoreFiles: Binding<Bool> {
        Binding<Bool>(
            get: { config.customizesIgnoreFiles },
            set: { config.setCustomizesIgnoreFiles($0, settings: settings) }
        )
    }

    private var ignoreFilenames: Binding<[String]> {
        Binding<[String]>(
            get: { config.effectiveIgnoreFilenames(settings: settings) },
            set: { config.ignoreFilenames = $0 }
        )
    }

    private var status: ConnectionStatus {
        connections.status(for: config.id)
    }

    // MARK: Validation

    private func validate() {
        do {
            try config.validate(settings: settings)
            validationError = nil
        } catch {
            validationError = error
        }
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    TextField(
                        "Display Name",
                        text: name,
                        prompt: Text(config.displayName)
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("nameField")
                    Toggle(isOn: enabled) {
                        Text("Enabled")
                    }
                    .disabled(
                        connections.isBusy(id: config.id)
                            || (!enabled.wrappedValue && validationError != nil)
                    )
                    .accessibilityIdentifier("enabledToggle")
                    HStack {
                        Text("Status")
                        Spacer()
                        if let validationError {
                            Label(
                                validationError.message,
                                systemImage: "lock.circle"
                            )
                            .foregroundStyle(.red)
                        } else {
                            HStack(spacing: 6) {
                                ConnectionStatusIcon(
                                    status: status,
                                    variant: .checkmark
                                )
                                ConnectionStatusText(status: status)
                            }
                        }
                        switch status {
                        case .offline(let reason):
                            switch reason {
                            case .failed(.hostKeyChanged(let hostKey)):
                                Button("Trust New Key…") {
                                    changedHostKey = hostKey
                                }
                                Button("Clear") {
                                    Task { await config.clearFailure() }
                                }
                            case .failed:
                                Button("Clear") {
                                    Task { await config.clearFailure() }
                                }
                            case .xpcUnreachable(let otherExtension):
                                Button("How to Fix…") {
                                    openWindow.inFront(
                                        id: "unreachable",
                                        value: UnreachableFix(
                                            otherExtension: otherExtension,
                                            home: .userHome
                                        )
                                    )
                                }
                                Button("Clear") {
                                    Task { await config.clearFailure() }
                                }
                            case .disabled, .paused:
                                EmptyView()
                            }
                            if config.enabled {
                                Button("Reconnect") {
                                    Task { await config.enable() }
                                }
                                .disabled(validationError != nil)
                            }
                        case .connecting:
                            Button("Cancel") {
                                Task { await config.disable() }
                            }
                        case .reconnecting, .online:
                            Button("Pause") {
                                Task { await config.pause() }
                            }
                        case .disconnecting:
                            EmptyView()
                        }
                    }
                } footer: {
                    if locked {
                        HStack {
                            Spacer()
                            Image(systemName: "info.circle")
                            Text(
                                "Disable / pause this connection to edit its settings."
                            )
                        }
                    }
                }
                Section("Connection") {
                    TextField(
                        "Hostname",
                        text: host,
                        prompt: Text("example.com")
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("hostField")
                    TextField(
                        "Port",
                        text: port,
                        prompt: Text("22 (default)")
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("portField")
                    TextField(
                        "Remote Path",
                        text: path,
                        prompt: Text("~")
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("pathField")
                }
                Section("Authentication") {
                    TextField(
                        "Username",
                        text: user,
                        prompt: Text(NSUserName())
                    )
                    .disabled(locked)
                    .accessibilityIdentifier("userField")
                    Toggle("Use Private Key", isOn: usePrivateKey)
                        .disabled(locked)
                        .accessibilityIdentifier("usePrivateKeyToggle")
                    if usePrivateKey.wrappedValue {
                        LabeledContent("Private Key") {
                            if let url = try? config.privateKeyUrl() {
                                Text(url.tildePath)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Button(role: .destructive) {
                                    config.bookmark = nil
                                } label: {
                                    Label(
                                        "Clear",
                                        systemImage: "xmark.circle.fill"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Clear private key selection")
                                .disabled(locked)
                            } else {
                                Button(
                                    "Select Private Key…",
                                    systemImage: "key"
                                ) {
                                    isImportingKey = true
                                }
                                .buttonStyle(.link)
                                .disabled(locked)
                            }
                        }
                        SecureField(
                            "Passphrase",
                            text: privateKeyPassphrase,
                            prompt: Text("(optional)")
                        )
                        .disabled(locked)
                    } else {
                        SecureField(
                            "Password",
                            text: $passwordText,
                            prompt: Text("Required").foregroundColor(.red)
                        )
                        .disabled(locked)
                        .accessibilityIdentifier("passwordField")
                        .onChange(of: passwordText) { _, newValue in
                            if newValue.isEmpty {
                                config.deletePassword()
                            } else {
                                config.setPassword(newValue)
                            }
                            validate()
                        }
                    }
                }
                IgnoreFilesSection(
                    customizes: customizesIgnoreFiles,
                    filenames: ignoreFilenames,
                    inheritedNote: "These are the defaults from General settings.",
                    error: validationError == .ignoreFilenameInvalid
                        ? validationError : nil
                )
            }
            .formStyle(.grouped)
            .onAppear {
                passwordText = config.getPassword() ?? ""
                validate()
            }
            .onChange(of: config.authMethod) { validate() }
            .onChange(of: config.bookmark) { validate() }
            .onChange(of: config.ignoreFilenames) {
                validate()
                config.submitLiveSettings(settings: settings)
            }
            .alert(
                "Trust the New Host Key?",
                isPresented: Binding(
                    get: { changedHostKey != nil },
                    set: { if !$0 { changedHostKey = nil } }
                ),
                presenting: changedHostKey
            ) { hostKey in
                Button("Trust and Reconnect", role: .destructive) {
                    config.trustHostKey(hostKey)
                    Task { await config.enable() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { hostKey in
                Text(
                    "The server at \(config.socket) identified itself with a different key than before. This happens when the server is reinstalled or its keys are regenerated, but it can also mean someone is intercepting the connection. Only trust the new key if you expected this change.\n\nNew key fingerprint:\n\(hostKey.fingerprint)"
                )
            }
            .fileImporter(
                isPresented: $isImportingKey,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: handlePrivateKeyImport
            )
        }
        .padding()
    }

    private func handlePrivateKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                config.authMethod = .privateKey
                config.bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.error(
                    "Failed to create bookmark data for URL \(url): \(error)"
                )
            }
        case .failure(let error):
            logger.error(
                "Failed to import file: \(error.localizedDescription)"
            )
        }
    }
}

extension URL {
    fileprivate var tildePath: String {
        let home = "/Users/\(NSUserName())"
        let path = self.standardizedFileURL.path

        if path.hasPrefix(home) {
            return "~\(path.dropFirst(home.count))"
        } else {
            return path
        }
    }
}
