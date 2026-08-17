import AppKit
import SwiftUI
import CCUsageCore

/// O que fica sempre visível: ícone + % do bloco de 5h.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    private var tint: Color { UsageColor.menuBar(snapshot.session.fraction) }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: ClawdMark.menuBarImage)
                .renderingMode(.template)
            Text(Format.percent(snapshot.session.fraction))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
    }
}
