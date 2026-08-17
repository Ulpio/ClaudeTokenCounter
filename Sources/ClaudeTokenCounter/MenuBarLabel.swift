import AppKit
import SwiftUI
import CCUsageCore

/// O que fica sempre visível: ícone + % do bloco de 5h.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

    private var tint: Color {
        guard let fraction = snapshot.activeBlock?.fraction else { return .secondary }
        switch fraction {
        case ..<0.6: return .secondary
        case ..<0.85: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: ClawdMark.menuBarImage)
                .renderingMode(.template)
            if let block = snapshot.activeBlock {
                Text(Format.percent(block.fraction))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(tint)
    }
}
