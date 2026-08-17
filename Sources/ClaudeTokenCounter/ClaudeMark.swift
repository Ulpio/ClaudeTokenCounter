import AppKit
import SwiftUI

/// A marca radial do Claude, desenhada em vetor.
///
/// Vetor em vez de asset: escala nítido em qualquer tamanho de menu bar e não
/// carrega binário no bundle. SF Symbols não serve — `asterisk` tem seis raios
/// retos e lê como pontuação, não como logo.
struct ClaudeMark: Shape {
    var rays: Int = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let thickness = radius * 0.24

        for index in 0..<rays {
            // Comprimentos levemente irregulares: a marca não é um asterisco
            // perfeito, e é essa variação que a faz parecer desenhada.
            let length = radius * (index.isMultiple(of: 3) ? 0.80 : 1.0)
            let ray = CGRect(x: -thickness / 2, y: -length,
                             width: thickness, height: length)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: Double(index) / Double(rays) * 2 * .pi)
            path.addPath(Path(roundedRect: ray, cornerRadius: thickness / 2),
                         transform: transform)
        }
        return path
    }
}

extension ClaudeMark {
    /// O label do `MenuBarExtra` só renderiza `Text` e `Image` — uma `Shape`
    /// desenhada direto no `HStack` é silenciosamente descartada. Rasterizar
    /// uma única vez no launch resolve, e `isTemplate` deixa o sistema tintar
    /// conforme claro/escuro.
    @MainActor
    static let menuBarImage: NSImage = {
        let side: CGFloat = 15
        let renderer = ImageRenderer(
            content: ClaudeMark()
                .frame(width: side, height: side)
                .foregroundStyle(.black))
        renderer.scale = 3
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
        image.isTemplate = true
        return image
    }()
}
