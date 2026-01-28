import SwiftUI

struct ConnectionConfigEditView: View {
    @Environment(\.modelContext) private var modelContext

    var config = ConnectionConfig(host: "")
    @State private var tester = ConnectionTestViewModel()

    private var host: Binding<String> {
        Binding<String>(
            get: { config.host },
            set: { newValue in
                config.host = newValue
            }
        )
    }

    private var port: Binding<String> {
        Binding<String>(
            get: {
                if let p = config.port {
                    return String(p)
                } else {
                    return ""
                }
            },
            set: { newValue in
                if newValue.isEmpty {
                    config.port = nil
                } else if let parsed = UInt16(newValue) {
                    config.port = parsed
                } else {
                    config.port = nil
                }
            }
        )
    }

    private var user: Binding<String> {
        Binding<String>(
            get: {
                return config.user ?? ""
            },
            set: { newValue in
                if newValue.isEmpty {
                    config.user = nil
                } else {
                    config.user = newValue
                }
            }
        )
    }

    private var password: Binding<String> {
        Binding<String>(
            get: {
                return config.password ?? ""
            },
            set: { newValue in
                config.password = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var path: Binding<String> {
        Binding<String>(
            get: {
                return config.path ?? ""
            },
            set: { newValue in
                if newValue.isEmpty {
                    config.path = nil
                } else {
                    config.path = newValue
                }
            }
        )
    }

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Connection Settings")
            }
            Form {
                Section("Connection") {
                    TextField("Host", text: host)
                    TextField(
                        "Port",
                        text: port,
                        prompt: Text("\(config.effectivePort) (default)")
                    )
                    TextField(
                        "User",
                        text: user,
                        prompt: Text(config.effectiveUser)
                    )
                    SecureField("Password", text: password)
                    TextField(
                        "Path",
                        text: path,
                        prompt: Text(config.effectivePath)
                    )
                    HStack {
                        Button(
                            tester.status == .testing
                                ? "Testing..." : "Test Connection"
                        ) {
                            tester.test(config)
                        }
                        .disabled(tester.status == .testing)

                        Spacer()

                        ConnectionTestStatusView(status: tester.status)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

#Preview {
    ConnectionConfigEditView()
}
