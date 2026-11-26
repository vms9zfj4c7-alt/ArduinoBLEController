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
                    Label("Scanner", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(Tab.scan)

            ControllerView(
                viewModel: controllerViewModel,
                onOpenScan: { selectedTab = .scan },
                onOpenMapping: { selectedTab = .mapping }
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
            if isConnected && selectedTab == .scan {
                withAnimation {
                    selectedTab = .controller
                }
            }
        }
    }
}
