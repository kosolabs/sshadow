import SwiftUI

struct DurationPicker: View {
    let title: String
    @Binding var seconds: Int?
    let defaultValue: Duration
    let choices: [Int]

    var body: some View {
        Picker(title, selection: $seconds) {
            ForEach(choices, id: \.self) { choice in
                let duration = Duration.seconds(choice)
                if duration == defaultValue {
                    Text("\(duration.spelledOut) (Default)").tag(Int?.none)
                } else {
                    Text(duration.spelledOut).tag(Int?.some(choice))
                }
            }
        }
    }
}

struct AppliesOnRestartNote: View {
    var body: some View {
        Label(
            "Changes apply the next time a connection starts. To apply them now, turn the connection off and on again in Connections.",
            systemImage: "info.circle"
        )
        .foregroundStyle(.secondary)
    }
}

extension Duration {
    var spelledOut: String {
        formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
