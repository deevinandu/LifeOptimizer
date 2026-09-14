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

            // Explicit warning of what happens if nothing is tapped --
            // the countdown alone doesn't communicate that a loud alarm
            // is about to fire, so this spells it out.
            Text("Buzzer will go off in:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(appState.countdown)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
                .animation(.default, value: appState.countdown)

            Spacer()

            // Big, high-contrast, thumb-friendly targets on purpose: whoever
            // is tapping these may be having a real neurological event right
            // now, with reduced fine motor control -- this is not a place
            // for compact, easy-to-miss buttons.
            VStack(spacing: 16) {
                Button {
                    appState.respond(.confirmedOkay)
                } label: {
                    Label("I'm Safe", systemImage: "checkmark.circle.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

                Button(role: .destructive) {
                    appState.respond(.needsHelp)
                } label: {
                    Label("HELP!", systemImage: "exclamationmark.triangle.fill")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .interactiveDismissDisabled()
    }
}
