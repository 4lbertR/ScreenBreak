import SwiftUI

/// The root tab bar navigation with four tabs: Dashboard, Apps, Stats, and Settings.
///
/// Uses a custom dark tab bar appearance with the app's teal accent color.
/// Designed as the primary container view after onboarding completes.
struct MainTabView: View {

    // MARK: - State

    @State private var selectedTab: Tab = .dashboard

    // MARK: - Tab Definition

    enum Tab: Int, CaseIterable, Identifiable {
        case dashboard
        case apps
        case stats
        case settings

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .apps:      return "Apps"
            case .stats:     return "Stats"
            case .settings:  return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .apps:      return "shield.fill"
            case .stats:     return "chart.bar.fill"
            case .settings:  return "gear"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .dashboard:
                    NavigationStack {
                        DashboardView()
                    }
                case .apps:
                    NavigationStack {
                        AppSelectionView()
                    }
                case .stats:
                    NavigationStack {
                        StatsView()
                    }
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            customTabBar
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background {
            // Glass-morphism background
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(alignment: .top) {
                    // Top border line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Tab Button

    private func tabButton(for tab: Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Selection indicator pill
                    if selectedTab == tab {
                        Capsule()
                            .fill(Color(hex: 0x00BFA6).opacity(0.15))
                            .frame(width: 56, height: 30)
                            .matchedGeometryEffect(id: "tab_indicator", in: tabNamespace)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            selectedTab == tab
                                ? Color(hex: 0x00BFA6)
                                : .white.opacity(0.4)
                        )
                        .frame(width: 56, height: 30)
                }

                Text(tab.title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color(hex: 0x00BFA6)
                            : .white.opacity(0.4)
                    )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Namespace

    @Namespace private var tabNamespace

    // MARK: - Appearance Configuration

    private func configureTabBarAppearance() {
        // Hide the default UIKit tab bar in case any system views inject one
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .preferredColorScheme(.dark)
}
