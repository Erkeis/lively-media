// [Intent] Obsidian Studio SwiftUI color tokens, typography hierarchy, and style constants
import SwiftUI

public extension Color {
    static let obsidianBackground = Color(red: 11/255, green: 12/255, blue: 14/255) // #0B0C0E
    static let obsidianSurface = Color(red: 20/255, green: 22/255, blue: 26/255)    // #14161A
    static let obsidianElevated = Color(red: 30/255, green: 33/255, blue: 39/255)   // #1E2127
    static let obsidianBorder = Color(red: 40/255, green: 44/255, blue: 53/255)     // #282C35
    static let studioAmber = Color(red: 229/255, green: 169/255, blue: 60/255)      // #E5A93C
    static let studioSlate = Color(red: 142/255, green: 149/255, blue: 165/255)    // #8E95A5
    static let studioTextMuted = Color(red: 99/255, green: 107/255, blue: 120/255) // #636B78
}

public extension Font {
    static let studioLargeTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let studioSection = Font.system(size: 20, weight: .semibold, design: .default)
    static let studioBody = Font.system(size: 16, weight: .medium, design: .default)
    static let studioSecondary = Font.system(size: 14, weight: .regular, design: .default)
    static let studioCaption = Font.system(size: 12, weight: .regular, design: .default)
    static let studioMonoTime = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let studioMonoSpec = Font.system(size: 11, weight: .semibold, design: .monospaced)
}

public struct ObsidianCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(Color.obsidianElevated)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
    }
}

public extension View {
    func obsidianCard() -> some View {
        self.modifier(ObsidianCardModifier())
    }
}
