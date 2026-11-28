public import UntitledCore

/// What Basic naming reads.
public struct BasicInput: Sendable {
    public var lines: [ContentLine]
    public var titleLine: String?
    public var downloadDomain: String?
    public var app: String?
    public var candidates: [DateCandidate]
    public var labels: [ImageLabel]
    public var fileExtension: String?
    public var isScreenshot: Bool
    public var isScan: Bool
    public var strippedOriginal: String?

    public init(lines: [ContentLine] = [], titleLine: String? = nil, downloadDomain: String? = nil, app: String? = nil,
                candidates: [DateCandidate] = [], labels: [ImageLabel] = [], fileExtension: String? = nil,
                isScreenshot: Bool = false, isScan: Bool = false, strippedOriginal: String? = nil) {
        self.lines = lines
        self.titleLine = titleLine
        self.downloadDomain = downloadDomain
        self.app = app
        self.candidates = candidates
        self.labels = labels
        self.fileExtension = fileExtension
        self.isScreenshot = isScreenshot
        self.isScan = isScan
        self.strippedOriginal = strippedOriginal
    }
}

/// An image classification label with its confidence (3.7).
public struct ImageLabel: Sendable, Hashable, Codable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// The deterministic naming path used when the model can't be (3.3, 3.8).
public enum BasicNamer {
    public static func fields(_ input: BasicInput) -> GeneratedFields {
        let kind = detectKind(input)
        var source: String?
        if let domain = input.downloadDomain { source = DomainAliases.source(forDomain: domain) }
        if source == nil, let app = input.app { source = app }
        var subject = input.titleLine.map { cleanTitle($0) } ?? ""
        if subject.isEmpty, let label = input.labels.filter({ $0.confidence >= 0.3 }).max(by: { $0.confidence < $1.confidence }) {
            subject = label.identifier.replacingUnderscores
        }
        if subject.isEmpty, let original = input.strippedOriginal { subject = original }
        return GeneratedFields(kind: kind, source: source, subject: subject, dateChoice: input.candidates.first?.index)
    }

    static func detectKind(_ input: BasicInput) -> KindRef {
        let title = input.titleLine.map { TextFolding.key($0) } ?? ""
        let body = input.lines.prefix(60).map { TextFolding.key($0.text) }.joined(separator: "\n")
        for text in [title, body] where !text.isEmpty {
            let words = WordTokenizer.words(text)
            if let kind = KeywordTable.match(words) { return .builtIn(kind) }
        }
        let headers = input.lines.prefix(15).map { $0.text.lowercased() }
        let hasFrom = headers.contains { $0.hasPrefix("from:") || $0.hasPrefix("von:") || $0.hasPrefix("de :") || $0.hasPrefix("de:") }
        let hasSubject = headers.contains { $0.hasPrefix("subject:") || $0.hasPrefix("betreff:") || $0.hasPrefix("objet :") || $0.hasPrefix("objet:") || $0.hasPrefix("oggetto:") || $0.hasPrefix("asunto:") }
        if hasFrom, hasSubject { return .builtIn(.email) }
        switch input.fileExtension?.lowercased() {
        case "pptx", "key": return .builtIn(.presentation)
        case "xlsx", "numbers": return .builtIn(.spreadsheet)
        case "html", "htm": return .builtIn(.webPage)
        default: break
        }
        if input.isScan { return .builtIn(.scan) }
        if !input.isScreenshot, input.lines.isEmpty, input.labels.contains(where: { $0.confidence >= 0.5 }),
           let ext = input.fileExtension?.lowercased(), Eligibility.imageExtensions.contains(ext) {
            return .builtIn(.photo)
        }
        return .other
    }

    /// The title line without dates and long numbers; the formatter applies the rest of the guards.
    static func cleanTitle(_ title: String) -> String {
        let candidates = DateCandidateParser.candidates(in: title, language: nil)
        var text = title
        for candidate in candidates { text = text.replacingOccurrences(of: candidate.snippet, with: " ") }
        return WordTokenizer.words(text).filter { word in !(word.allSatisfy(\.isNumber) && word.count > 4) }.joined(separator: " ")
    }
}

/// Kind keywords in the supported languages (3.8 "Invoice/Facture/Rechnung/Fattura/…").
enum KeywordTable {
    static let entries: [(BuiltInKind, [String])] = [
        (.boardingPass, ["boarding pass", "bordkarte", "carte d'embarquement", "carta d'imbarco", "tarjeta de embarque", "cartao de embarque", "instapkaart", "搭乗券", "탑승권", "登机牌"]),
        (.bookingConfirmation, ["booking confirmation", "reservation confirmation", "buchungsbestatigung", "reservierungsbestatigung", "confirmation de reservation", "conferma di prenotazione", "confirmacion de reserva", "confirmacao de reserva", "boekingsbevestiging"]),
        (.orderConfirmation, ["order confirmation", "bestellbestatigung", "auftragsbestatigung", "confirmation de commande", "conferma d'ordine", "confirmacion de pedido", "confirmacao de pedido", "orderbevestiging", "注文確認"]),
        (.shippingLabel, ["shipping label", "versandetikett", "etiquette d'expedition", "etichetta di spedizione", "etiqueta de envio", "verzendlabel"]),
        (.bankStatement, ["bank statement", "account statement", "kontoauszug", "releve de compte", "releve bancaire", "estratto conto", "extracto bancario", "extrato bancario", "bankafschrift", "rekeningafschrift"]),
        (.payslip, ["payslip", "pay slip", "lohnabrechnung", "gehaltsabrechnung", "fiche de paie", "bulletin de salaire", "busta paga", "nomina", "holerite", "contracheque", "loonstrook", "給与明細"]),
        (.taxDocument, ["tax return", "tax assessment", "steuererklarung", "steuerbescheid", "steuerausweis", "declaration d'impots", "avis d'imposition", "dichiarazione dei redditi", "declaracion de la renta", "belastingaangifte", "w-2", "1099"]),
        (.invoice, ["invoice", "facture", "rechnung", "fattura", "factura", "fatura", "factuur", "請求書", "청구서", "发票"]),
        (.receipt, ["receipt", "quittung", "kassenbon", "kaufbeleg", "recu", "ricevuta", "scontrino", "recibo", "kwitantie", "kassabon", "領収書", "レシート", "영수증", "收据"]),
        (.contract, ["contract", "agreement", "vertrag", "contrat", "contratto", "contrato", "overeenkomst", "契約書", "계약서", "合同"]),
        (.certificate, ["certificate", "zertifikat", "bescheinigung", "zeugnis", "certificat", "attestation", "certificato", "certificado", "certificaat", "証明書"]),
        (.ticket, ["ticket", "billet", "biglietto", "billete", "bilhete", "fahrkarte", "eintrittskarte", "entrada", "チケット"]),
        (.manual, ["user manual", "user guide", "manual", "bedienungsanleitung", "handbuch", "mode d'emploi", "manuel", "manuale", "handleiding"]),
        (.resume, ["curriculum vitae", "resume", "lebenslauf", "cv"]),
        (.recipe, ["recipe", "ingredients", "rezept", "zutaten", "recette", "ingredients", "ricetta", "ingredienti", "receta", "receita"]),
        (.report, ["report", "bericht", "rapport", "relazione", "rapporto", "informe", "relatorio"]),
        (.form, ["application form", "form", "formular", "antrag", "formulaire", "modulo", "formulario", "formulier"]),
        (.letter, ["dear sir", "dear madam", "sehr geehrte", "madame, monsieur", "gentile", "estimado", "prezado", "geachte"]),
        (.errorMessage, ["error", "exception", "fatal", "failed", "fehler", "erreur", "errore"]),
    ]

    static let compiled: [(BuiltInKind, [[String]])] = entries.map { kind, phrases in
        (kind, phrases.map { WordTokenizer.words(TextFolding.key($0)) }.sorted { $0.count > $1.count })
    }

    /// The first kind whose keyword appears as whole words; longer phrases are tried first.
    static func match(_ words: [String]) -> BuiltInKind? {
        let keys = words.map { TextFolding.key($0) }
        var best: (kind: BuiltInKind, position: Int, length: Int)?
        for (kind, phrases) in compiled {
            for phrase in phrases where !phrase.isEmpty && phrase.count <= keys.count {
                for start in 0...(keys.count - phrase.count) where Array(keys[start..<(start + phrase.count)]) == phrase {
                    if best == nil || phrase.count > best!.length || (phrase.count == best!.length && start < best!.position) {
                        best = (kind, start, phrase.count)
                    }
                    break
                }
            }
        }
        return best?.kind
    }
}

extension String {
    var replacingUnderscores: String { split(separator: "_").joined(separator: " ") }
}
