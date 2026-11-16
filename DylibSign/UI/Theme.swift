import SwiftUI

/// Colours taken from the app icon: deep navy → teal gradient with a gold accent.
enum Theme {
    static let navy = Color(red: 0.08, green: 0.09, blue: 0.24)
    static let deep = Color(red: 0.04, green: 0.24, blue: 0.36)
    static let teal = Color(red: 0.00, green: 0.59, blue: 0.67)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.31)
    static let goldDeep = Color(red: 0.96, green: 0.62, blue: 0.16)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.42)

    static let card = Color.white.opacity(0.07)
    static let field = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.62)

    static let background = LinearGradient(
        colors: [navy, deep, teal.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [gold, goldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Card

struct StepCard<Content: View>: View {
    let step: Int
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.goldGradient)
                    Text("\(step)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.navy)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.gold.opacity(0.9))
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - File slot

struct FileSlot: View {
    let placeholder: String
    let hint: String
    let systemImage: String
    let file: URL?
    var isLoading = false
    let onPick: () -> Void
    var onClear: (() -> Void)? = nil

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(file == nil ? Color.white.opacity(0.08) : Theme.teal.opacity(0.35))
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: file == nil ? systemImage : "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(file == nil ? Theme.gold : .white)
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isLoading ? "جارٍ تجهيز الملف…" : (file?.lastPathComponent ?? placeholder))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.map(InjectorViewModel.sizeText) ?? hint)
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                if file != nil, let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(file == nil ? Theme.gold.opacity(0.45) : Theme.stroke,
                                  style: StrokeStyle(lineWidth: 1.2, dash: file == nil ? [6, 4] : []))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - File chip (list item)

struct FileChip: View {
    let url: URL
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.gold)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(InjectorViewModel.sizeText(url))
                    .font(.caption2)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.danger)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.danger.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var icon: String {
        switch url.pathExtension.lowercased() {
        case "deb": return "shippingbox.fill"
        case "framework", "bundle": return "folder.fill"
        default: return "puzzlepiece.extension.fill"
        }
    }
}

// MARK: - Add button

struct AddButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(Theme.gold)
                } else {
                    Image(systemName: "plus.circle.fill")
                }
                Text(isLoading ? "جارٍ التجهيز…" : title)
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(Theme.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Segmented choice

struct ChoicePicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundColor(selected ? Theme.navy : .white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Toggle row

struct OptionToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(Theme.secondaryText)
                }
            }
        }
        .tint(Theme.teal)
        .padding(.vertical, 2)
    }
}

// MARK: - Text field

struct StyledField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(Theme.gold.opacity(0.85))
                .frame(width: 20)
            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.field))
    }

    private var prompt: Text {
        Text(title).foregroundColor(Color.white.opacity(0.38))
    }
}
