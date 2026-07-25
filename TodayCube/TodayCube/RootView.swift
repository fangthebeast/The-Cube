import SwiftUI

struct RootView: View {
    enum Tab { case today, pip }

    @State private var tab: Tab = .today

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .today: TodayView()
                case .pip: PipView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.today, label: "Today") {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().frame(width: 4, height: 4))
            }
            tabButton(.pip, label: "Pip") {
                Image(systemName: "face.smiling")
                    .font(.system(size: 17, weight: .medium))
            }
        }
        .background(Theme.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func tabButton<Icon: View>(_ target: Tab, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 4) {
                icon()
                Text(label)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .foregroundStyle(tab == target ? Theme.accent : Theme.inkMuted)
        }
        .buttonStyle(.plain)
    }
}
