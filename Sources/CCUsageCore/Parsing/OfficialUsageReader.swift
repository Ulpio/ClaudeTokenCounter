import Foundation

/// Números oficiais de limite, como o Claude Code os cacheia.
public struct OfficialUsage: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        /// 0…1. O arquivo grava percentual inteiro; convertido na leitura para
        /// bater com o resto do app, que trabalha em fração.
        public let utilization: Double
        public let resetsAt: Date?

        public init(utilization: Double, resetsAt: Date?) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    /// Quando o Claude Code buscou estes números. O cache só se move quando ele
    /// roda, então a idade é parte do dado — não um detalhe de implementação.
    public let fetchedAt: Date
    public let fiveHour: Window?
    public let sevenDay: Window?

    public init(fetchedAt: Date, fiveHour: Window?, sevenDay: Window?) {
        self.fetchedAt = fetchedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }
}

/// Lê `cachedUsageUtilization` de `~/.claude.json`.
///
/// É o mesmo dado que o `/usage` mostra — percentual e horário de reset das
/// janelas de 5h e 7 dias, direto da Anthropic. Ler daqui dispensa derivar
/// janelas, calibrar teto e adivinhar fase: tudo isso existia só porque eu
/// procurei este estado dentro de `~/.claude/` e dos JSONL de sessão, e ele
/// mora na home, em `~/.claude.json`.
///
/// Campo interno e indocumentado: pode mudar de forma sem aviso. Por isso toda
/// falha de leitura devolve `nil` e o app cai no caminho derivado, em vez de
/// quebrar.
public enum OfficialUsageReader {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    }

    public static func read(from url: URL = defaultURL) -> OfficialUsage? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let fetchedAtMs = cache["fetchedAtMs"] as? Double,
              let windows = cache["utilization"] as? [String: Any]
        else { return nil }

        return OfficialUsage(
            fetchedAt: Date(timeIntervalSince1970: fetchedAtMs / 1000),
            fiveHour: window(windows["five_hour"]),
            sevenDay: window(windows["seven_day"]))
    }

    /// Muitas janelas vêm `null` (`seven_day_opus`, `tangelo`…). `null` é
    /// ausência, nunca zero.
    private static func window(_ raw: Any?) -> OfficialUsage.Window? {
        guard let dict = raw as? [String: Any],
              let percent = dict["utilization"] as? Double
        else { return nil }
        return OfficialUsage.Window(
            utilization: percent / 100,
            resetsAt: (dict["resets_at"] as? String).flatMap(parseTimestamp))
    }

    /// O arquivo grava microssegundos e offset explícito
    /// (`2026-08-18T02:20:00.007553+00:00`). O parser ISO do Swift aceita no
    /// máximo milissegundos, então a parte fracionária é descartada — precisão
    /// sub-segundo não significa nada para um horário de reset.
    static func parseTimestamp(_ raw: String) -> Date? {
        var cleaned = raw
        if let dot = raw.firstIndex(of: "."),
           let offsetStart = raw[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            cleaned = String(raw[..<dot]) + String(raw[offsetStart...])
        }
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? plain.parse(cleaned) { return date }
        return try? plain.parse(cleaned.replacingOccurrences(of: "+00:00", with: "Z"))
    }
}
