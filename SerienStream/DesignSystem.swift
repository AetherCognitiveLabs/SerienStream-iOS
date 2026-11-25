import SwiftUI

enum DS {
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.055)
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.094)
    static let accent = Color(red: 0.267, green: 0.675, blue: 0.949) // #44ACF2 serienstream blue
    static let glassFill = Color.white.opacity(0.07)
    static let glassStroke = Color.white.opacity(0.14)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 14
}

struct GlassModifier: ViewModifier {
    var radius: CGFloat = DS.pillRadius
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.glassStroke, lineWidth: 1)
            )
    }
}

extension View {
    func glass(radius: CGFloat = DS.pillRadius) -> some View {
        modifier(GlassModifier(radius: radius))
    }
}

struct CoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = DS.cardRadius

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay(ProgressView().tint(DS.textTertiary))
            @unknown default:
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DS.glassStroke, lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DS.bgElevated)
            .overlay(
                Image(systemName: "tv")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(DS.textTertiary)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundColor(DS.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(DS.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glass(radius: 10)
    }
}
