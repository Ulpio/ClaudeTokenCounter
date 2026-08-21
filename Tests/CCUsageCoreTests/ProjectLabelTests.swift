import Foundation
import Testing
@testable import CCUsageCore

@Test func theLastSegmentIsEnoughWhenNothingCollides() {
    let labels = ProjectLabel.labels(for: ["-Users-me-Projects-Alpha",
                                           "-Users-me-Projects-Beta"])
    #expect(labels["-Users-me-Projects-Alpha"] == "Alpha")
    #expect(labels["-Users-me-Projects-Beta"] == "Beta")
}

@Test func collidingNamesGrowLeftUntilTheyDiffer() {
    // Rotulo curto que colide e pior que rotulo longo: dois "app" na lista nao
    // dizem qual e qual, e a tela existe justamente para responder isso.
    let labels = ProjectLabel.labels(for: ["-Users-me-work-app", "-Users-me-side-app"])
    #expect(labels["-Users-me-work-app"] == "work/app")
    #expect(labels["-Users-me-side-app"] == "side/app")
}

@Test func onlyTheCollidingOnesGrow() {
    let labels = ProjectLabel.labels(for: ["-Users-me-work-app",
                                           "-Users-me-side-app",
                                           "-Users-me-Projects-Solo"])
    #expect(labels["-Users-me-Projects-Solo"] == "Solo")
}

@Test func aSingleSegmentDoesNotBreak() {
    #expect(ProjectLabel.labels(for: ["scratch"])["scratch"] == "scratch")
}

@Test func doubledSeparatorsCollapse() {
    // "-Users-me--claude-mem" tem hifen que veio de hifen, nao de barra. Nada no
    // dado distingue os dois casos, entao segmento vazio simplesmente some.
    #expect(ProjectLabel.labels(for: ["-Users-me--claude-mem"])["-Users-me--claude-mem"] == "mem")
}

@Test func exhaustedSegmentsStopGrowingInsteadOfLooping() {
    // Duas entradas que so diferem no prefixo vazio nao tem como se separar
    // crescendo. O laco precisa parar, e o que sobra tem que continuar sendo
    // dois rotulos distintos: a chave crua e o unico desempate que resta.
    let labels = ProjectLabel.labels(for: ["-app", "app"])
    #expect(labels.count == 2)
    #expect(labels["-app"] == "-app")
    #expect(labels["app"] == "app")
}

@Test func aCollisionThatCannotBeSeparatedFallsBackToTheRawKey() {
    // ~/.claude-mem e ~/claude/mem sao diretorios diferentes que mutilam para
    // strings diferentes, mas para a MESMA lista de segmentos: o ponto e a
    // barra viraram o mesmo hifen. Crescer ate o fim daria "Users/me/claude/mem"
    // nos dois — longo E ambiguo, o pior resultado possivel.
    let raws = ["-Users-me--claude-mem", "-Users-me-claude-mem"]
    let labels = ProjectLabel.labels(for: raws)
    #expect(labels["-Users-me--claude-mem"] != labels["-Users-me-claude-mem"])
    #expect(labels["-Users-me--claude-mem"] == "-Users-me--claude-mem")
    #expect(labels["-Users-me-claude-mem"] == "-Users-me-claude-mem")
}

@Test func anEmptyRawMapsToItself() {
    // A chave vazia dos eventos sem projeto nunca chega aqui — a aba a filtra
    // antes. O caso existe para a funcao ser total, nao para ser exibido.
    #expect(ProjectLabel.labels(for: [""])[""] == "")
}

@Test func aDuplicateRawDoesNotCrash() {
    // Nada no tipo `[String]` impede repeticao. Um chamador futuro que mapeie
    // eventos sem tirar duplicata antes nao pode derrubar a funcao.
    let labels = ProjectLabel.labels(for: ["-Users-me-Projects-Alpha",
                                           "-Users-me-Projects-Alpha"])
    #expect(labels.count == 1)
    #expect(labels["-Users-me-Projects-Alpha"] == "Alpha")
}
