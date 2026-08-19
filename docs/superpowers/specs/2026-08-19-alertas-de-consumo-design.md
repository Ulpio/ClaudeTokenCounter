# Alertas de consumo — Design

**Data:** 2026-08-19
**Status:** Aprovado para planejamento
**Contexto:** primeiro item do nível 1 do diagnóstico de produto (o app não avisa)

---

## 1. Objetivo

O app é hoje um medidor passivo: ele só ajuda quem lembra de abrir o painel. A
premissa dele — não ser pego de surpresa pelo teto — depende de o usuário olhar
na hora certa, que é justamente o que ninguém faz.

Entrega: **notificações do sistema ao cruzar limiares de consumo**, e um aviso
quando a janela reseta para quem tinha encostado no teto.

---

## 2. A restrição que define a forma

Notificar com base em número que o app sabe não ser confiável trairia a premissa
do projeto inteiro.

A busca ao vivo vem **desligada por padrão**, por decisão explícita de
privacidade (`AppSettings.liveUsageEnabled`). Nesse estado o app lê o cache do
Claude Code — o mesmo que na medição de 2026-08-18 estava 13h25 defasado,
dizendo 35% quando o valor real era 6%.

Um alerta sobre esse número erra nos dois sentidos:

| Defasagem | Consequência |
|---|---|
| Cache alto, real baixo | Alarme falso: interrompe por nada |
| Cache baixo, real alto | **Silêncio enquanto você estoura** — a falha que o app existe para impedir |

**Decisão: alerta só com procedência ao vivo.** Sem isso, nada dispara.

### 2.1 A confiança é por medidor, não por snapshot

`UsageSnapshot.sourceStatus` descreve o snapshot inteiro, mas a procedência é
guardada em cada `Gauge` — e elas divergem. O caso real: a semanal vem do
relatório oficial enquanto a sessão cai no derivado, porque o payload trouxe
`five_hour: null`. Um snapshot com `sourceStatus == .live` pode conter um
medidor derivado.

Então o teste de confiança é `if case .live = gauge.provenance`, **no medidor que
vai disparar**, nunca no status do snapshot. Checar o status seria emitir alerta
sobre número estimado sob a etiqueta de ao vivo.

---

## 3. Decisões tomadas

| # | Decisão | Por quê |
|---|---|---|
| 1 | Alerta só com `provenance == .live` | §2 |
| 2 | Uma notificação única explicando, se o usuário liga alertas com o ao vivo desligado | Silêncio é indistinguível de bug; e vira a cura da descoberta do ao vivo |
| 3 | Gatilho é cruzar porcentagem, não projeção por ritmo | Projeção é previsão; o app afirma o que observou. Ritmo oscila e a rajada curta gera alarme que se desmente sozinho |
| 4 | Limiares fixos em 80% e 95% | Menos botão. Configurável quando houver evidência de que precisa |
| 5 | Janelas de 5h e semanal; **não** as por modelo | Multiplicariam o ruído sem demanda conhecida |
| 6 | Sem persistência de estado | §5.2 a torna desnecessária |

---

## 4. Arquitetura

Mesma divisão que o resto do repo: regra pura no core, sistema no alvo de UI.

```
UsageStore.rebuild()  ──snapshot──▶  AlertPolicy (CCUsageCore, pura)
                                          │
                                     [Alert] a emitir
                                          │
                                     AlertPresenting (protocolo)
                                          │
                          UserNotificationPresenter (alvo de UI, UNUserNotificationCenter)
```

### 4.1 Tipos

```swift
// CCUsageCore
public enum Alert: Equatable, Sendable {
    case threshold(window: Window, percent: Int, resetsAt: Date?)
    case windowReset(window: Window)
    case liveRequired            // caso da decisão 2

    public enum Window: Equatable, Sendable { case session, weekly }
}

public struct AlertPolicy {
    public static let thresholds = [80, 95]
    public init()
    /// Consome um snapshot e devolve o que emitir. Guarda dentro de si o que já
    /// disparou, por instância de janela.
    public mutating func evaluate(_ snapshot: UsageSnapshot,
                                  alertsEnabled: Bool,
                                  liveEnabled: Bool) -> [Alert]
}
```

`evaluate` é `mutating` e determinística: mesma sequência de snapshots, mesma
saída. É isso que a torna testável sem relógio nem sistema de notificação.

**O `Alert` não carrega texto.** Ele carrega o fato — qual janela, qual
percentual, quando reseta — e quem compõe a frase é o presenter, no alvo de UI.
Copy em português dentro do `CCUsageCore` significaria ter que localizar o core
junto quando os idiomas chegarem; assim toda string de usuário continua num
lugar só. Os testes também ficam melhores: afirmam sobre o fato emitido, não
sobre a redação dele.

### 4.2 Onde ela roda

`UsageStore.rebuild()` (linha ~201) é o **ponto único** onde `snapshot` é
publicado. O store ganha um gancho opcional:

```swift
public var onSnapshot: ((UsageSnapshot) -> Void)?
```

chamado no fim de `rebuild()`. O coordenador vive no alvo de UI, segura a
`AlertPolicy` e o presenter, e não devolve nada ao store — o store continua sem
saber que notificação existe.

Alternativa descartada: observar `store.snapshot` de dentro de uma `View`. O
corpo de uma view pode ser reavaliado a qualquer momento e mais de uma vez por
mudança; efeito colateral ali duplica notificação.

---

## 5. Regras da política

### 5.1 Identidade da janela

Um limiar dispara **uma vez por instância de janela**, e rearma quando ela
reseta. A instância é identificada pelo `Gauge.resetsAt`: mudou o `resetsAt`, é
outra janela. Não é preciso inventar identificador — o dado já está lá.

`resetsAt` é `Date?`. Sendo `nil`, a janela **não é identificável** e nada
dispara para ela. Não é um caso raro a se ignorar: é o mesmo estado em que o
medidor costuma ser derivado, que a regra §2 já barra.

### 5.2 Linha de base no primeiro snapshot

O app sobe e o usuário já está em 92%. Disparar "80%" ali afirmaria um
cruzamento que ninguém observou — o app não viu subir, ele chegou depois.

**Regra:** no primeiro snapshot de cada instância de janela, a política apenas
registra como já disparados todos os limiares `<=` fração atual, e não emite
nada.

Custo: subir em 92% fica calado até 95%.
Ganho: nenhum alerta afirma cruzamento não observado.

**Consequência que simplifica o sistema:** isso torna a persistência
desnecessária. Se o processo reiniciar no meio da janela, a linha de base
reconstrói exatamente o estado correto a partir do próprio dado. Sem
`UserDefaults`, sem migração de formato, sem estado velho para apodrecer.

O limiar é comparado contra `Gauge.fraction`, que é saturada em 1, e **não**
contra `rawFraction`. Abaixo de 100% as duas são idênticas; a escolha importa
para o alerta concordar com o número que o painel mostra na mesma hora.

### 5.3 Fração que cai

Dentro de uma janela a fração só cresce até resetar — mas ela **pode cair** na
troca de fonte (cache velho → ao vivo), que é exatamente o cenário de 35% → 6%.

Como o registro é "este limiar já disparou nesta janela", cair e subir de novo
não redispara. A regra existe por causa de um caso medido, não hipotético.

### 5.4 Reset

Avisar todo reset da janela de 5h seriam quatro ou cinco notificações por dia.

**Regra:** o reset só avisa se aquela instância de janela tinha disparado algum
limiar. Você só ouve "sua janela resetou" se tinha encostado no teto. Quem nunca
chegou perto não recebe nada.

### 5.5 Ordem de avaliação

Primeira condição que casar vence, de cima para baixo — mesmo padrão do
`UsageSourcePolicy`:

1. Alertas desligados → nada
2. Alertas ligados e ao vivo desligado → `liveRequired`, **uma vez por execução**
3. Medidor sem `provenance == .live` → nada para aquele medidor
4. `resetsAt` nulo → nada para aquele medidor
5. Instância de janela nova → linha de base, sem emitir
6. Fração cruzou limiar ainda não disparado → `threshold`
7. Instância anterior tinha disparado e resetou → `windowReset`

---

## 6. UI

Nova seção nos Ajustes, entre "Números de uso" e "Teto do bloco de 5h":

```
Alertas
  [x] Avisar ao aproximar do teto
      Avisa em 80% e 95% de cada janela.
      [!] Alertas precisam da busca ao vivo — o cache do Claude Code
          pode estar horas atrasado.  [Ligar busca ao vivo]
      [!] Notificações negadas em Ajustes do Sistema.  [Abrir]
```

As duas linhas de aviso são condicionais e mutuamente independentes. A segunda
existe porque uma chave ligada sobre permissão negada é uma chave que mente.

Texto das notificações (pt-BR, como o resto do app; ver
[[i18n-pendente]] na memória do projeto):

| Alerta | Título | Corpo |
|---|---|---|
| `threshold` sessão | `80% da janela de 5h` | `Reseta às 2:19, em 2h 7m.` |
| `threshold` semanal | `95% da janela semanal` | `Reseta sexta às 4:00.` |
| `windowReset` sessão | `Janela de 5h resetou` | `Capacidade cheia de novo.` |
| `liveRequired` | `Alertas precisam da busca ao vivo` | `O cache do Claude Code pode estar horas atrasado. Ligue em Ajustes.` |

---

## 7. Permissão

Pedida **quando o usuário liga os alertas**, não no lançamento. Um app
`LSUIElement` que pede permissão de notificação ao subir pede sem contexto
visível, e a negativa é permanente.

Estados a tratar: não pedida, autorizada, negada. Negada precisa aparecer na UI
(§6) — o app não consegue reabrir o diálogo, só apontar para os Ajustes do
Sistema.

---

## 8. Testes

Todos sobre `AlertPolicy`, sem sistema de notificação:

| # | Teste |
|---|---|
| 1 | Primeiro snapshot de uma janela não dispara nada |
| 2 | Cruzar 80% dispara uma vez |
| 3 | O mesmo limiar não dispara duas vezes na mesma janela |
| 4 | `resetsAt` diferente rearma os limiares |
| 5 | Medidor com procedência de cache nunca dispara |
| 6 | Medidor derivado dentro de snapshot `.live` nunca dispara (§2.1) |
| 7 | `resetsAt` nulo nunca dispara |
| 8 | Fração que cai e sobe de novo não redispara |
| 9 | Reset avisa se a janela tinha disparado limiar |
| 10 | Reset não avisa se a janela nunca disparou |
| 11 | `liveRequired` sai uma vez por execução, não a cada snapshot |
| 12 | Alertas desligados: nenhuma saída em nenhum cenário acima |

---

## 9. Arquivos

| Ação | Arquivo |
|---|---|
| cria | `Sources/CCUsageCore/Alerts/Alert.swift` |
| cria | `Sources/CCUsageCore/Alerts/AlertPolicy.swift` |
| cria | `Sources/ClaudeTokenCounter/Alerts/UserNotificationPresenter.swift` |
| cria | `Sources/ClaudeTokenCounter/Alerts/AlertCoordinator.swift` |
| cria | `Tests/CCUsageCoreTests/AlertPolicyTests.swift` |
| edita | `Sources/CCUsageCore/UsageStore.swift` (gancho `onSnapshot`) |
| edita | `Sources/CCUsageCore/Settings/AppSettings.swift` (`alertsEnabled`) |
| edita | `Sources/ClaudeTokenCounter/Settings/SettingsView.swift` (seção) |
| edita | `Sources/ClaudeTokenCounter/App.swift` (liga o coordenador) |

---

## 10. Riscos

**`UNUserNotificationCenter` num app assinado ad-hoc.** Notificação depende de
identidade de bundle, e este app não tem Team ID nem notarização. Não está
verificado que funciona.

**Mitigação: é a primeira tarefa do plano.** Um teste de fumaça que dispara uma
notificação do bundle real, antes de qualquer política existir. Se falhar, a
feature muda de forma — e é melhor descobrir em dez minutos do que depois de
construir tudo.

**`liveRequired` reaparece a cada execução.** Como não há persistência (§5.2),
o "uma vez" vale enquanto o processo vive. Com o app aberto no login, isso é no
máximo uma vez por dia, para quem ligou alertas e mantém o ao vivo desligado —
uma configuração que não produz alerta nenhum. É defensável como cutucada, mas é
escolha, não acaso: se incomodar, o conserto é persistir um único booleano, e
esse é o momento de reconsiderar a decisão 6.

**Frequência de avaliação.** `rebuild()` roda a cada tick e a cada evento de
disco. A política é chamada muitas vezes por minuto; ela precisa ser barata e,
acima de tudo, idempotente entre snapshots iguais. Os testes 3 e 11 cobrem isso.

---

## 11. Não-objetivos

- Projeção por ritmo (§3, decisão 3)
- Limiares configuráveis (§3, decisão 4)
- Janelas por modelo (§3, decisão 5)
- Som, badge, ou notificação persistente
- Histórico de alertas no painel
