import XCTest

final class TabBarUITests: XCTestCase {
    @MainActor
    func testNativeTabScrubbing() {
        let app = XCUIApplication(bundleIdentifier: "com.ordoeden.muses")
        app.launch()
        let selection = app.buttons["workspace.tab.AI选品"]
        let products = app.buttons["workspace.tab.我的商品"]
        let sales = app.buttons["workspace.tab.销售跟进"]
        let settings = app.buttons["workspace.tab.个人设置"]
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        selection.tap()
        let left = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let next = products.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        left.press(forDuration: 0.35, thenDragTo: next)
        XCTAssertTrue(products.isSelected, "拖动滑块应选中我的商品")
        let farRight = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        next.press(forDuration: 0.35, thenDragTo: farRight)
        XCTAssertTrue(settings.isSelected, "滑块应可跨过中间发布按钮")
        farRight.press(forDuration: 0.35, thenDragTo: sales.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(sales.isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native tabbar after scrubbing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRaisedPublishButtonAndTabSwitching() {
        let app = XCUIApplication(bundleIdentifier: "com.ordoeden.muses")
        app.launch()
        let publish = app.buttons["workspace.tab.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "workspace.tab.publish").count, 1)
        XCTAssertEqual(publish.frame.width, 60, accuracy: 1)
        XCTAssertEqual(publish.frame.height, 60, accuracy: 1)
        for title in ["AI选品", "我的商品", "销售跟进", "个人设置"] {
            let tab = app.buttons["workspace.tab.\(title)"]
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            XCTAssertFalse(publish.isSelected)
            // Tap the cap above the capsule, not the part inside the bar.
            XCTAssertLessThan(publish.frame.minY + 6, tab.frame.minY - 6)
            publish.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(app.buttons["workspace.publish.photos"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["workspace.publish.photos"].label.contains("从相册选择"))
            XCTAssertTrue(app.buttons["workspace.publish.smart"].isHittable)
            XCTAssertTrue(app.buttons["workspace.publish.camera"].isHittable)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            app.buttons["workspace.publish.close"].tap()
            XCTAssertTrue(tab.waitForExistence(timeout: 3))
            XCTAssertTrue(tab.isSelected, "关闭发布工作台后应回到原 tab")
            XCTAssertFalse(app.buttons["workspace.publish-slot"].isSelected)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Liquid Glass tabbar — raised publish button"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSmartRecognitionSheetInput() {
        let app = XCUIApplication(bundleIdentifier: "com.ordoeden.muses")
        app.launch()
        let publish = app.buttons["workspace.tab.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 10))
        let products = app.buttons["workspace.tab.我的商品"]
        products.tap()
        publish.tap()
        let smart = app.buttons["workspace.publish.smart"]
        XCTAssertTrue(smart.waitForExistence(timeout: 3))
        smart.tap()

        let input = app.textViews["workspace.publish.smart.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["workspace.publish.photos"].exists, "输入 sheet 打开后应收起悬浮菜单")
        let recognize = app.buttons["workspace.publish.smart.recognize"]
        XCTAssertFalse(recognize.isEnabled, "空输入时应禁用识别按钮")
        input.tap()
        input.typeText("https://example.com/product")
        XCTAssertTrue(recognize.isEnabled)

        app.buttons["workspace.publish.smart.close"].tap()
        XCTAssertTrue(products.waitForExistence(timeout: 3))
        XCTAssertTrue(products.isSelected)
        publish.tap()
        XCTAssertTrue(app.buttons["workspace.publish.smart"].waitForExistence(timeout: 3))
        app.buttons["workspace.publish.close"].tap()
    }

    @MainActor
    func testSKUEntryPhotoRowAndNameValidation() {
        let app = XCUIApplication(bundleIdentifier: "com.ordoeden.muses")
        app.launch()
        let products = app.buttons["workspace.tab.我的商品"]
        XCTAssertTrue(products.waitForExistence(timeout: 10))
        products.tap()
        app.buttons["新建"].tap()
        let firstSlot = app.buttons["sku.photo.add.1"]
        XCTAssertTrue(firstSlot.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["workspace.tab.publish"].exists, "添加商品页不应显示发布按钮")
        for title in ["AI选品", "我的商品", "销售跟进", "个人设置"] {
            XCTAssertFalse(app.buttons["workspace.tab.\(title)"].exists, "添加商品页不应显示 TabBar")
        }
        XCTAssertEqual(firstSlot.frame.width, firstSlot.frame.height, accuracy: 1)
        for index in 2...9 {
            XCTAssertFalse(app.buttons["sku.photo.add.\(index)"].exists, "只显示一个添加框")
        }
        let photoRow = app.scrollViews["sku.photos.row"]
        XCTAssertTrue(photoRow.exists)
        XCTAssertEqual(app.scrollViews.count, 1, "只有图片区域可以横向滚动")
        XCTAssertFalse(app.buttons["sku.photos.files"].exists)
        XCTAssertEqual(app.textFields.count, 1, "仅输入商品名称")
        XCTAssertFalse(app.buttons["sku.save"].isEnabled)
        XCTAssertFalse(app.buttons["sku.recognize"].exists)

        let field = app.textFields["sku.input.name"]
        XCTAssertTrue(field.isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.minY, photoRow.frame.maxY)
        let fieldY = field.frame.minY
        photoRow.swipeUp()
        XCTAssertEqual(field.frame.minY, fieldY, accuracy: 1, "页面不能纵向滚动")
        field.tap()
        field.typeText("Glass cup")
        app.buttons["sku.input.done"].tap()
        XCTAssertTrue(app.buttons["sku.save"].isEnabled, "只填商品名称即可保存")
        XCTAssertFalse(app.buttons["workspace.tab.publish"].exists, "收起键盘后仍应保持全屏")
        XCTAssertFalse(app.buttons["sku.recognize"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SKU entry — photo row and name"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["sku.save"].tap()
        let savedName = app.staticTexts["sku.detail.name"]
        XCTAssertTrue(savedName.waitForExistence(timeout: 3))
        XCTAssertEqual(savedName.label, "Glass cup")
        app.buttons["sku.detail.edit"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["workspace.tab.publish"].exists, "编辑商品也应保持全屏")
        XCTAssertEqual(field.value as? String, "Glass cup")
        app.buttons["sku.back"].tap()
        XCTAssertTrue(products.waitForExistence(timeout: 3))
        XCTAssertTrue(products.isSelected)
        XCTAssertTrue(app.buttons["workspace.tab.publish"].isHittable, "返回商品列表后恢复 TabBar")
    }
}
