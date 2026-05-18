import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var activeMode: VisualizerID = .aurora
    @Published var isOnboardingActive: Bool = false

    func cycleMode(reverse: Bool = false) {
        let modes = VisualizerID.allCases
        guard let idx = modes.firstIndex(of: activeMode) else { return }
        let next = (idx + (reverse ? -1 : 1) + modes.count) % modes.count
        activeMode = modes[next]
    }
}
