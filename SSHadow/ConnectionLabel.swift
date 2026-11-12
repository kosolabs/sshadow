import CoreKit
import SwiftUI

struct ConnectionLabel: View {
    let config: ConnectionConfigModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(subtitle).font(.caption)
        }
    }

    private var title: String {
        if let name = config.name { return name }
        return config.host.isEmpty ? "New Connection" : config.host
    }

    private var subtitle: String {
        config.host.isEmpty ? "No hostname" : config.url
    }
}
