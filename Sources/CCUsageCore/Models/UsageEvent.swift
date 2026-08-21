import Foundation

/// Uma mensagem assistant com uso de token, extraída de uma linha do JSONL.
public struct UsageEvent: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let model: ModelID
    /// `message.usage.speed == "fast"` — fast mode custa o dobro no Opus 5.
    public let isFast: Bool
    public let input: UInt32
    public let output: UInt32
    public let cacheWrite5m: UInt32
    public let cacheWrite1h: UInt32
    public let cacheRead: UInt32
    /// `"\(message.id):\(requestId)"` — resume e fork reescrevem a mesma
    /// mensagem em arquivos diferentes; sem isso os tokens contam em dobro.
    public let dedupeKey: String
    /// Diretório do projeto sob `~/.claude/projects`, cru como está no disco:
    /// `-Users-me-Projects-Alpha`.
    ///
    /// Cru de propósito. A mutilação que o Claude Code aplica troca `/` por `-`
    /// e é irreversível — diretório com hífen no nome vira ambíguo. Desmutilar
    /// é palpite de apresentação, e apresentação não mora no core.
    ///
    /// Vazio em evento vindo de cache gravado antes deste campo existir.
    public let project: String

    public init(
        timestamp: Date, model: ModelID, isFast: Bool,
        input: UInt32, output: UInt32,
        cacheWrite5m: UInt32, cacheWrite1h: UInt32, cacheRead: UInt32,
        dedupeKey: String, project: String = ""
    ) {
        self.timestamp = timestamp
        self.model = model
        self.isFast = isFast
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.dedupeKey = dedupeKey
        self.project = project
    }

    public var totalTokens: UInt64 {
        UInt64(input) + UInt64(output)
            + UInt64(cacheWrite5m) + UInt64(cacheWrite1h) + UInt64(cacheRead)
    }
}

extension UsageEvent {
    // `decodeIfPresent` em vez do Codable sintetizado: o ParseCache guarda estes
    // eventos em JSON e devolve cache vazio quando algo não decodifica. Campo
    // obrigatório novo tornaria todo cache existente ilegível de uma vez, e o
    // descarte custa reparse de 90 dias mais os eventos cujos .jsonl de origem
    // já sumiram do disco — que o cache é o único lugar a guardar.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.model = try c.decode(ModelID.self, forKey: .model)
        self.isFast = try c.decode(Bool.self, forKey: .isFast)
        self.input = try c.decode(UInt32.self, forKey: .input)
        self.output = try c.decode(UInt32.self, forKey: .output)
        self.cacheWrite5m = try c.decode(UInt32.self, forKey: .cacheWrite5m)
        self.cacheWrite1h = try c.decode(UInt32.self, forKey: .cacheWrite1h)
        self.cacheRead = try c.decode(UInt32.self, forKey: .cacheRead)
        self.dedupeKey = try c.decode(String.self, forKey: .dedupeKey)
        self.project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
    }
}
