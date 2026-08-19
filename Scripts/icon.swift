//
// Gera a arte do app: o .iconset e o fundo do DMG.
//
// Compilado junto com Sources/CCUsageCore/Presentation/GaugeGeometry.swift —
// veja Scripts/icon.sh. O anel daqui é literalmente o mesmo código do anel da
// barra de menu; sem isso, "identidade visual" viraria dois desenhos parecidos
// que alguém tem que lembrar de manter em sincronia.
//
// Uso: icongen <diretório de saída>

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paleta

enum Palette {
    /// O mesmo verde dessaturado do UsageColor.calm — a cor do estado normal.
    /// O ícone é o app parado, não o app alarmado.
    static let markTop = CGColor(red: 0.42, green: 0.70, blue: 0.52, alpha: 1)
    static let markBottom = CGColor(red: 0.20, green: 0.40, blue: 0.30, alpha: 1)
    static let ring = CGColor(gray: 1, alpha: 0.96)
    static let track = CGColor(gray: 1, alpha: 0.26)
    static let gloss = CGColor(gray: 1, alpha: 0.34)
    static let shadow = CGColor(gray: 0, alpha: 0.28)

    static let paper = CGColor(red: 0.976, green: 0.980, blue: 0.976, alpha: 1)
    static let paperEdge = CGColor(red: 0.918, green: 0.937, blue: 0.925, alpha: 1)
    static let ink = CGColor(gray: 0.13, alpha: 1)
    static let inkFaint = CGColor(gray: 0.45, alpha: 1)
}

/// Quanto do anel o ícone mostra.
///
/// 62%, e não um número redondo, porque `UsageColor.calmThreshold` é 0.66: este
/// é o arco mais cheio que ainda cabe no verde. Um ícone permanentemente âmbar
/// seria um alarme falso na pasta de aplicativos.
let iconFraction = 0.62

// MARK: - Contexto

/// Contexto y-para-baixo, para casar com a convenção do `GaugeGeometry` e com a
/// do Finder, que posiciona os ícones do DMG a partir do topo da janela.
func makeContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    return context
}

func writePNG(_ context: CGContext, to url: URL) {
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("falhou ao escrever \(url.path)")
    }
}

/// Desenha texto num contexto já invertido. O CoreText desenha de baixo para
/// cima, então a inversão precisa ser desfeita só em volta da linha.
func drawText(_ string: String, font: NSFont, color: CGColor,
              centeredAt point: CGPoint, in context: CGContext) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: string,
        attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!]))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    context.saveGState()
    context.translateBy(x: point.x - bounds.width / 2, y: point.y + bounds.height / 2)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
}

// MARK: - Formas

/// Superelipse — a família de curva do ícone do macOS, cujo canto é contínuo em
/// vez de um arco de círculo colado numa reta. Um `roundedRect` comum entrega a
/// silhueta errada e é o detalhe que faz um ícone parecer de fora.
func squircle(in rect: CGRect, exponent: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let samples = 720

    for step in 0...samples {
        let t = Double(step) / Double(samples) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = center.x + a * CGFloat(copysign(pow(abs(cosT), 2 / exponent), cosT))
        let y = center.y + b * CGFloat(copysign(pow(abs(sinT), 2 / exponent), sinT))
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func fill(_ path: CGPath, from top: CGColor, to bottom: CGColor,
          in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [top, bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [])
    context.restoreGState()
}

// MARK: - O ícone

func drawIcon(side: CGFloat, in context: CGContext) {
    // Abaixo de 64px o desenho engrossa em vez de encolher junto. A 16px, as
    // proporções do tamanho grande entregam um anel de 1,4px que o
    // antialiasing dissolve num borrão — e 16px é o tamanho dos Itens de Login
    // e dos diálogos do Gatekeeper, onde muita gente vê o app pela primeira
    // vez. Sombra e brilho também saem: a essa escala viram sujeira, não
    // volume.
    let compact = side < 64

    // A arte ocupa 82,4% da tela, a proporção histórica do ícone do macOS. O
    // resto é a folga que o sistema espera — e que impede que a máscara do
    // macOS 26 corte o canto do desenho. No compacto a folga cai, porque a
    // sombra que ela acomodava não é mais desenhada.
    let inset = side * (compact ? 0.045 : 0.088)
    let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = squircle(in: plate)

    if !compact {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.014),
                          blur: side * 0.028, color: Palette.shadow)
        context.addPath(shape)
        context.setFillColor(Palette.markBottom)
        context.fillPath()
        context.restoreGState()
    }

    fill(shape, from: Palette.markTop, to: Palette.markBottom, in: plate, context: context)

    // Brilho superior: a metade de cima da placa, esmaecendo para baixo. É o que
    // dá a leitura de vidro sem depender do material dinâmico do sistema, que
    // só o Icon Composer produz.
    if !compact {
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let glossRect = CGRect(x: plate.minX, y: plate.minY,
                           width: plate.width, height: plate.height * 0.58)
    let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [Palette.gloss, CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(gloss,
                               start: CGPoint(x: glossRect.midX, y: glossRect.minY),
                               end: CGPoint(x: glossRect.midX, y: glossRect.maxY),
                               options: [])
    context.restoreGState()

    // Fio de luz na borda de cima, o realce que separa a placa do fundo.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.addPath(shape)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
    context.setLineWidth(side * 0.006)
    context.strokePath()
    context.restoreGState()
    }

    // O anel, pelo mesmo GaugeGeometry que a barra de menu usa.
    let ringSide = plate.width * (compact ? 0.68 : 0.54)
    let ringRect = CGRect(x: plate.midX - ringSide / 2, y: plate.midY - ringSide / 2,
                          width: ringSide, height: ringSide)
    // No compacto o traço nunca fica abaixo de 2px: menos que isso e o anel
    // deixa de ler como anel.
    let lineWidth = max(compact ? 2 : 0, ringSide * (compact ? 0.24 : 0.155))

    context.setLineCap(.round)
    context.setLineWidth(lineWidth)

    context.addPath(GaugeGeometry.trackPath(in: ringRect, lineWidth: lineWidth))
    context.setStrokeColor(Palette.track)
    context.strokePath()

    context.addPath(GaugeGeometry.arcPath(in: ringRect, lineWidth: lineWidth,
                                          fraction: iconFraction))
    context.setStrokeColor(Palette.ring)
    context.strokePath()
}

// MARK: - O fundo do DMG

func drawInstallerBackground(size: CGSize, scale: CGFloat, in context: CGContext) {
    let rect = CGRect(origin: .zero, size: size)
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [Palette.paper, Palette.paperEdge] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: 0),
                               end: CGPoint(x: rect.midX, y: rect.height),
                               options: [])

    drawText("Claude Token Counter", font: .systemFont(ofSize: 22, weight: .semibold),
             color: Palette.ink, centeredAt: CGPoint(x: rect.midX, y: 56), in: context)
    drawText("Arraste para a pasta Aplicativos",
             font: .systemFont(ofSize: 13, weight: .regular),
             color: Palette.inkFaint, centeredAt: CGPoint(x: rect.midX, y: 84), in: context)

    // Um halo suave atrás de onde o Finder vai pôr o app: sem ele, o olho não
    // tem por onde começar numa janela que é quase toda branca.
    context.saveGState()
    let halo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [CGColor(red: 0.42, green: 0.70, blue: 0.52, alpha: 0.13),
                                   CGColor(red: 0.42, green: 0.70, blue: 0.52, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    let haloCenter = CGPoint(x: installerAppCenterX, y: installerIconCenterY)
    context.drawRadialGradient(halo, startCenter: haloCenter, startRadius: 0,
                               endCenter: haloCenter, endRadius: 132, options: [])
    context.restoreGState()

    // A seta liga as duas posições que o osascript fixa no Finder. Se aquelas
    // mudarem, esta precisa mudar junto — por isso as duas leem as constantes
    // abaixo.
    let y = installerIconCenterY
    let from = installerAppCenterX + 78
    let to = installerFolderCenterX - 78
    let arrow = CGColor(red: 0.42, green: 0.62, blue: 0.50, alpha: 0.85)

    context.setStrokeColor(arrow)
    context.setLineWidth(2.5)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: from, y: y))
    context.addLine(to: CGPoint(x: to - 9, y: y))
    context.strokePath()

    context.setFillColor(arrow)
    context.move(to: CGPoint(x: to, y: y))
    context.addLine(to: CGPoint(x: to - 14, y: y - 8))
    context.addLine(to: CGPoint(x: to - 14, y: y + 8))
    context.closePath()
    context.fillPath()

    // Rodapé com os dois requisitos que fazem o app simplesmente não abrir. É a
    // informação mais útil que cabe aqui, e o instalador é o último momento em
    // que alguém a lê antes de concluir que o app está quebrado.
    drawText("Requer macOS 26 ou mais recente  ·  Mac com Apple Silicon",
             font: .systemFont(ofSize: 11, weight: .regular),
             color: CGColor(gray: 0.58, alpha: 1),
             centeredAt: CGPoint(x: rect.midX, y: 352), in: context)

    context.restoreGState()
}

/// Compartilhadas com o Scripts/dmg.sh: a arte desenha a seta entre estes dois
/// pontos, e o Finder coloca os ícones neles.
let installerAppCenterX: CGFloat = 172
let installerFolderCenterX: CGFloat = 468
let installerIconCenterY: CGFloat = 214
let installerWindow = CGSize(width: 640, height: 396)

// MARK: - Saída

// `@main` em vez de código solto no topo: com dois arquivos de entrada, o
// swiftc só aceita instruções de topo num arquivo chamado main.swift.
@main
enum IconGen {
    static func main() throws {
        let outputRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1
                             ? CommandLine.arguments[1] : "dist")
        let iconset = outputRoot.appendingPathComponent("AppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        // Cada tamanho é renderizado no seu próprio tamanho, não reduzido do
        // maior: a 16px o traço fino some se vier de uma redução.
        for (pixels, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"),
                               (32, "icon_32x32"), (64, "icon_32x32@2x"),
                               (128, "icon_128x128"), (256, "icon_128x128@2x"),
                               (256, "icon_256x256"), (512, "icon_256x256@2x"),
                               (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
            let context = makeContext(width: pixels, height: pixels)
            drawIcon(side: CGFloat(pixels), in: context)
            writePNG(context, to: iconset.appendingPathComponent("\(name).png"))
        }

        for (scale, name) in [(CGFloat(1), "installer-background.png"),
                              (CGFloat(2), "installer-background@2x.png")] {
            let context = makeContext(width: Int(installerWindow.width * scale),
                                      height: Int(installerWindow.height * scale))
            drawInstallerBackground(size: installerWindow, scale: scale, in: context)
            writePNG(context, to: outputRoot.appendingPathComponent(name))
        }

        print("==> arte gerada em \(outputRoot.path)")
    }
}
