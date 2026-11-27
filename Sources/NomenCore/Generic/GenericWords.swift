/// Word lists behind the generic-name detector (3.6) and screenshot detection (3.7).
/// Entries are folded (lowercase, accents removed) when the sets are built.
enum GenericWords {
    /// System screenshot names in macOS languages (and Android/Windows defaults).
    static let screenshotTerms: [String] = [
        // English, older macOS
        "screenshot", "screen", "shot", "screenshots",
        // German, French, Spanish, Catalan, Italian, Portuguese
        "bildschirmfoto", "capture", "d", "l", "écran", "decran", "captura", "pantalla",
        "schermata", "istantanea", "schermo", "tela", "ecrã",
        // Dutch, Nordic, Finnish
        "schermafbeelding", "skärmavbild", "skærmbillede", "skjermbilde", "näyttökuva", "skjáskot",
        // Slavic, Baltic, Hungarian, Romanian, Turkish, Greek
        "снимок", "экрана", "знімок", "екрана", "zrzut", "ekranu", "snímek", "snímka", "obrazovky",
        "snimka", "zaslona", "snimak", "ekrana", "posnetek", "zaslona", "képernyőfotó", "kepernyofoto",
        "ekrano", "kopija", "ekrānuzņēmums", "ekraanipilt", "ekraanitõmmis", "captură", "ecran",
        "ekran", "resmi", "görüntüsü", "στιγμιότυπο", "οθόνης", "екранна", "снимка",
        // Hebrew, Arabic, Persian, Hindi, Thai, Vietnamese, Indonesian, Malay
        "צילום", "מסך", "لقطة", "شاشة", "اسکرین", "شات", "स्क्रीनशॉट", "ภาพหน้าจอ", "ảnh", "màn", "hình",
        "tangkapan", "cuplikan", "layar", "skrin", "gambar", "petikan",
        // Japanese, Chinese, Korean
        "スクリーンショット", "画面", "截屏", "截图", "屏幕截图", "螢幕截圖", "螢幕擷圖", "擷取畫面", "스크린샷", "화면",
    ]

    /// Screen recording names. Recordings are video files and never eligible; the words
    /// are listed so their names count as generic for explicit requests.
    static let recordingTerms: [String] = [
        "recording", "bildschirmaufnahme", "enregistrement", "grabación", "gravação", "gravacao",
        "registrazione", "schermopname", "skärminspelning", "запись", "画面収録", "录屏", "屏幕录制",
        "기록", "녹화",
    ]

    /// Connectors and time markers that appear in default names ("at", "um", "à", "a las", PM).
    static let connectors: [String] = [
        "at", "um", "à", "a", "las", "les", "alle", "om", "às", "kl", "kello", "klo", "o", "v", "в",
        "о", "u", "la", "de", "da", "del", "di", "do", "on", "lúc", "pukul", "pada", "ב", "في", "को",
        "เวลา", "am", "pm", "a.m", "p.m", "μ", "μμ", "πμ", "م", "ص", "下午", "上午", "午後", "午前",
        "오후", "오전", "kell", "в", "pe", "ob", "um", "at", "the", "of", "from",
    ]

    /// Camera, phone and app counters: IMG_1234, DSC_0001, PXL_…, GOPR0001.
    static let cameraPrefixesList: [String] = [
        "img", "image", "dsc", "dscn", "dscf", "dsc_", "sam", "pxl", "gopr", "gh", "gx", "dji",
        "mvimg", "vid", "video", "pict", "cimg", "imag", "dcim", "wp", "photo", "pic", "picture",
        "mov", "clip", "hpim", "kimg", "mvc", "pano", "burst", "live", "portrait", "edited", "e",
    ]
    static let cameraPrefixes: Set<String> = Set(cameraPrefixesList)

    /// Messaging exports, scanners and generic file words in several languages.
    static let fileTerms: [String] = [
        // messaging
        "whatsapp", "wa", "telegram", "signal", "attachment", "attachments", "imessage", "messenger",
        "viber", "line", "wechat", "微信", "kakaotalk",
        // scanners
        "scan", "scans", "scanned", "scanner", "scansione", "numérisation", "escaneo", "digitalização",
        "doc", "ccf", "skmbt", "epson", "hp", "canon", "brother", "brn", "xerox", "ricoh", "kyocera",
        "konica", "sharp", "lexmark", "mfp", "scanjet", "imagerunner",
        // generic file words
        "document", "documents", "dokument", "documento", "documenten", "file", "files", "fichier",
        "datei", "archivo", "arquivo", "bestand", "download", "downloads", "untitled", "unbenannt",
        "sans", "titre", "senza", "titolo", "sin", "título", "titulo", "sem", "naamloos", "zonder",
        "titel", "без", "названия", "無題", "名称未設定", "未命名", "제목", "없음", "image", "images",
        "bild", "imagen", "immagine", "imagem", "afbeelding", "画像", "图片", "이미지", "unnamed",
        "export", "exported", "output", "untitled", "copy", "kopie", "copie", "copia", "cópia",
        "コピー", "副本", "사본", "new", "neu", "nouveau", "nouvelle", "nuevo", "nueva", "nuovo",
        "nuova", "novo", "nova", "nieuw", "nieuwe", "fullsizerender", "photo", "photos", "foto",
        "fotos", "picture", "pictures", "pic", "img", "dsc", "temp", "tmp", "index", "default",
        "book", "presentation", "doc", "item", "upload", "uploaded", "edited", "edit", "final",
    ]

    static let all: Set<String> = {
        var set: Set<String> = []
        for list in [screenshotTerms, recordingTerms, connectors, cameraPrefixesList, fileTerms] {
            for word in list { set.insert(TextFolding.key(word)) }
        }
        return set
    }()

    static let screenshot: Set<String> = Set(screenshotTerms.map(TextFolding.key))
    static let recording: Set<String> = Set(recordingTerms.map(TextFolding.key))
}
