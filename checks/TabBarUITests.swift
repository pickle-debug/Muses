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
            XCTAssertTrue(app.buttons["手动录入 SKU"].waitForExistence(timeout: 3))
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
}
