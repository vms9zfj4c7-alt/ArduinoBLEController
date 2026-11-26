import SwiftUI

/// Vue racine organisant la navigation par onglets : Scanner, Manette et Assignation.
struct MainTabView: View {
    enum Tab: Hashable {
        case scan
        case controller
        case mapping
    }

    @ObservedObject var scanViewModel: ScanViewModel
    @ObservedObject var controllerViewModel: ControllerViewModel
    @ObservedObject var mappingViewModel: MappingViewModel

    @State private var selectedTab: Tab = .scan

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView(viewModel: scanViewModel)
                .tabItem {
                    Label("Radar", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(Tab.scan)

            ControllerView(
                viewModel: controllerViewModel,
                telemetryStore: controllerViewModel.telemetryStore,
                onOpenScan: {
                    withAnimation(AppleMotion.fluidSpring) {
                        selectedTab = .scan
                    }
                },
                onOpenMapping: {
                    withAnimation(AppleMotion.fluidSpring) {
                        selectedTab = .mapping
                    }
                }
            )
            .tabItem {
                Label("Manette", systemImage: "gamecontroller.fill")
            }
            .tag(Tab.controller)

            MappingView(viewModel: mappingViewModel)
                .tabItem {
                    Label("Assigner", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.mapping)
        }
        .onChange(of: controllerViewModel.connectionState.isConnected) { isConnected in
            if isConnected {
                AppHaptics.success()
                if selectedTab == .scan {
                    withAnimation(AppleMotion.fluidSpring) {
                        selectedTab = .controller
                    }
                }
            }
        }
        .onChange(of: selectedTab) { _ in
            AppHaptics.selection()
        }
    }
}
