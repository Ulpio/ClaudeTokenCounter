import Foundation
import Observation

/// Fachada observável: mantém os eventos em memória, reage a mudanças no disco
/// e publica um `UsageSnapshot`. É o único tipo que a UI conhece.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot
    public private(set) var isLoading = false

    /// Teto manual das settings; `nil` usa a calibração automática.
    public var ceilingOverride: Ceilings? {
        didSet { rebuild() }
    }

    private let scanner: ProjectScanner
    private let cacheURL: URL
    private let officialUsageURL: URL
    private let lookback: TimeInterval

    private var events: [UsageEvent] = []
    private var seenKeys = Set<String>()
    private var cache = ParseCache()
    private var watcher: FSWatcher?
    private var ticker: Task<Void, Never>?

    public init(
        scanner: ProjectScanner = ProjectScanner(),
        cacheURL: URL = ParseCache.defaultURL,
        officialUsageURL: URL = CachedUsageReader.defaultURL,
        lookback: TimeInterval = 90 * 24 * 60 * 60
    ) {
        self.scanner = scanner
        self.cacheURL = cacheURL
        self.officialUsageURL = officialUsageURL
        self.lookback = lookback
        self.snapshot = .empty(at: Date())
    }

    /// Lê o delta do disco, funde com o que já está em memória e reconstrói o snapshot.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let scanner = self.scanner
        let cache = self.cache
        let since = Date().addingTimeInterval(-lookback)

        let result: (events: [UsageEvent], cache: ParseCache)
        do {
            result = try await Task.detached(priority: .utility) {
                try scanner.ingest(since: since, cache: cache)
            }.value
        } catch {
            // Disco indisponível ou permissão negada: mantém o último snapshot bom.
            return
        }

        self.cache = result.cache
        for event in result.events where seenKeys.insert(event.dedupeKey).inserted {
            events.append(event)
        }

        // Descarta o que já saiu da janela de interesse, senão o arquivo de
        // cache cresce sem limite.
        let horizon = Date().addingTimeInterval(-lookback)
        if events.contains(where: { $0.timestamp < horizon }) {
            events.removeAll { $0.timestamp < horizon }
            seenKeys = Set(events.map(\.dedupeKey))
        }

        self.cache.events = events
        try? self.cache.save(to: cacheURL)
        rebuild()
    }

    public func start() {
        cache = ParseCache.load(from: cacheURL)
        // Restaura o histórico antes de tocar no disco: o painel abre com dados
        // completos em vez de esperar os segundos da varredura.
        events = cache.events
        seenKeys = Set(events.map(\.dedupeKey))
        rebuild()

        Task { await refresh() }

        watcher = FSWatcher(url: scanner.root) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        watcher?.start()

        // O bloco de 5h continua correndo mesmo sem escrita nova no disco:
        // o tempo até o reset precisa avançar sozinho.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run { self?.rebuild() }
            }
        }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        ticker?.cancel()
        ticker = nil
    }

    private func rebuild() {
        // Relido a cada reconstrução: o arquivo é pequeno e o cache oficial se
        // move sozinho enquanto o Claude Code roda.
        let cached = CachedUsageReader.read(from: officialUsageURL)
        let (official, status) = UsageSourcePolicy.select(
            liveEnabled: false, live: nil, cached: cached, now: Date())
        snapshot = SnapshotBuilder.build(
            from: events, now: Date(), calendar: .current,
            override: ceilingOverride, official: official, status: status)
    }
}
