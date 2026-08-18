import Common
import CoreKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(category: "ConnectionConfigEditView")

struct ConnectionConfigEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Connections.self) private var connections

    var config = ConnectionConfigModel()
    @State private var isImportingKey: Bool = false
    @State private var passwordText: String = ""

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
            }
        )
    }

    private var path: Binding<String> {
        Binding<String>(
            get: { config.path ?? "" },
            set: { config.path = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: Validation

    private var isPasswordMissing: Bool {
        if case .password = config.authMethod {
            return passwordText.isEmpty
        }
        return false
    }

    private var isPrivateKeyMissing: Bool {
        if case .privateKey = config.authMethod {
            return (try? config.privateKeyUrl()) == nil
        }
        return false
    }

    private var isInvalid: Bool {
        isPasswordMissing || isPrivateKeyMissing
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
                        HStack {
                            Text("Enabled")
                            if isInvalid {
                                Spacer()
                                HStack {
                                    Image(systemName: "lock.circle")
                                    if isPasswordMissing {
                                        Text("Password is required.")
                                    } else if isPrivateKeyMissing {
                                        Text("Private key is required.")
                                    }
                                }
                                .foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(
                        connections.isBusy(id: config.id)
                            || (!enabled.wrappedValue && isInvalid)
                    )
                    .accessibilityIdentifier("enabledToggle")
                    HStack {
                        Text("Status")
                        Spacer()
                        ConnectionStatusView(
                            status: connections.status(for: config.id)
                        )
                        if enabled.wrappedValue {
                            if connections.isOffline(id: config.id) {
                                Button("Reconnect") {
                                    Task { try await config.reconfigure() }
                                }
                            } else {
                                Button("Pause") {
                                    Task { try await config.pause() }
                                }
                            }
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
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                passwordText = config.getPassword() ?? ""
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
