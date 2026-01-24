import SwiftUI

struct ConnectionConfigView: View {
    @State private var config = ConnectionConfig(host: "")
    @State private var tester = ConnectionTestViewModel()
    
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
                if newValue.isEmpty {
                    config.password = nil
                } else {
                    config.password = newValue
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
                    TextField("Host", text: $config.host)
                    TextField("Port", text: port, prompt: Text("\(config.effectivePort) (default)"))
                    TextField("User", text: user, prompt: Text(config.effectiveUser))
                    SecureField("Password", text: password)
                    HStack {
                        Button(tester.status == .testing ? "Testing..." : "Test Connection") {
                            tester.test(config)
                        }
                        .disabled(tester.status == .testing)
                        
                        Spacer()
                        switch tester.status {
                        case .notStarted:
                            Text("")
                        case .testing:
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                                .foregroundStyle(.secondary)
                        case .success:
                            Label("Success", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        case .invalidConfig(let message):
                            Label(message, systemImage: "xmark.octagon")
                                .foregroundStyle(.red)
                        case .other(let message):
                            Label(message, systemImage: "bolt.slash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

#Preview {
    ConnectionConfigView()
}
