import SwiftUI

struct LibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: InjectorViewModel
    @StateObject private var store = LibraryStore()
    @State private var search = ""
    @State private var expanded: String?
    @State private var errorMessage: String?

    private var filtered: [LibraryDylib] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.items }
        return store.items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
                || ($0.category ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                header
                searchField
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .preferredColorScheme(.dark)
        .task { await store.load() }
        .alert("تنبيه", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.navy)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.goldGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("مكتبة الدايلب")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundColor(.white)
                Text(store.isOffline ? "بدون اتصال — نسخة محفوظة" : "اختر أداة لإضافتها للحقن")
                    .font(.caption)
                    .foregroundColor(store.isOffline ? Theme.gold : Theme.secondaryText)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("تم")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.secondaryText)
            TextField("", text: $search, prompt: Text("بحث").foregroundColor(Color.white.opacity(0.38)))
                .foregroundColor(.white)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.secondaryText)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.field))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            Spacer()
            switch store.state {
            case .idle, .loading:
                ProgressView("جارٍ تحميل المكتبة…").tint(.white).foregroundColor(.white)
            case .failed(let message):
                emptyState(icon: "wifi.exclamationmark", title: "تعذّر تحميل المكتبة", text: message, retry: true)
            case .loaded:
                emptyState(icon: "tray", title: "المكتبة فارغة حالياً", text: "ستظهر الأدوات هنا عند إضافتها.", retry: true)
            }
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { item in
                        row(item)
                    }
                    if filtered.isEmpty {
                        Text("لا توجد نتائج")
                            .foregroundColor(Theme.secondaryText)
                            .padding(.top, 30)
                    }
                }
                .padding(.bottom, 30)
            }
            .refreshable { await store.load() }
        }
    }

    private func emptyState(icon: String, title: String, text: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Theme.gold)
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if retry {
                Button {
                    Task { await store.load() }
                } label: {
                    Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(Theme.navy)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.goldGradient))
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
    }

    // MARK: - Row

    private func row(_ item: LibraryDylib) -> some View {
        let isOpen = expanded == item.id
        let added = isAdded(item)
        let isDownloading = store.downloading.contains(item.id)

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded = isOpen ? nil : item.id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.icon ?? "puzzlepiece.extension.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.deep, Theme.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if let version = item.version {
                                Text(version)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Theme.secondaryText)
                            }
                        }
                        Text(item.summary)
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(isOpen ? nil : 2)
                    }
                    Spacer(minLength: 4)
                    if added {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.success)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                details(item, added: added, isDownloading: isDownloading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isOpen ? Theme.gold.opacity(0.5) : Theme.stroke))
    }

    private func details(_ item: LibraryDylib, added: Bool, isDownloading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let category = item.category { tag(category, systemImage: "tag.fill") }
                if let author = item.author { tag(author, systemImage: "person.fill") }
                if item.needsSubstrate == true { tag("يحتاج CydiaSubstrate", systemImage: "exclamationmark.triangle.fill", color: Theme.gold) }
            }

            if let description = item.description, !description.isEmpty {
                section(title: "الوظيفة", systemImage: "info.circle.fill", text: description)
            }
            if let activation = item.activation, !activation.isEmpty {
                section(title: "طريقة التفعيل", systemImage: "hand.tap.fill", text: activation)
            }

            Button {
                Task { await add(item) }
            } label: {
                HStack(spacing: 8) {
                    if isDownloading {
                        ProgressView().tint(Theme.navy)
                        Text("جارٍ التحميل…")
                    } else if added {
                        Image(systemName: "checkmark")
                        Text("مُضاف للحقن")
                    } else {
                        Image(systemName: "plus")
                        Text("إضافة للحقن")
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundColor(added ? .white : Theme.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(added ? AnyShapeStyle(Theme.success.opacity(0.35)) : AnyShapeStyle(Theme.goldGradient))
                )
            }
            .buttonStyle(.plain)
            .disabled(added || isDownloading)
        }
    }

    private func section(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundColor(Theme.gold)
            Text(text)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.2)))
    }

    private func tag(_ text: String, systemImage: String, color: Color = Theme.secondaryText) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: - Actions

    private func isAdded(_ item: LibraryDylib) -> Bool {
        guard let remote = store.fileURL(for: item) else { return false }
        let name = remote.lastPathComponent.removingPercentEncoding ?? remote.lastPathComponent
        return model.tweaks.contains { $0.lastPathComponent == name || $0.lastPathComponent == "\(item.id).dylib" }
    }

    private func add(_ item: LibraryDylib) async {
        do {
            let local = try await store.download(item)
            model.addTweakFile(local)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
