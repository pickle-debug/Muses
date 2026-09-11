import Foundation

struct SKUImportRow: Sendable {
    let sku: String
    let name: String
    let sellingPoint: String
}

enum SKUImport {
    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumRows = 500

    static func parse(_ data: Data, fileExtension: String) throws -> [SKUImportRow] {
        guard data.count <= maximumBytes else {
            throw AppError.safe("SKU_IMPORT_FILE_TOO_LARGE", "导入文件不能超过 2MB")
        }

        let fileType = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch fileType {
        case "csv", "tsv":
            guard var text = String(data: data, encoding: .utf8) else {
                throw AppError.safe("SKU_IMPORT_ENCODING_INVALID", "导入文件必须为 UTF-8 编码")
            }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return try parseDelimited(text, separator: fileType == "csv" ? "," : "\t")
        case "json":
            return try parseJSON(data)
        default:
            throw AppError.safe("SKU_IMPORT_FILE_TYPE_INVALID", "仅支持 CSV、TSV 或 JSON 文件")
        }
    }

    private struct JSONRow: Decodable {
        let sku: String?
        let name: String?
        let sellingPoint: String?
    }

    private static func parseJSON(_ data: Data) throws -> [SKUImportRow] {
        let values: [JSONRow]
        do {
            values = try JSONDecoder().decode([JSONRow].self, from: data)
        } catch {
            throw AppError.safe("SKU_IMPORT_JSON_INVALID", "JSON 文件格式不正确，应为商品数组")
        }
        return try validate(values.enumerated().map { index, value in
            (index + 1, [value.sku ?? "", value.name ?? "", value.sellingPoint ?? ""])
        })
    }

    private static func parseDelimited(_ text: String, separator: Character) throws -> [SKUImportRow] {
        let records = try csvRecords(text, separator: separator)
        guard let header = records.first else {
            throw AppError.safe("SKU_IMPORT_HEADER_MISSING", "导入文件缺少表头")
        }
        let headers = header.fields.map(normalizeHeader)
        guard let skuIndex = headers.firstIndex(of: "sku"),
              let nameIndex = headers.firstIndex(of: "name"),
              let sellingPointIndex = headers.firstIndex(of: "sellingpoint") else {
            throw AppError.safe("SKU_IMPORT_COLUMN_MISSING", "表头必须包含 SKU、商品名称和卖点")
        }
        guard Set(headers).count == headers.count else {
            throw AppError.safe("SKU_IMPORT_HEADER_INVALID", "表头不能包含重复列")
        }

        let requiredWidth = header.fields.count
        let rows = records.dropFirst().filter { !$0.fields.allSatisfy { $0.isEmpty } }
        let mapped: [(Int, [String])] = try rows.map { record in
            guard record.fields.count == requiredWidth else {
                throw AppError.safe("SKU_IMPORT_ROW_LENGTH_INVALID", "第 \(record.line) 行的列数与表头不一致")
            }
            return (record.line, [record.fields[skuIndex], record.fields[nameIndex], record.fields[sellingPointIndex]])
        }
        return try validate(mapped)
    }

    private static func validate(_ values: [(Int, [String])]) throws -> [SKUImportRow] {
        guard !values.isEmpty else {
            throw AppError.safe("SKU_IMPORT_EMPTY", "文件中没有可导入的商品。")
        }
        guard values.count <= maximumRows else {
            throw AppError.safe("SKU_IMPORT_ROW_LIMIT", "一次最多导入 500 个商品")
        }
        var seen = Set<String>()
        return try values.map { line, fields in
            let clean = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard clean.count == 3, clean.allSatisfy({ !$0.isEmpty }) else {
                throw AppError.safe("SKU_IMPORT_FIELD_EMPTY", "第 \(line) 行的 SKU、商品名称和卖点均不能为空")
            }
            let key = clean[0].folding(options: [.caseInsensitive], locale: .current)
            guard seen.insert(key).inserted else {
                throw AppError.safe("SKU_IMPORT_SKU_DUPLICATE", "第 \(line) 行的 SKU 与文件内其他商品重复")
            }
            return SKUImportRow(sku: clean[0], name: clean[1], sellingPoint: clean[2])
        }
    }

    private static func normalizeHeader(_ header: String) -> String {
        let value = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "商品名称": return "name"
        case "卖点", "真实卖点": return "sellingpoint"
        default: return value
        }
    }

    private struct DelimitedRecord {
        let line: Int
        let fields: [String]
    }

    private static func csvRecords(_ text: String, separator: Character) throws -> [DelimitedRecord] {
        var result: [DelimitedRecord] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var afterQuote = false
        var atFieldStart = true
        var line = 1
        var recordLine = 1
        let characters = Array(text)
        var index = 0

        func finishRecord() {
            fields.append(field)
            result.append(DelimitedRecord(line: recordLine, fields: fields))
            fields = []; field = ""; atFieldStart = true; recordLine = line + 1
        }

        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count {
                        let next = characters[index + 1]
                        if next == "\"" { field.append("\""); index += 1 }
                        else { quoted = false; afterQuote = true }
                    } else { quoted = false; afterQuote = true }
                } else if character.isNewline {
                    field.append("\n"); line += 1
                } else { field.append(character); if character == "\n" { line += 1 } }
            } else {
                if afterQuote {
                    guard character == separator || character.isNewline else {
                        throw AppError.safe("SKU_IMPORT_CSV_INVALID", "CSV 引号格式不正确")
                    }
                    afterQuote = false
                }
                if character == separator { fields.append(field); field = ""; atFieldStart = true }
                else if character.isNewline {
                    finishRecord(); line += 1; recordLine = line
                } else if character == "\"" {
                    guard atFieldStart else { throw AppError.safe("SKU_IMPORT_CSV_INVALID", "CSV 引号格式不正确") }
                    quoted = true; atFieldStart = false
                } else { field.append(character); atFieldStart = false }
            }
            index += 1
        }
        guard !quoted else { throw AppError.safe("SKU_IMPORT_CSV_INVALID", "CSV 引号格式不正确") }
        if !fields.isEmpty || !field.isEmpty || !atFieldStart { finishRecord() }
        return result
    }
}
