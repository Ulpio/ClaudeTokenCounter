import Foundation

/// Converte o diretório cru de `~/.claude/projects` num rótulo curto de tela.
///
/// A mutilação que o Claude Code aplica troca `/` por `-` e é **irreversível**:
/// `-Users-me--claude-mem` tem hífen que veio de hífen, não de barra, e nada no
/// dado distingue os dois casos. Por isso o core guarda o nome cru e a
/// reconstrução acontece aqui, onde é corrigível sem migrar dado persistido.
///
/// Fica no core e não no alvo de UI porque é regra de derivação sobre string,
/// sem idioma — o que não pode descer para cá é a **frase**, que se traduz.
/// `GaugeGeometry` é o mesmo caso: apresentação testável fora da UI.
public enum ProjectLabel {
    /// Rótulo por diretório, encurtado o máximo que der sem gerar ambiguidade.
    ///
    /// Recebe a lista inteira de uma vez porque colisão só existe em conjunto:
    /// dois caminhos que terminam no mesmo segmento precisam crescer juntos, e
    /// isso é impossível de decidir olhando um por vez.
    public static func labels(for raws: [String]) -> [String: String] {
        // `raws` e um array puro, nada no tipo impede repeticao. Sem isso,
        // `Dictionary(uniqueKeysWithValues:)` daria fatalError numa entrada
        // repetida, e pior: contada duas vezes ela pareceria colisao com ela
        // mesma no laco abaixo, crescendo o rotulo sem necessidade. Dedupar
        // aqui resolve as duas coisas de uma vez.
        let uniqueRaws = Array(Set(raws))
        var depth = Dictionary(uniqueKeysWithValues: uniqueRaws.map { ($0, 1) })

        var changed = true
        while changed {
            changed = false
            var byLabel: [String: [String]] = [:]
            for raw in uniqueRaws {
                byLabel[label(raw, depth: depth[raw] ?? 1), default: []].append(raw)
            }
            for (_, colliding) in byLabel where colliding.count > 1 {
                for raw in colliding where (depth[raw] ?? 1) < segments(raw).count {
                    depth[raw] = (depth[raw] ?? 1) + 1
                    changed = true
                }
            }
        }

        var result = Dictionary(uniqueKeysWithValues:
            uniqueRaws.map { ($0, label($0, depth: depth[$0] ?? 1)) })

        // O laco para quando ninguem mais pode crescer, e isso inclui o caso em
        // que crescer nunca separou: `-Users-me--claude-mem` e
        // `-Users-me-claude-mem` viram a mesma lista de segmentos, porque o
        // ponto e a barra viraram o mesmo hifen. Sem esta saida o resultado
        // seria o rotulo mais longo possivel E ainda ambiguo — as duas coisas
        // que a regra existe para evitar. A chave crua e distinta por
        // construcao (e chave de dicionario), entao cair nela sempre separa.
        var byLabel: [String: [String]] = [:]
        for (raw, text) in result { byLabel[text, default: []].append(raw) }
        for (_, colliding) in byLabel where colliding.count > 1 {
            for raw in colliding { result[raw] = raw }
        }

        return result
    }

    /// `split` já descarta segmento vazio, que é o que resolve tanto o hífen
    /// inicial quanto o hífen duplicado.
    private static func segments(_ raw: String) -> [String] {
        raw.split(separator: "-").map(String.init)
    }

    private static func label(_ raw: String, depth: Int) -> String {
        let parts = segments(raw)
        guard !parts.isEmpty else { return raw }
        return parts.suffix(depth).joined(separator: "/")
    }
}
