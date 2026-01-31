import SwiftUI
import UniformTypeIdentifiers

struct ConnectionConfigEditView: View {
    @Environment(\.modelContext) private var modelContext

    var config = ConnectionConfig()
    @State private var tester = ConnectionTestViewModel()
    @State private var isImportingKey = false

    private var name: Binding<String> {
        Binding<String>(
            get: { config.name ?? "" },
            set: { config.name = $0.isEmpty ? nil : $0 }
        )
    }

    private var enabled: Binding<Bool> {
        Binding<Bool>(
            get: { config.isEnabled() },
            set: { shouldEnable in
                if shouldEnable {
                    tester.test(config)
                } else {
                    config.disable()
                }
            }
        )
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
            get: { config.authMethod == .privateKey },
            set: { config.authMethod = $0 ? .privateKey : .password }
        )
    }

    private var password: Binding<String> {
        Binding<String>(
            get: { config.getPassword() ?? "" },
            set: {
                if $0.isEmpty {
                    config.deletePassword()
                } else {
                    config.setPassword($0)
                }
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

    var body: some View {
        VStack {
            Form {
                Section {
                    TextField(
                        "Display Name",
                        text: name,
                        prompt: Text(config.effectiveName),
                    )
                    .accessibilityIdentifier("nameField")
                    HStack {
                        Toggle(isOn: enabled) {
                            HStack {
                                Text("Enabled")
                                Spacer()
                                ConnectionTestStatusView(status: tester.status)
                            }
                        }
                        .accessibilityIdentifier("enabledToggle")
                    }
                }
                Section("Connection") {
                    TextField(
                        "Hostname",
                        text: host,
                        prompt: Text("example.com")
                    )
                    .accessibilityIdentifier("hostField")
                    TextField(
                        "Port",
                        text: port,
                        prompt: Text("\(config.effectivePort) (default)")
                    )
                    .accessibilityIdentifier("portField")
                    TextField(
                        "Remote Path",
                        text: path,
                        prompt: Text(config.effectivePath)
                    )
                    .accessibilityIdentifier("pathField")
                }
                Section("Authentication") {
                    TextField(
                        "Username",
                        text: user,
                        prompt: Text(config.effectiveUser)
                    )
                    .accessibilityIdentifier("userField")
                    Toggle("Use Private Key", isOn: usePrivateKey)
                    if usePrivateKey.wrappedValue {
                        LabeledContent("Private Key") {
                            if let url = config.privateKeyURL() {
                                Text(url.tildePath)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Button(role: .destructive) {
                                    config.privateKeyBookmark = nil
                                } label: {
                                    Label(
                                        "Clear",
                                        systemImage: "xmark.circle.fill"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Clear private key selection")
                            } else {
                                Button(
                                    "Select Private Key…",
                                    systemImage: "key"
                                ) {
                                    isImportingKey = true
                                }
                                .buttonStyle(.link)
                            }
                        }
                        SecureField(
                            "Passphrase",
                            text: privateKeyPassphrase,
                            prompt: Text("(optional)")
                        )
                    } else {
                        SecureField("Password", text: password)
                            .accessibilityIdentifier("passwordField")
                    }
                }
            }
            .formStyle(.grouped)
            .fileImporter(
                isPresented: $isImportingKey,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: handlePrivateKeyImport
            )
            .onChange(of: tester.status) {
                switch tester.status {
                case .success:
                    config.enable()
                default:
                    break
                }
            }
            .onChange(of: config) {
                tester.clear()
            }
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
                config.privateKeyBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                print(
                    "Failed to create bookmark data for URL \(url): \(error)"
                )
            }
        case .failure(let error):
            print(
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

#Preview {
    ConnectionConfigEditView()
}
