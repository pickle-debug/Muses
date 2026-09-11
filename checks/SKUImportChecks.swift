import Foundation

@main
struct SKUImportChecks {
    static func main() throws {
        let csv = "\u{FEFF}SKU,商品名称,卖点\r\nA1,\"名称, 一\",\"第一行\n第二行\"\r\n"
        let csvRows = try SKUImport.parse(Data(csv.utf8), fileExtension: "csv")
        assert(csvRows.count == 1 && csvRows[0].name == "名称, 一" && csvRows[0].sellingPoint == "第一行\n第二行")

        let tsv = try SKUImport.parse(Data("sku\tname\tsellingPoint\r\nT1\t杯子\t\"带\"\"刻度\"\"\"".utf8), fileExtension: "tsv")
        assert(tsv[0].sellingPoint == "带\"刻度\"")
        let json = "[{\"sku\":\"B2\",\"name\":\"商品\",\"sellingPoint\":\"卖点\"}]"
        let jsonRows = try SKUImport.parse(Data(json.utf8), fileExtension: "json")
        assert(jsonRows.count == 1)

        for bad in ["sku,name,sellingPoint\nA,a,x\na,a,y", "sku,name,sellingPoint\nA,,x", "sku,name,sellingPoint\n\"A,a,x"] {
            do { _ = try SKUImport.parse(Data(bad.utf8), fileExtension: "csv"); assertionFailure("应拒绝无效 CSV") }
            catch let error as AppError { assert(!error.userMessage.isEmpty) }
        }
        let legacy = "{\"id\":\"11111111-1111-1111-1111-111111111111\",\"productSnapshotID\":\"22222222-2222-2222-2222-222222222222\",\"platform\":\"xiaohongshu\",\"template\":\"handheld_lifestyle_v1\",\"status\":\"ready\",\"createdAt\":0,\"updatedAt\":0}"
        let creation = try JSONDecoder().decode(Creation.self, from: Data(legacy.utf8))
        assert(creation.versionNumber == nil && creation.tracking == nil && creation.isPreview == nil)
        var metrics = PostMetrics(views: 1000, likes: 5, saves: 2, comments: 1, inquiries: 10, orders: 3, revenue: 99.9, note: "")
        try metrics.validate()
        assert(metrics.conversionRate == 0.003)
        metrics.views = 0
        assert(metrics.conversionRate == nil)
        metrics.orders = -1
        do { try metrics.validate(); assertionFailure("负数必须拒绝") } catch {}
        print("IMPORT AND MODEL CHECKS PASSED")
    }
}
