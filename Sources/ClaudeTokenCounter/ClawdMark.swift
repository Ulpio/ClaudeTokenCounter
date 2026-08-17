import AppKit
import SwiftUI

/// Clawd, o caranguejo do Claude Code, como pixel art vetorial.
///
/// O grid foi extraído do asset original (`clawd-magnifier.gif` no Claude.app,
/// célula de 43 px) e reencodado como células — assim escala nítido em qualquer
/// tamanho de menu bar, em vez de carregar um raster de resolução fixa.
///
/// Os olhos ficam **vazados** em vez de pretos: como imagem template o sistema
/// tinta a silhueta inteira de uma cor só, então o contraste tem que vir do
/// recorte, não de um segundo tom.
struct ClawdMark: Shape {
    private static let rows = [
        "..########..",
        "..#o####o#..",
        "############",
        "############",
        "..########..",
        "..########..",
        "..#.#..#.#..",
        "..#.#..#.#..",
    ]

    static let aspectRatio: CGFloat = CGFloat(rows[0].count) / CGFloat(rows.count)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = Self.rows[0].count
        let cell = min(rect.width / CGFloat(columns), rect.height / CGFloat(Self.rows.count))
        let originX = rect.midX - cell * CGFloat(columns) / 2
        let originY = rect.midY - cell * CGFloat(Self.rows.count) / 2

        // As células vizinhas se sobrepõem por um fio: sem isso o antialiasing
        // deixa costuras claras nas junções quando a célula não cai em pixel
        // inteiro.
        let bleed: CGFloat = 0.5

        for (row, line) in Self.rows.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                path.addRect(CGRect(x: originX + CGFloat(column) * cell,
                                    y: originY + CGFloat(row) * cell,
                                    width: cell + bleed,
                                    height: cell + bleed))
            }
        }
        return path
    }
}

extension ClawdMark {
    /// O label do `MenuBarExtra` só renderiza `Text` e `Image` — uma `Shape`
    /// desenhada direto no `HStack` é silenciosamente descartada. Rasterizar
    /// uma única vez no launch resolve, e `isTemplate` deixa o sistema tintar
    /// conforme claro/escuro.
    @MainActor
    static let menuBarImage: NSImage = {
        let height: CGFloat = 12
        let width = height * aspectRatio
        let renderer = ImageRenderer(
            content: ClawdMark()
                .frame(width: width, height: height)
                .foregroundStyle(.black))
        renderer.scale = 4
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = true
        return image
    }()
}
