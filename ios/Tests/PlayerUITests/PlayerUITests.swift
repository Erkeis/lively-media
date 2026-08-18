// [Intent] Unit tests verifying PlayerUI presets, color tokens, and navigation models
import XCTest
@testable import PlayerUI

final class PlayerUITests: XCTestCase {
    func testEqualizerPresetsCountAndGainRanges() {
        let presets = EqualizerPreset.standardPresets
        XCTAssertEqual(presets.count, 7)

        for preset in presets {
            XCTAssertEqual(preset.gains.count, 10, "Preset \(preset.name) must have exactly 10 bands")
            for gain in preset.gains {
                XCTAssertTrue(gain >= -12 && gain <= 12, "Gain \(gain) in \(preset.name) must be between -12dB and +12dB")
            }
        }
    }

    func testNavigationSectionsCountAndIcons() {
        let sections = NavigationSection.allCases
        XCTAssertEqual(sections.count, 7)
        for section in sections {
            XCTAssertFalse(section.iconName.isEmpty)
        }
    }
}
