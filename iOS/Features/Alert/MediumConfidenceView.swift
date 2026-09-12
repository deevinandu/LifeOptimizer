import SwiftUI

struct MediumConfidenceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("We noticed a significant change in your facial movement.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Are you feeling okay?")
                .font(.title3)

            Text("\(appState.countdown)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
                .animation(.default, value: appState.countdown)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    appState.respond(.confirmedOkay)
                } label: {
                    Text("Yes, I'm okay")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    appState.respond(.needsHelp)
                } label: {
                    Text("I need help")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
