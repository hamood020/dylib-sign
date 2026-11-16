import SwiftUI
import UIKit

/// Explains how to get a decrypted IPA through Telegram decrypt bots.
struct IPAGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPickFile: () -> Void

    private struct Bot: Identifiable {
        let username: String
        let title: String
        var id: String { username }
    }

    private let bots = [
        Bot(username: "eeveedecrypterbot", title: "البوت الأول"),
        Bot(username: "FastDecryptBot", title: "البوت الثاني"),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("كيف أحصل على ملف IPA؟")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundColor(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .accessibilityLabel("إغلاق")
                    }

                    Text("التطبيقات المثبّتة من App Store مشفّرة ولا يمكن حقنها. استخدم أحد بوتات تلجرام لاستخراج نسخة مفكوكة التشفير.")
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        stepRow(1, "افتح App Store وابحث عن التطبيق.")
                        stepRow(2, "اضغط زر المشاركة ثم «نسخ الرابط».")
                        stepRow(3, "افتح أحد البوتات بالأسفل وأرسل له الرابط.")
                        stepRow(4, "سيرسل لك البوت ملف IPA — احفظه في تطبيق الملفات.")
                        stepRow(5, "ارجع هنا واضغط «اختيار ملف IPA».")
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke))

                    Button {
                        open(URL(string: "itms-apps://apps.apple.com")!, fallback: URL(string: "https://apps.apple.com")!)
                    } label: {
                        linkLabel(title: "فتح App Store", subtitle: "لنسخ رابط التطبيق", systemImage: "bag.fill", tint: Theme.teal)
                    }
                    .buttonStyle(.plain)

                    Text("بوتات استخراج التطبيقات")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 4)

                    ForEach(bots) { bot in
                        Button {
                            openTelegram(bot.username)
                        } label: {
                            linkLabel(title: bot.title, subtitle: "@\(bot.username)", systemImage: "paperplane.fill",
                                      tint: Color(red: 0.16, green: 0.63, blue: 0.89))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onPickFile() }
                    } label: {
                        Label("لدي الملف — اختيار ملف IPA", systemImage: "square.and.arrow.down")
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundColor(Theme.navy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Capsule().fill(Theme.goldGradient))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    Text("هذه البوتات خدمات خارجية لا علاقة لها بالتطبيق. تأكد من مصدر الملف قبل استخدامه.")
                        .font(.caption2)
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.navy)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.goldGradient))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func linkLabel(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.app.fill")
                .foregroundColor(Theme.gold)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
        .contentShape(Rectangle())
    }

    // MARK: - Links

    /// Opens the chat in the Telegram app; falls back to t.me (which also hands off to Telegram or the web).
    private func openTelegram(_ username: String) {
        let app = URL(string: "tg://resolve?domain=\(username)")!
        let web = URL(string: "https://t.me/\(username)")!
        open(app, fallback: web)
    }

    private func open(_ url: URL, fallback: URL) {
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { UIApplication.shared.open(fallback) }
        }
    }
}
