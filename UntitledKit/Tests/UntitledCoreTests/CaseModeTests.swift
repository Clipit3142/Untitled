import Testing
import UntitledTestSupport
@testable import UntitledCore

/// H2: each case mode matches ≥ 100 expected input/output pairs, covering protected words,
/// acronyms, apostrophes, hyphens, numbers and caseless scripts.
struct CaseModeTests {
    struct Row: Sendable {
        var language: NameLanguage
        var input: String
        var title: String
        var sentence: String
        var lower: String
        var upper: String
        var camel: String
        var pascal: String
        var asGenerated: String

        func expected(_ mode: CaseMode) -> String {
            switch mode {
            case .title: title
            case .sentence: sentence
            case .lowercase: lower
            case .uppercase: upper
            case .camel: camel
            case .pascal: pascal
            case .asGenerated: asGenerated
            }
        }
    }

    static func r(_ language: NameLanguage = .english, _ input: String, _ title: String, _ sentence: String,
                  _ lower: String, _ upper: String, _ camel: String, _ pascal: String, _ asGenerated: String? = nil) -> Row {
        Row(language: language, input: input, title: title, sentence: sentence, lower: lower, upper: upper,
            camel: camel, pascal: pascal, asGenerated: asGenerated ?? input)
    }

    static let rows: [Row] = [
        r(.english, "mobile subscription november", "Mobile Subscription November", "Mobile subscription november", "mobile subscription november", "MOBILE SUBSCRIPTION NOVEMBER", "mobileSubscriptionNovember", "MobileSubscriptionNovember"),
        r(.english, "the lord of the rings", "The Lord of the Rings", "The lord of the rings", "the lord of the rings", "THE LORD OF THE RINGS", "theLordOfTheRings", "TheLordOfTheRings"),
        r(.english, "iphone receipt", "iPhone Receipt", "iPhone receipt", "iphone receipt", "IPHONE RECEIPT", "iphoneReceipt", "IphoneReceipt", "iPhone receipt"),
        r(.english, "MACOS update notes", "macOS Update Notes", "macOS update notes", "macos update notes", "MACOS UPDATE NOTES", "macosUpdateNotes", "MacosUpdateNotes", "macOS update notes"),
        r(.english, "PDF export settings", "PDF Export Settings", "PDF export settings", "pdf export settings", "PDF EXPORT SETTINGS", "pdfExportSettings", "PdfExportSettings"),
        r(.english, "INVOICE FOR SERVICES", "Invoice for Services", "Invoice for services", "invoice for services", "INVOICE FOR SERVICES", "invoiceForServices", "InvoiceForServices"),
        r(.english, "don't panic guide", "Don't Panic Guide", "Don't panic guide", "don't panic guide", "DON'T PANIC GUIDE", "dontPanicGuide", "DontPanicGuide"),
        r(.english, "follow-up meeting notes", "Follow-Up Meeting Notes", "Follow-up meeting notes", "follow-up meeting notes", "FOLLOW-UP MEETING NOTES", "followUpMeetingNotes", "FollowUpMeetingNotes"),
        r(.english, "state-of-the-art report", "State-of-the-Art Report", "State-of-the-art report", "state-of-the-art report", "STATE-OF-THE-ART REPORT", "stateOfTheArtReport", "StateOfTheArtReport"),
        r(.english, "2nd quarter results", "2nd Quarter Results", "2nd quarter results", "2nd quarter results", "2ND QUARTER RESULTS", "2ndQuarterResults", "2ndQuarterResults"),
        r(.english, "q3 2026 budget", "Q3 2026 Budget", "Q3 2026 budget", "q3 2026 budget", "Q3 2026 BUDGET", "q32026Budget", "Q32026Budget"),
        r(.english, "ebay order confirmation", "eBay Order Confirmation", "eBay order confirmation", "ebay order confirmation", "EBAY ORDER CONFIRMATION", "ebayOrderConfirmation", "EbayOrderConfirmation", "eBay order confirmation"),
        r(.english, "McDonald's receipt", "McDonald's Receipt", "McDonald's receipt", "mcdonald's receipt", "MCDONALD'S RECEIPT", "mcdonaldsReceipt", "McdonaldsReceipt"),
        r(.english, "a tale of two cities", "A Tale of Two Cities", "A tale of two cities", "a tale of two cities", "A TALE OF TWO CITIES", "aTaleOfTwoCities", "ATaleOfTwoCities"),
        r(.english, "notes on the go", "Notes on the Go", "Notes on the go", "notes on the go", "NOTES ON THE GO", "notesOnTheGo", "NotesOnTheGo"),
        r(.english, "github pull request", "GitHub Pull Request", "GitHub pull request", "github pull request", "GITHUB PULL REQUEST", "githubPullRequest", "GithubPullRequest", "GitHub pull request"),
        r(.english, "USA travel visa", "USA Travel Visa", "USA travel visa", "usa travel visa", "USA TRAVEL VISA", "usaTravelVisa", "UsaTravelVisa"),
        r(.english, "NASA mission brief", "NASA Mission Brief", "NASA mission brief", "nasa mission brief", "NASA MISSION BRIEF", "nasaMissionBrief", "NasaMissionBrief"),
        r(.english, "o'neil family photos", "O'Neil Family Photos", "O'neil family photos", "o'neil family photos", "O'NEIL FAMILY PHOTOS", "oNeilFamilyPhotos", "ONeilFamilyPhotos"),
        r(.english, "rock and roll history", "Rock and Roll History", "Rock and roll history", "rock and roll history", "ROCK AND ROLL HISTORY", "rockAndRollHistory", "RockAndRollHistory"),
        r(.english, "wi-fi password reset", "Wi-Fi Password Reset", "Wi-fi password reset", "wi-fi password reset", "WI-FI PASSWORD RESET", "wiFiPasswordReset", "WiFiPasswordReset"),
        r(.english, "3D printer manual", "3D Printer Manual", "3D printer manual", "3d printer manual", "3D PRINTER MANUAL", "3dPrinterManual", "3dPrinterManual"),
        r(.english, "covid-19 test result", "Covid-19 Test Result", "Covid-19 test result", "covid-19 test result", "COVID-19 TEST RESULT", "covid19TestResult", "Covid19TestResult"),
        r(.english, "tax return 2025", "Tax Return 2025", "Tax return 2025", "tax return 2025", "TAX RETURN 2025", "taxReturn2025", "TaxReturn2025"),
        r(.english, "paypal transfer to anna", "PayPal Transfer to Anna", "PayPal transfer to anna", "paypal transfer to anna", "PAYPAL TRANSFER TO ANNA", "paypalTransferToAnna", "PaypalTransferToAnna", "PayPal transfer to anna"),
        r(.english, "Meeting with Anna and Ben", "Meeting With Anna and Ben", "Meeting with anna and ben", "meeting with anna and ben", "MEETING WITH ANNA AND BEN", "meetingWithAnnaAndBen", "MeetingWithAnnaAndBen"),
        r(.english, "youtube video ideas", "YouTube Video Ideas", "YouTube video ideas", "youtube video ideas", "YOUTUBE VIDEO IDEAS", "youtubeVideoIdeas", "YoutubeVideoIdeas", "YouTube video ideas"),
        r(.english, "linkedin profile export", "LinkedIn Profile Export", "LinkedIn profile export", "linkedin profile export", "LINKEDIN PROFILE EXPORT", "linkedinProfileExport", "LinkedinProfileExport", "LinkedIn profile export"),
        r(.english, "IKEA assembly instructions", "IKEA Assembly Instructions", "IKEA assembly instructions", "ikea assembly instructions", "IKEA ASSEMBLY INSTRUCTIONS", "ikeaAssemblyInstructions", "IkeaAssemblyInstructions"),
        r(.english, "BMW SERVICE INVOICE", "BMW Service Invoice", "BMW service invoice", "bmw service invoice", "BMW SERVICE INVOICE", "bmwServiceInvoice", "BmwServiceInvoice"),
        r(.english, "an apple a day", "An Apple a Day", "An apple a day", "an apple a day", "AN APPLE A DAY", "anAppleADay", "AnAppleADay"),
        r(.english, "über cool ideas", "Über Cool Ideas", "Über cool ideas", "über cool ideas", "ÜBER COOL IDEAS", "überCoolIdeas", "ÜberCoolIdeas"),
        r(.english, "élodie's birthday party", "Élodie's Birthday Party", "Élodie's birthday party", "élodie's birthday party", "ÉLODIE'S BIRTHDAY PARTY", "élodiesBirthdayParty", "ÉlodiesBirthdayParty"),
        r(.english, "straße renovation plan", "Straße Renovation Plan", "Straße renovation plan", "straße renovation plan", "STRASSE RENOVATION PLAN", "straßeRenovationPlan", "StraßeRenovationPlan"),
        r(.english, "east-west travel log", "East-West Travel Log", "East-west travel log", "east-west travel log", "EAST-WEST TRAVEL LOG", "eastWestTravelLog", "EastWestTravelLog"),
        r(.english, "for sale by owner", "For Sale by Owner", "For sale by owner", "for sale by owner", "FOR SALE BY OWNER", "forSaleByOwner", "ForSaleByOwner"),
        r(.english, "what to do", "What to Do", "What to do", "what to do", "WHAT TO DO", "whatToDo", "WhatToDo"),
        r(.english, "the end", "The End", "The end", "the end", "THE END", "theEnd", "TheEnd"),
        r(.english, "ups shipping label", "UPS Shipping Label", "UPS shipping label", "ups shipping label", "UPS SHIPPING LABEL", "upsShippingLabel", "UpsShippingLabel", "UPS shipping label"),
        r(.english, "dhl tracking info", "DHL Tracking Info", "DHL tracking info", "dhl tracking info", "DHL TRACKING INFO", "dhlTrackingInfo", "DhlTrackingInfo", "DHL tracking info"),
        r(.english, "fedex delivery notice", "FedEx Delivery Notice", "FedEx delivery notice", "fedex delivery notice", "FEDEX DELIVERY NOTICE", "fedexDeliveryNotice", "FedexDeliveryNotice", "FedEx delivery notice"),
        r(.english, "vat return q4", "VAT Return Q4", "VAT return q4", "vat return q4", "VAT RETURN Q4", "vatReturnQ4", "VatReturnQ4", "VAT return q4"),
        r(.english, "chatgpt conversation export", "ChatGPT Conversation Export", "ChatGPT conversation export", "chatgpt conversation export", "CHATGPT CONVERSATION EXPORT", "chatgptConversationExport", "ChatgptConversationExport", "ChatGPT conversation export"),
        r(.english, "MacBook battery report", "MacBook Battery Report", "MacBook battery report", "macbook battery report", "MACBOOK BATTERY REPORT", "macbookBatteryReport", "MacbookBatteryReport"),
        r(.english, "iOS 27 release notes", "iOS 27 Release Notes", "iOS 27 release notes", "ios 27 release notes", "IOS 27 RELEASE NOTES", "ios27ReleaseNotes", "Ios27ReleaseNotes"),
        r(.english, "Harry Potter Fan Art", "Harry Potter Fan Art", "Harry potter fan art", "harry potter fan art", "HARRY POTTER FAN ART", "harryPotterFanArt", "HarryPotterFanArt"),
        r(.english, "hello WORLD program", "Hello World Program", "Hello world program", "hello world program", "HELLO WORLD PROGRAM", "helloWorldProgram", "HelloWorldProgram"),
        r(.english, "API KEY rotation", "API KEY Rotation", "API KEY rotation", "api key rotation", "API KEY ROTATION", "apiKeyRotation", "ApiKeyRotation"),
        r(.english, "x-ray results", "X-Ray Results", "X-ray results", "x-ray results", "X-RAY RESULTS", "xRayResults", "XRayResults"),
        r(.english, "e-mail from bank", "E-Mail From Bank", "E-mail from bank", "e-mail from bank", "E-MAIL FROM BANK", "eMailFromBank", "EMailFromBank"),
        r(.english, "jack-in-the-box toy", "Jack-in-the-Box Toy", "Jack-in-the-box toy", "jack-in-the-box toy", "JACK-IN-THE-BOX TOY", "jackInTheBoxToy", "JackInTheBoxToy"),
        r(.english, "log in to portal", "Log in to Portal", "Log in to portal", "log in to portal", "LOG IN TO PORTAL", "logInToPortal", "LogInToPortal"),
        r(.english, "R&D budget plan", "R&D Budget Plan", "R&D budget plan", "r&d budget plan", "R&D BUDGET PLAN", "r&dBudgetPlan", "R&dBudgetPlan"),
        r(.english, "at&t phone bill", "At&t Phone Bill", "At&t phone bill", "at&t phone bill", "AT&T PHONE BILL", "at&tPhoneBill", "At&tPhoneBill"),
        r(.english, "v2.1 release checklist", "V2.1 Release Checklist", "V2.1 release checklist", "v2.1 release checklist", "V2.1 RELEASE CHECKLIST", "v2.1ReleaseChecklist", "V2.1ReleaseChecklist"),
        r(.english, "café menu prices", "Café Menu Prices", "Café menu prices", "café menu prices", "CAFÉ MENU PRICES", "caféMenuPrices", "CaféMenuPrices"),
        r(.english, "naïve bayes notes", "Naïve Bayes Notes", "Naïve bayes notes", "naïve bayes notes", "NAÏVE BAYES NOTES", "naïveBayesNotes", "NaïveBayesNotes"),
        r(.english, "flight to new york", "Flight to New York", "Flight to new york", "flight to new york", "FLIGHT TO NEW YORK", "flightToNewYork", "FlightToNewYork"),
        r(.english, "zoom call recording", "Zoom Call Recording", "Zoom call recording", "zoom call recording", "ZOOM CALL RECORDING", "zoomCallRecording", "ZoomCallRecording"),
        r(.english, "kindergarten enrollment form", "Kindergarten Enrollment Form", "Kindergarten enrollment form", "kindergarten enrollment form", "KINDERGARTEN ENROLLMENT FORM", "kindergartenEnrollmentForm", "KindergartenEnrollmentForm"),
        r(.french, "carte d'embarquement genève", "Carte d'Embarquement Genève", "Carte d'embarquement genève", "carte d'embarquement genève", "CARTE D'EMBARQUEMENT GENÈVE", "carteDEmbarquementGenève", "CarteDEmbarquementGenève"),
        r(.french, "l'offre de bienvenue", "L'Offre de Bienvenue", "L'offre de bienvenue", "l'offre de bienvenue", "L'OFFRE DE BIENVENUE", "lOffreDeBienvenue", "LOffreDeBienvenue"),
        r(.french, "facture de la banque", "Facture de la Banque", "Facture de la banque", "facture de la banque", "FACTURE DE LA BANQUE", "factureDeLaBanque", "FactureDeLaBanque"),
        r(.french, "relevé de compte mensuel", "Relevé de Compte Mensuel", "Relevé de compte mensuel", "relevé de compte mensuel", "RELEVÉ DE COMPTE MENSUEL", "relevéDeCompteMensuel", "RelevéDeCompteMensuel"),
        r(.french, "rendez-vous chez le médecin", "Rendez-Vous Chez le Médecin", "Rendez-vous chez le médecin", "rendez-vous chez le médecin", "RENDEZ-VOUS CHEZ LE MÉDECIN", "rendezVousChezLeMédecin", "RendezVousChezLeMédecin"),
        r(.german, "rechnung für das auto", "Rechnung für das Auto", "Rechnung für das auto", "rechnung für das auto", "RECHNUNG FÜR DAS AUTO", "rechnungFürDasAuto", "RechnungFürDasAuto"),
        r(.german, "Kontoauszug der Sparkasse", "Kontoauszug der Sparkasse", "Kontoauszug der Sparkasse", "kontoauszug der sparkasse", "KONTOAUSZUG DER SPARKASSE", "kontoauszugDerSparkasse", "KontoauszugDerSparkasse"),
        r(.german, "MIETVERTRAG WOHNUNG BERLIN", "Mietvertrag Wohnung Berlin", "Mietvertrag wohnung berlin", "mietvertrag wohnung berlin", "MIETVERTRAG WOHNUNG BERLIN", "mietvertragWohnungBerlin", "MietvertragWohnungBerlin"),
        r(.german, "Lohnabrechnung November", "Lohnabrechnung November", "Lohnabrechnung November", "lohnabrechnung november", "LOHNABRECHNUNG NOVEMBER", "lohnabrechnungNovember", "LohnabrechnungNovember"),
        r(.german, "über das leben", "Über das Leben", "Über das leben", "über das leben", "ÜBER DAS LEBEN", "überDasLeben", "ÜberDasLeben"),
        r(.italian, "fattura della luce", "Fattura della Luce", "Fattura della luce", "fattura della luce", "FATTURA DELLA LUCE", "fatturaDellaLuce", "FatturaDellaLuce"),
        r(.italian, "conferma d'ordine amazon", "Conferma d'Ordine Amazon", "Conferma d'ordine amazon", "conferma d'ordine amazon", "CONFERMA D'ORDINE AMAZON", "confermaDOrdineAmazon", "ConfermaDOrdineAmazon"),
        r(.spanish, "factura de la luz", "Factura de la Luz", "Factura de la luz", "factura de la luz", "FACTURA DE LA LUZ", "facturaDeLaLuz", "FacturaDeLaLuz"),
        r(.spanish, "extracto bancario y recibos", "Extracto Bancario y Recibos", "Extracto bancario y recibos", "extracto bancario y recibos", "EXTRACTO BANCARIO Y RECIBOS", "extractoBancarioYRecibos", "ExtractoBancarioYRecibos"),
        r(.portuguese, "fatura da operadora", "Fatura da Operadora", "Fatura da operadora", "fatura da operadora", "FATURA DA OPERADORA", "faturaDaOperadora", "FaturaDaOperadora"),
        r(.portuguese, "cartão de embarque para lisboa", "Cartão de Embarque para Lisboa", "Cartão de embarque para lisboa", "cartão de embarque para lisboa", "CARTÃO DE EMBARQUE PARA LISBOA", "cartãoDeEmbarqueParaLisboa", "CartãoDeEmbarqueParaLisboa"),
        r(.dutch, "ijsland reisplan", "IJsland Reisplan", "IJsland reisplan", "ijsland reisplan", "IJSLAND REISPLAN", "ijslandReisplan", "IjslandReisplan"),
        r(.dutch, "factuur van de energie", "Factuur Van De Energie", "Factuur van de energie", "factuur van de energie", "FACTUUR VAN DE ENERGIE", "factuurVanDeEnergie", "FactuurVanDeEnergie"),
        r(.japanese, "請求書 アマゾン", "請求書 アマゾン", "請求書 アマゾン", "請求書 アマゾン", "請求書 アマゾン", "請求書アマゾン", "請求書アマゾン"),
        r(.korean, "청구서 통신사", "청구서 통신사", "청구서 통신사", "청구서 통신사", "청구서 통신사", "청구서통신사", "청구서통신사"),
        r(.chineseSimplified, "发票 中国移动", "发票 中国移动", "发票 中国移动", "发票 中国移动", "发票 中国移动", "发票中国移动", "发票中国移动"),
        r(.english, "мой отчёт", "Мой Отчёт", "Мой отчёт", "мой отчёт", "МОЙ ОТЧЁТ", "мойОтчёт", "МойОтчёт"),
        r(.english, "דוח שנתי", "דוח שנתי", "דוח שנתי", "דוח שנתי", "דוח שנתי", "דוחשנתי", "דוחשנתי"),
        r(.english, "تقرير سنوي", "تقرير سنوي", "تقرير سنوي", "تقرير سنوي", "تقرير سنوي", "تقريرسنوي", "تقريرسنوي"),
        r(.english, "back to school list", "Back to School List", "Back to school list", "back to school list", "BACK TO SCHOOL LIST", "backToSchoolList", "BackToSchoolList"),
        r(.english, "pros and cons", "Pros and Cons", "Pros and cons", "pros and cons", "PROS AND CONS", "prosAndCons", "ProsAndCons"),
        r(.english, "up and running", "Up and Running", "Up and running", "up and running", "UP AND RUNNING", "upAndRunning", "UpAndRunning"),
        r(.english, "dog's vet record", "Dog's Vet Record", "Dog's vet record", "dog's vet record", "DOG'S VET RECORD", "dogsVetRecord", "DogsVetRecord"),
        r(.english, "nineteen eighty-four", "Nineteen Eighty-Four", "Nineteen eighty-four", "nineteen eighty-four", "NINETEEN EIGHTY-FOUR", "nineteenEightyFour", "NineteenEightyFour"),
        r(.english, "To Kill A Mockingbird", "To Kill a Mockingbird", "To kill a mockingbird", "to kill a mockingbird", "TO KILL A MOCKINGBIRD", "toKillAMockingbird", "ToKillAMockingbird"),
        r(.english, "self-assessment tax form", "Self-Assessment Tax Form", "Self-assessment tax form", "self-assessment tax form", "SELF-ASSESSMENT TAX FORM", "selfAssessmentTaxForm", "SelfAssessmentTaxForm"),
        r(.english, "airpods warranty claim", "AirPods Warranty Claim", "AirPods warranty claim", "airpods warranty claim", "AIRPODS WARRANTY CLAIM", "airpodsWarrantyClaim", "AirpodsWarrantyClaim", "AirPods warranty claim"),
        r(.english, "whatsapp chat backup", "WhatsApp Chat Backup", "WhatsApp chat backup", "whatsapp chat backup", "WHATSAPP CHAT BACKUP", "whatsappChatBackup", "WhatsappChatBackup", "WhatsApp chat backup"),
        r(.english, "icloud storage plan", "iCloud Storage Plan", "iCloud storage plan", "icloud storage plan", "ICLOUD STORAGE PLAN", "icloudStoragePlan", "IcloudStoragePlan", "iCloud storage plan"),
        r(.english, "powerpoint template draft", "PowerPoint Template Draft", "PowerPoint template draft", "powerpoint template draft", "POWERPOINT TEMPLATE DRAFT", "powerpointTemplateDraft", "PowerpointTemplateDraft", "PowerPoint template draft"),
        r(.english, "javascript cheat sheet", "JavaScript Cheat Sheet", "JavaScript cheat sheet", "javascript cheat sheet", "JAVASCRIPT CHEAT SHEET", "javascriptCheatSheet", "JavascriptCheatSheet", "JavaScript cheat sheet"),
        r(.english, "SBB ticket zurich", "SBB Ticket Zurich", "SBB ticket zurich", "sbb ticket zurich", "SBB TICKET ZURICH", "sbbTicketZurich", "SbbTicketZurich"),
        r(.english, "hdmi cable order", "HDMI Cable Order", "HDMI cable order", "hdmi cable order", "HDMI CABLE ORDER", "hdmiCableOrder", "HdmiCableOrder", "HDMI cable order"),
        r(.english, "qr code menu", "QR Code Menu", "QR code menu", "qr code menu", "QR CODE MENU", "qrCodeMenu", "QrCodeMenu", "QR code menu"),
        r(.english, "ahv statement 2026", "AHV Statement 2026", "AHV statement 2026", "ahv statement 2026", "AHV STATEMENT 2026", "ahvStatement2026", "AhvStatement2026", "AHV statement 2026"),
        r(.english, "one-on-one notes", "One-on-One Notes", "One-on-one notes", "one-on-one notes", "ONE-ON-ONE NOTES", "oneOnOneNotes", "OneOnOneNotes"),
        r(.english, "the who concert tickets", "The Who Concert Tickets", "The who concert tickets", "the who concert tickets", "THE WHO CONCERT TICKETS", "theWhoConcertTickets", "TheWhoConcertTickets"),
        r(.english, "summer vacation photos", "Summer Vacation Photos", "Summer vacation photos", "summer vacation photos", "SUMMER VACATION PHOTOS", "summerVacationPhotos", "SummerVacationPhotos"),
        r(.english, "phd thesis draft", "Phd Thesis Draft", "Phd thesis draft", "phd thesis draft", "PHD THESIS DRAFT", "phdThesisDraft", "PhdThesisDraft"),
        r(.english, "PhD thesis draft", "PhD Thesis Draft", "PhD thesis draft", "phd thesis draft", "PHD THESIS DRAFT", "phdThesisDraft", "PhdThesisDraft"),
        r(.english, "an IOU note", "An IOU Note", "An IOU note", "an iou note", "AN IOU NOTE", "anIouNote", "AnIouNote"),
        r(.english, "rock 'n' roll", "Rock N Roll", "Rock n roll", "rock n roll", "ROCK N ROLL", "rockNRoll", "RockNRoll", "rock n roll"),
        r(.english, "New Year's Eve plans", "New Year's Eve Plans", "New year's eve plans", "new year's eve plans", "NEW YEAR'S EVE PLANS", "newYearsEvePlans", "NewYearsEvePlans"),
        r(.english, "tv guide schedule", "Tv Guide Schedule", "Tv guide schedule", "tv guide schedule", "TV GUIDE SCHEDULE", "tvGuideSchedule", "TvGuideSchedule"),
        r(.english, "TV guide schedule", "TV Guide Schedule", "TV guide schedule", "tv guide schedule", "TV GUIDE SCHEDULE", "tvGuideSchedule", "TvGuideSchedule"),
    ]

    @Test func everyModeHasAtLeastOneHundredPairs() {
        #expect(Self.rows.count >= 100)
    }

    @Test(arguments: CaseMode.allCases)
    func caseModeMatchesExpectedPairs(mode: CaseMode) {
        for row in Self.rows {
            let words = WordTokenizer.words(row.input)
            let transformer = CaseTransformer(mode: mode, language: row.language, protectedWords: WordLists.builtInProtectedWords)
            let separator = mode.forcesNoWordSeparator ? "" : " "
            let output = transformer.apply(words).joined(separator: separator)
            #expect(output == row.expected(mode), "\(mode) of “\(row.input)” (\(row.language.rawValue))")
        }
    }

    @Test func userProtectedWordsKeepCasingOnlyInTitleSentenceAndAsGenerated() {
        let words = ["acme", "tools"]
        let protected = ["ACMEcorp", "AcMe"]
        #expect(CaseTransformer(mode: .title, language: .english, protectedWords: protected).apply(words) == ["AcMe", "Tools"])
        #expect(CaseTransformer(mode: .sentence, language: .english, protectedWords: protected).apply(words) == ["AcMe", "tools"])
        #expect(CaseTransformer(mode: .asGenerated, language: .english, protectedWords: protected).apply(words) == ["AcMe", "tools"])
        #expect(CaseTransformer(mode: .lowercase, language: .english, protectedWords: protected).apply(words) == ["acme", "tools"])
        #expect(CaseTransformer(mode: .uppercase, language: .english, protectedWords: protected).apply(words) == ["ACME", "TOOLS"])
        #expect(CaseTransformer(mode: .camel, language: .english, protectedWords: protected).apply(words) == ["acme", "Tools"])
        #expect(CaseTransformer(mode: .pascal, language: .english, protectedWords: protected).apply(words) == ["Acme", "Tools"])
    }
}
