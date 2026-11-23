import SwiftUI
import UniformTypeIdentifiers
import zlib

struct ContentView: View {
    @State private var selectedFileName: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var previewText: String = ""
    @State private var exportedFileURL: URL?
    @State private var showFileImporter: Bool = false
    @State private var showFileExporter: Bool = false
    @State private var txtDocument: TxtFileDocument?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Unggah template Excel Payroll BCA (.xlsx / .xlsm) untuk dikonversi menjadi file teks siap unggah.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Tombol Pilih & Proses File Excel
                    Button(action: {
                        showFileImporter = true
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text(selectedFileName.isEmpty ? "Pilih File Excel Payroll BCA" : selectedFileName)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text("Tap untuk membuka aplikasi Files")
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    // Kotak Status
                    if !statusMessage.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            Text(statusMessage)
                                .font(.footnote)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                        .foregroundColor(isError ? .red : .green)
                        .cornerRadius(10)
                    }

                    // Tombol Simpan & Salin jika berhasil
                    if !previewText.isEmpty {
                        Button(action: {
                            txtDocument = TxtFileDocument(text: previewText)
                            showFileExporter = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Simpan File TXT ke Files")
                                    .fontWeight(.bold)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button(action: {
                            UIPasteboard.general.string = previewText
                            statusMessage = "Seluruh isi file TXT berhasil disalin ke Clipboard."
                            isError = false
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Salin Semua Teks")
                                    .fontWeight(.semibold)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pratinjau Hasil Konversi:")
                                .font(.headline)
                            ScrollView(.horizontal) {
                                Text(previewText)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding()
                            }
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Payroll BCA")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: txtDocument,
                contentType: .plainText,
                defaultFilename: generateFileName()
            ) { result in
                switch result {
                case .success(let url):
                    statusMessage = "File berhasil disimpan: \(url.lastPathComponent)"
                    isError = false
                case .failure(let error):
                    statusMessage = "Gagal menyimpan file: \(error.localizedDescription)"
                    isError = true
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            statusMessage = "Gagal memilih file: \(error.localizedDescription)"
            isError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedFileName = url.lastPathComponent
            
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            
            do {
                let fileData = try Data(contentsOf: url)
                let converted = try NativeExcelParser.convertPayrollBCA(data: fileData)
                previewText = converted
                statusMessage = "Convert Berhasil! Siap disimpan (\(generateFileName()))."
                isError = false
            } catch {
                previewText = ""
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }

    private func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ddMMMyyyy_HHmmss"
        return "Payroll_BCA_\(formatter.string(from: Date())).txt"
    }
}

struct TxtFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Parser XLSX/XLSM Mandiri Menggunakan Zlib & XMLParser Bawaan iOS
enum PayrollError: LocalizedError {
    case invalidFile(String)
    case missingMandatory

    var errorDescription: String? {
        switch self {
        case .invalidFile(let msg): return msg
        case .missingMandatory: return "Silakan isi field mandatory (C3, C4, C5, C8, C9, C10) pada file Excel."
        }
    }
}

class NativeExcelParser {
    static func convertPayrollBCA(data: Data) throws -> String {
        let entries = try unzipEntries(data: data)
        
        var sharedStrings: [String] = []
        if let ssData = entries["xl/sharedStrings.xml"] {
            sharedStrings = SharedStringsXMLParser.parse(data: ssData)
        }

        // Cari sheet Payroll_BCA atau sheet pertama
        var targetSheetPath = "xl/worksheets/sheet1.xml"
        if let wbData = entries["xl/workbook.xml"], let relsData = entries["xl/_rels/workbook.xml.rels"] {
            if let foundPath = WorkbookResolver.findSheetPath(wbData: wbData, relsData: relsData, targetName: "Payroll_BCA") {
                targetSheetPath = foundPath
            }
        }

        guard let sheetData = entries[targetSheetPath] ?? entries.first(where: { $0.key.hasPrefix("xl/worksheets/sheet") && $0.key.hasSuffix(".xml") })?.value else {
            throw PayrollError.invalidFile("Worksheet tidak ditemukan dalam file Excel.")
        }

        let parsedSheet = SheetXMLParser.parse(data: sheetData, sharedStrings: sharedStrings)
        let cells = parsedSheet.cells

        func val(_ ref: String) -> String {
            return (cells[ref] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 1. Validasi Mandatory
        let corpID = val("C3")
        let srcAcct = val("C4")
        let feeAccount = val("C5")
        let effDate = val("C8")
        let effMonth = val("C9")
        let effYear = val("C10")

        if corpID.isEmpty || srcAcct.isEmpty || feeAccount.isEmpty || effDate.isEmpty || effMonth.isEmpty || effYear.isEmpty {
