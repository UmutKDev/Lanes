import SwiftUI

/// Pages that are designed but not built yet say what they will hold.
struct PlannedPage: View {
    let destination: Destination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.symbol)
        } description: {
            Text(destination.plannedSummary)
        } actions: {
            Text("Alfa sürümünde geliyor.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
