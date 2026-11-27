import Testing
@testable import NomenCore

/// D5: the generic-name detector is 100% correct on ≥ 400 names, including every macOS
/// language's screenshot name.
struct GenericNameTests {
    /// macOS default screenshot names, with {d} for the date and {t} for the time.
    static let screenshotTemplates: [String] = [
        "Screenshot {d} at {t}", "Screen Shot {d} at {t}", "Bildschirmfoto {d} um {t}", "Capture d’écran {d} à {t}",
        "Capture d'écran {d} à {t}", "Captura de pantalla {d} a las {t}", "Captura de pantalla {d} a les {t}",
        "Istantanea schermo {d} alle {t}", "Schermata {d} alle {t}", "Captura de Tela {d} às {t}", "Captura de ecrã {d} às {t}",
        "Schermafbeelding {d} om {t}", "Skärmavbild {d} kl. {t}", "Skærmbillede {d} kl. {t}", "Skjermbilde {d} kl. {t}",
        "Näyttökuva {d} kello {t}", "Snímek obrazovky {d} v {t}", "Snímka obrazovky {d} o {t}", "Zrzut ekranu {d} o {t}",
        "Képernyőfotó {d} - {t}", "Captură de ecran {d} la {t}", "Snimka zaslona {d} u {t}", "Ekran Resmi {d} {t}",
        "Ekran Görüntüsü {d} {t}", "Снимок экрана {d} в {t}", "Знімок екрана {d} о {t}", "Στιγμιότυπο οθόνης {d}, {t}",
        "צילום מסך {d} ב-{t}", "لقطة شاشة {d} في {t}", "ภาพหน้าจอ {d} เวลา {t}", "Ảnh màn hình {d} lúc {t}",
        "Cuplikan Layar {d} pukul {t}", "Tangkapan Layar {d} pukul {t}", "Tangkapan Skrin {d} pada {t}",
        "スクリーンショット {d} {t}", "截屏{d} {t}", "螢幕截圖 {d} {t}", "스크린샷 {d} {t}", "स्क्रीनशॉट {d} को {t}",
    ]

    static let recordingTemplates: [String] = [
        "Screen Recording {d} at {t}", "Bildschirmaufnahme {d} um {t}", "Enregistrement de l’écran {d} à {t}",
        "Grabación de pantalla {d} a las {t}", "Registrazione schermo {d} alle {t}", "Gravação de Tela {d} às {t}",
        "Schermopname {d} om {t}", "Запись экрана {d} в {t}", "画面収録 {d} {t}", "录屏{d} {t}", "화면 기록 {d} {t}",
    ]

    static let times = ["14.05.12", "2.05.12 PM", "09.41.00", "11.59.59 AM", "下午2.05.12", "오후 2.05.12", "2.05.12 μ.μ."]
    static let dates = ["2026-11-27", "2025-01-03", "2569-11-27"]

    static var screenshotNames: [String] {
        var names: [String] = []
        for (index, template) in screenshotTemplates.enumerated() {
            for variant in 0..<5 {
                let date = dates[(index + variant) % 2]
                let time = times[(index + variant) % times.count]
                names.append(template.replacingOccurrences(of: "{d}", with: date).replacingOccurrences(of: "{t}", with: time) + ".png")
            }
        }
        names.append("ภาพหน้าจอ 2569-11-27 เวลา 14.05.12.png")
        names.append("Screenshot 2026-11-27 at 14.05.12 (2).png")
        names.append("Screenshot_20261127-140512_Chrome.jpg")
        names.append("Screenshot_2026-11-27-14-05-12-123_com.android.chrome.jpg")
        return names
    }

    static var recordingNames: [String] {
        recordingTemplates.map {
            $0.replacingOccurrences(of: "{d}", with: "2026-11-27").replacingOccurrences(of: "{t}", with: "14.05.12") + ".mov"
        }
    }

    static let otherGeneric: [String] = [
        // cameras and phones
        "IMG_0001.JPG", "IMG_1234.HEIC", "IMG_E1234.JPG", "IMG_1234 (1).jpg", "IMG_1234-edited.jpg", "IMG_1234 copy.jpg",
        "DSC_0001.JPG", "DSCN0042.JPG", "DSCF1234.JPG", "_DSC1234.NEF", "PXL_20261127_140512345.jpg",
        "PXL_20261127_140512345.MP.jpg", "GOPR0001.JPG", "GH010001.MP4", "DJI_0001.JPG", "MVIMG_20261127_140512.jpg",
        "VID_20261127_140512.mp4", "P1010001.JPG", "CIMG0001.JPG", "IMAG0001.jpg", "image0.jpeg", "image (3).png",
        "FullSizeRender.jpg", "Photo 27-11-2026, 14 05 12.jpg", "Photo on 27-11-2026 at 14.05.jpg", "PANO_20261127_140512.jpg",
        "IMG-20261127-WA0001.jpg", "photo_2026-11-27_14-05-12.jpg", "Photo Nov 27 2026.jpeg", "IMG_20261127_140512.jpg",
        // messaging
        "WhatsApp Image 2026-11-27 at 14.05.12.jpeg", "WhatsApp Image 2026-11-27 at 14.05.12 (1).jpeg",
        "WhatsApp Video 2026-11-27 at 14.05.12.mp4", "signal-2026-11-27-140512.jpg", "signal-attachment-2026-11-27-140512.jpeg",
        "telegram-cloud-photo-size-2-5381.jpg", "attachment.pdf", "attachment-1.pdf", "Attachments.zip",
        // scanners
        "scan0001.pdf", "Scan.pdf", "Scan 1.pdf", "Scan 2026-11-27.pdf", "Scanned Document.pdf", "Scanned Document 2.pdf",
        "scan_20261127_140512.pdf", "doc00012320261127.pdf", "CCF_000123.pdf", "SKMBT_C22426112714050.pdf", "EPSON001.JPG",
        "HP Scan 2026-11-27.pdf", "Scan 27 Nov 2026.pdf", "BRN3C2AF41234AB_000123.pdf", "Scan 27. November 2026.pdf",
        // generic words in several languages
        "document.pdf", "document (3).pdf", "Document1.docx", "file.pdf", "file (1).pdf", "download.pdf", "download (2).pdf",
        "untitled.txt", "Untitled 2.png", "Untitled-1.psd", "image.png", "unnamed.jpg", "unnamed (1).jpg", "export.csv",
        "Export-2026-11-27.xlsx", "output.pdf", "Unbenannt.txt", "Unbenannt 3.rtf", "Sans titre.txt", "Sin título.docx",
        "Senza titolo.txt", "Sem título.png", "Naamloos.txt", "無題.txt", "名称未設定.txt", "未命名.txt", "제목 없음.txt",
        "copy.pdf", "Kopie.pdf", "new document.docx", "Neues Dokument.txt", "Nouveau document.docx", "Presentation1.pptx",
        "Book1.xlsx", "Doc1.docx", "index.html", "final.pdf", "Bild.jpg", "imagen.png", "immagine.jpg", "afbeelding.png",
        "画像.png", "图片.png", "이미지.png", "Datei.pdf", "Fichier.txt", "archivo.pdf", "Bestand.txt",
        // identifiers and numbers
        "3f2a9c1e-5b7d-4e8f-9a1b-2c3d4e5f6a7b.pdf", "3F2A9C1E-5B7D-4E8F-9A1B-2C3D4E5F6A7B.jpg",
        "3f2a9c1e-5b7d-4e8f-9a1b-2c3d4e5f6a7b (1).pdf", "a3f9c2e1b7d4.png", "5f3e2a1b9c8d7e6f.jpg", "20261127.pdf",
        "2026-11-27.pdf", "27.11.2026 14.05.pdf", "1234.jpg", "0001.png", "2026-11-27_140512.png", "1700000000123.pdf",
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.pdf",
    ]

    static let wellNamed: [String] = [
        "2026-11-27 Swisscom Invoice Mobile Subscription November.pdf", "Tax return 2025.pdf", "Lease agreement.pdf",
        "CV John Smith.pdf", "Holiday photos Lisbon.jpg", "Q3 Board Presentation.key", "Rechnung Swisscom November.pdf",
        "Facture EDF octobre.pdf", "Flight booking Zurich Lisbon.pdf", "Wedding invitation.png", "Meeting notes.md",
        "Project Apollo plan.pages", "東京タワー.jpg", "東京.jpg", "富士山.png", "Invoice.pdf", "Invoice (1).pdf",
        "IMG_1234 Hawaii.jpg", "Screenshot of bug in Xcode.png", "Scan of passport.pdf", "Photo Booth Image.jpg",
        "Untitled design.png", "Mom's birthday.jpg", "Budget 2026.numbers", "Kontoauszug Oktober.pdf",
        "Relevé de compte.pdf", "Estratto conto gennaio.pdf", "Contrato de alquiler.pdf", "Recibo de luz.pdf",
        "Huurcontract.pdf", "請求書 アマゾン.pdf", "청구서 통신사.pdf", "发票 中国移动.pdf", "Отчёт за год.docx",
        "Ελληνικές σημειώσεις.txt", "דוח שנתי.pdf", "تقرير سنوي.pdf", "Recipe pancakes.txt", "Map of Paris.png",
        "Error message Xcode build.png", "Boarding pass LX 1234.pdf", "Concert tickets.pdf", "Car insurance 2026.pdf",
        "Swisscom.pdf", "README.md", "Notes.txt", "Research summary.docx", "Cat.jpg", "Dog walking schedule.xlsx",
        "WhatsApp chat with Anna.txt", "Signal safety numbers.txt", "Scanner manual Epson.pdf", "Download speed test.png",
        "Document management plan.docx", "Export pricing 2026.xlsx", "Final exam answers.pdf", "Copy editing guide.pdf",
        "Image rights agreement.pdf", "Screen protector receipt.pdf", "Recording studio booking.pdf", "Photo contest rules.pdf",
        "Index of terms.pdf", "Untitled song lyrics.txt", "IMG_1234 sunset over the lake.jpg", "DSC_0001 Grandma.jpg",
        "Scan 2026-11-27 lease.pdf", "Screenshot 2026-11-27 Slack thread.png", "2026-11-27 Arzttermin.pdf",
        "Hike.gpx", "Zoo.jpg", "Bob.png", "Ana.txt", "Eva.docx",
        "Lisbon itinerary.pdf", "Kitchen renovation quote.pdf", "Pension statement 2025.pdf", "Gym membership.pdf",
        "Dentist appointment.pdf", "Payslip November.pdf", "Electricity bill autumn.pdf", "Birth certificate.pdf",
        "Passport renewal form.pdf", "Driving licence scan.jpg", "Apartment floor plan.png", "Wifi router manual.pdf",
        "Team offsite agenda.docx", "Quarterly sales report.xlsx", "Brand guidelines.key", "Logo final version.png",
        "Garden design sketch.jpg", "Bike repair receipt.pdf", "Rental deposit return.pdf", "School report Emma.pdf",
        "Vaccination record.pdf", "Health insurance card.png", "Train ticket Geneva.pdf", "Hotel booking Rome.pdf",
        "Concert poster.png", "Wine list.pdf", "Wedding speech draft.docx", "Grocery list.txt", "Packing list.md",
        "Mortgage offer.pdf", "Car service invoice.pdf", "Parking fine.pdf", "Museum tickets.pdf", "Recipe lasagne.pdf",
        "Swimming course schedule.pdf", "Piano sheet music.pdf", "Yoga timetable.png", "Jacket return label.pdf",
        "Phone contract.pdf", "Laptop warranty.pdf", "Thank you card.png", "Holiday rota.xlsx", "Invoice Swisscom.pdf",
        "Rechnung Strom.pdf", "Facture eau.pdf", "Bolletta gas.pdf", "Factura teléfono.pdf", "Conta de luz.pdf",
    ]

    static var allCases: [(String, Bool)] {
        screenshotNames.map { ($0, true) } + recordingNames.map { ($0, true) } + otherGeneric.map { ($0, true) }
            + wellNamed.map { ($0, false) }
    }

    @Test func atLeastFourHundredNames() {
        #expect(Self.allCases.count >= 400, "\(Self.allCases.count)")
    }

    @Test func detectorIsCorrectOnEveryName() {
        let detector = GenericNameDetector()
        for (name, expected) in Self.allCases {
            #expect(detector.isGeneric(name) == expected, "\(name) should\(expected ? "" : " not") be generic")
        }
    }

    @Test func screenshotNamesAreRecognizedAsScreenshots() {
        for name in Self.screenshotNames {
            let match = ScreenshotName.parse(name)
            #expect(match != nil, "\(name)")
            #expect(match?.isRecording == false, "\(name)")
        }
        for name in Self.recordingNames {
            #expect(ScreenshotName.parse(name)?.isRecording == true, "\(name)")
        }
        #expect(ScreenshotName.parse("Screenshot of bug in Xcode.png") == nil)
        #expect(ScreenshotName.parse("Invoice.pdf") == nil)
    }

    @Test func captureTimeIsReadFromTheName() {
        #expect(ScreenshotName.parse("Screenshot 2026-11-27 at 14.05.12.png")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        #expect(ScreenshotName.parse("Screenshot 2026-11-27 at 2.05.12 PM.png")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        #expect(ScreenshotName.parse("Screenshot 2026-11-27 at 12.30.00 AM.png")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 0, minute: 30))
        #expect(ScreenshotName.parse("스크린샷 2026-11-27 오후 2.05.12.png")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        #expect(ScreenshotName.parse("ภาพหน้าจอ 2569-11-27 เวลา 14.05.12.png")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
        #expect(ScreenshotName.parse("Screenshot_20261127-140512_Chrome.jpg")?.captureDate == DateValue(year: 2026, month: 11, day: 27, hour: 14, minute: 5))
    }

    @Test func userPatternsAndStrippedOriginal() {
        let detector = GenericNameDetector(userPatterns: ["Report-*", "export_??"])
        #expect(detector.isGeneric("Report-2026-Q3.pdf"))
        #expect(detector.isGeneric("EXPORT_ab.csv"))
        #expect(!detector.isGeneric("Quarterly report.pdf"))
        #expect(detector.strippedOriginal("IMG_1234 Hawaii.jpg") == "Hawaii")
        #expect(detector.strippedOriginal("Screenshot 2026-11-27 at 14.05.12.png") == nil)
        #expect(detector.strippedOriginal("Capture d’écran 2026-11-27 à 14.05.12.png") == nil)
        #expect(detector.strippedOriginal("Invoice (1).pdf") == "Invoice")
        #expect(detector.strippedOriginal("scan0001 lease contract.pdf") == "lease contract")
    }
}
