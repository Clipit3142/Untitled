/// The built-in document kinds from spec 3.8.
public enum BuiltInKind: String, CaseIterable, Codable, Sendable, Hashable {
    case invoice, receipt, bankStatement, payslip, taxDocument, contract, letter, form
    case certificate, ticket, boardingPass, bookingConfirmation, orderConfirmation
    case shippingLabel, manual, report, article, presentation, spreadsheet, resume
    case recipe, map, chat, email, socialPost, webPage, errorMessage, code, diagram
    case chart, design, photo, scan

    /// The English label, which is also the value the model chooses from.
    public var englishLabel: String { label(in: .english) }

    /// The label in a name language (app-provided translations, 3.10 step 2).
    public func label(in language: NameLanguage) -> String {
        let row = KindLabels.table[self] ?? []
        let index = NameLanguage.allCases.firstIndex(of: language) ?? 0
        return index < row.count ? row[index] : englishLabelFallback
    }

    private var englishLabelFallback: String { rawValue }
}

/// A user-defined kind. Its label is used as written in every name language.
public struct CustomKind: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// The kind chosen for a file.
public enum KindRef: Codable, Sendable, Hashable {
    case builtIn(BuiltInKind)
    case custom(id: String)
    case other

    /// Label used in a name. `other` has no label: it counts as empty (3.9).
    public func label(in language: NameLanguage, customKinds: [CustomKind]) -> String {
        switch self {
        case .builtIn(let kind): kind.label(in: language)
        case .custom(let id): customKinds.first(where: { $0.id == id })?.label ?? ""
        case .other: ""
        }
    }

    /// The schema value the model sees for this kind.
    public func schemaValue(customKinds: [CustomKind]) -> String {
        switch self {
        case .builtIn(let kind): kind.englishLabel
        case .custom(let id): customKinds.first(where: { $0.id == id })?.label ?? "Other"
        case .other: "Other"
        }
    }

    /// Resolves a schema value back to a kind. Unknown values become `other`.
    public static func fromSchemaValue(_ value: String, customKinds: [CustomKind]) -> KindRef {
        if let builtIn = BuiltInKind.allCases.first(where: { $0.englishLabel == value }) {
            return .builtIn(builtIn)
        }
        if let custom = customKinds.first(where: { $0.label == value }) {
            return .custom(id: custom.id)
        }
        return .other
    }
}

/// Labels per language, in `NameLanguage.allCases` order:
/// en, de, fr, it, es, pt, nl, ja, ko, zh-Hans.
enum KindLabels {
    static let table: [BuiltInKind: [String]] = [
        .invoice: ["Invoice", "Rechnung", "Facture", "Fattura", "Factura", "Fatura", "Factuur", "請求書", "청구서", "发票"],
        .receipt: ["Receipt", "Quittung", "Reçu", "Ricevuta", "Recibo", "Recibo", "Bon", "領収書", "영수증", "收据"],
        .bankStatement: ["Bank Statement", "Kontoauszug", "Relevé bancaire", "Estratto conto", "Extracto bancario", "Extrato bancário", "Bankafschrift", "銀行取引明細書", "은행 거래 내역서", "银行对账单"],
        .payslip: ["Payslip", "Lohnabrechnung", "Fiche de paie", "Busta paga", "Nómina", "Recibo de salário", "Loonstrook", "給与明細", "급여 명세서", "工资单"],
        .taxDocument: ["Tax Document", "Steuerdokument", "Document fiscal", "Documento fiscale", "Documento fiscal", "Documento fiscal", "Belastingdocument", "税務書類", "세금 문서", "税务文件"],
        .contract: ["Contract", "Vertrag", "Contrat", "Contratto", "Contrato", "Contrato", "Contract", "契約書", "계약서", "合同"],
        .letter: ["Letter", "Brief", "Lettre", "Lettera", "Carta", "Carta", "Brief", "手紙", "편지", "信函"],
        .form: ["Form", "Formular", "Formulaire", "Modulo", "Formulario", "Formulário", "Formulier", "申込書", "양식", "表格"],
        .certificate: ["Certificate", "Zertifikat", "Certificat", "Certificato", "Certificado", "Certificado", "Certificaat", "証明書", "증명서", "证书"],
        .ticket: ["Ticket", "Ticket", "Billet", "Biglietto", "Billete", "Bilhete", "Ticket", "チケット", "티켓", "票"],
        .boardingPass: ["Boarding Pass", "Bordkarte", "Carte d'embarquement", "Carta d'imbarco", "Tarjeta de embarque", "Cartão de embarque", "Instapkaart", "搭乗券", "탑승권", "登机牌"],
        .bookingConfirmation: ["Booking Confirmation", "Buchungsbestätigung", "Confirmation de réservation", "Conferma di prenotazione", "Confirmación de reserva", "Confirmação de reserva", "Boekingsbevestiging", "予約確認", "예약 확인서", "预订确认"],
        .orderConfirmation: ["Order Confirmation", "Bestellbestätigung", "Confirmation de commande", "Conferma d'ordine", "Confirmación de pedido", "Confirmação de pedido", "Orderbevestiging", "注文確認", "주문 확인서", "订单确认"],
        .shippingLabel: ["Shipping Label", "Versandetikett", "Étiquette d'expédition", "Etichetta di spedizione", "Etiqueta de envío", "Etiqueta de envio", "Verzendlabel", "配送ラベル", "배송 라벨", "快递单"],
        .manual: ["Manual", "Handbuch", "Manuel", "Manuale", "Manual", "Manual", "Handleiding", "マニュアル", "설명서", "手册"],
        .report: ["Report", "Bericht", "Rapport", "Rapporto", "Informe", "Relatório", "Rapport", "レポート", "보고서", "报告"],
        .article: ["Article", "Artikel", "Article", "Articolo", "Artículo", "Artigo", "Artikel", "記事", "기사", "文章"],
        .presentation: ["Presentation", "Präsentation", "Présentation", "Presentazione", "Presentación", "Apresentação", "Presentatie", "プレゼンテーション", "프레젠테이션", "演示文稿"],
        .spreadsheet: ["Spreadsheet", "Tabelle", "Feuille de calcul", "Foglio di calcolo", "Hoja de cálculo", "Planilha", "Spreadsheet", "スプレッドシート", "스프레드시트", "电子表格"],
        .resume: ["Résumé", "Lebenslauf", "CV", "Curriculum", "Currículum", "Currículo", "Cv", "履歴書", "이력서", "简历"],
        .recipe: ["Recipe", "Rezept", "Recette", "Ricetta", "Receta", "Receita", "Recept", "レシピ", "레시피", "食谱"],
        .map: ["Map", "Karte", "Carte", "Mappa", "Mapa", "Mapa", "Kaart", "地図", "지도", "地图"],
        .chat: ["Chat", "Chat", "Discussion", "Chat", "Chat", "Conversa", "Chat", "チャット", "채팅", "聊天"],
        .email: ["Email", "E-Mail", "E-mail", "Email", "Correo", "E-mail", "E-mail", "メール", "이메일", "电子邮件"],
        .socialPost: ["Social Post", "Beitrag", "Publication", "Post", "Publicación", "Publicação", "Bericht", "SNS投稿", "소셜 게시물", "社交帖子"],
        .webPage: ["Web Page", "Webseite", "Page web", "Pagina web", "Página web", "Página web", "Webpagina", "ウェブページ", "웹 페이지", "网页"],
        .errorMessage: ["Error Message", "Fehlermeldung", "Message d'erreur", "Messaggio di errore", "Mensaje de error", "Mensagem de erro", "Foutmelding", "エラーメッセージ", "오류 메시지", "错误信息"],
        .code: ["Code", "Code", "Code", "Codice", "Código", "Código", "Code", "コード", "코드", "代码"],
        .diagram: ["Diagram", "Schema", "Schéma", "Schema", "Diagrama", "Diagrama", "Diagram", "図", "다이어그램", "示意图"],
        .chart: ["Chart", "Diagramm", "Graphique", "Grafico", "Gráfico", "Gráfico", "Grafiek", "グラフ", "차트", "图表"],
        .design: ["Design", "Entwurf", "Maquette", "Design", "Diseño", "Design", "Ontwerp", "デザイン", "디자인", "设计"],
        .photo: ["Photo", "Foto", "Photo", "Foto", "Foto", "Foto", "Foto", "写真", "사진", "照片"],
        .scan: ["Scan", "Scan", "Numérisation", "Scansione", "Escaneo", "Digitalização", "Scan", "スキャン", "스캔", "扫描件"],
    ]
}
