import SwiftUI
import UniformTypeIdentifiers

struct CertificatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CertificateStore

    @State private var adding = false
    @State private var name = ""
    @State private var password = ""
    @State private var p12: URL?
    @State private var provision: URL?
    @State private var errorMessage: String?
    @State private var renaming: SavedCertificate?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if adding {
                        addForm
                    } else {
                        list
                        Button {
                            withAnimation { adding = true }
                        } label: {
                            Label("إضافة شهادة جديدة", systemImage: "plus.circle.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.navy)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Theme.goldGradient))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .alert("تنبيه", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert("إعادة تسمية", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("الاسم", text: $renameText)
            Button("حفظ") { if let c = renaming { store.rename(c, to: renameText) }; renaming = nil }
            Button("إلغاء", role: .cancel) { renaming = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.navy)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.goldGradient))
            Text("الشهادات")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundColor(.white)
            Spacer()
            Button {
                if adding { withAnimation { adding = false }; clearForm() } else { dismiss() }
            } label: {
                Text(adding ? "رجوع" : "تم")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if store.certificates.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 36)).foregroundColor(Theme.gold)
                Text("لا توجد شهادات محفوظة")
                    .font(.system(.headline, design: .rounded)).foregroundColor(.white)
                Text("أضف شهادتك ليحفظها التطبيق وتختار بينها بسهولة.")
                    .font(.footnote).foregroundColor(Theme.secondaryText).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            ForEach(store.certificates) { cert in
                row(cert)
            }
        }
    }

    private func row(_ cert: SavedCertificate) -> some View {
        let selected = store.selectedID == cert.id
        return HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(selected ? Theme.success : Color.white.opacity(0.35))
            VStack(alignment: .leading, spacing: 3) {
                Text(cert.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                Text("\(cert.p12Name) • \(cert.provisionName)")
                    .font(.caption2).foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer()
            Menu {
                Button { renameText = cert.name; renaming = cert } label: { Label("إعادة تسمية", systemImage: "pencil") }
                Button(role: .destructive) { store.delete(cert) } label: { Label("حذف", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white).frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? Theme.success.opacity(0.5) : Theme.stroke))
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = cert.id }
    }

    // MARK: - Add form

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            StyledField(title: "اسم الشهادة (اختياري)", systemImage: "textformat", text: $name)
            FileSlot(placeholder: "الشهادة (.p12)", hint: "ملف الشهادة", systemImage: "key.fill",
                     file: p12, onPick: { pick(p12: true) }, onClear: { p12 = nil })
            StyledField(title: "كلمة مرور الشهادة", systemImage: "lock.fill", text: $password, secure: true)
                .environment(\.layoutDirection, .leftToRight)
            FileSlot(placeholder: "البروفايل (.mobileprovision)", hint: "ملف التوزيع المطابق",
                     systemImage: "doc.badge.gearshape.fill", file: provision,
                     onPick: { pick(p12: false) }, onClear: { provision = nil })

            Button {
                save()
            } label: {
                Label("حفظ الشهادة", systemImage: "square.and.arrow.down.fill")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundColor(Theme.navy)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Capsule().fill(Theme.goldGradient))
                    .opacity(p12 != nil && provision != nil ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(p12 == nil || provision == nil)
        }
    }

    // MARK: - Actions

    private func pick(p12 isP12: Bool) {
        let type = isP12 ? "p12" : "mobileprovision"
        DocumentPicker.shared.present(types: [UTType.item], allowsMultiple: false) { urls in
            guard let url = urls.first else { return }
            guard url.pathExtension.lowercased() == type || (isP12 && url.pathExtension.lowercased() == "pfx") else {
                errorMessage = "اختر ملف ‎.\(type)‎"
                return
            }
            if isP12 { p12 = url } else { provision = url }
        }
    }

    private func save() {
        guard let p12, let provision else { return }
        do {
            try store.add(name: name.trimmingCharacters(in: .whitespaces), p12: p12, provision: provision, password: password)
            clearForm()
            withAnimation { adding = false }
        } catch {
            errorMessage = "تعذّر حفظ الشهادة: \(error.localizedDescription)"
        }
    }

    private func clearForm() {
        name = ""; password = ""; p12 = nil; provision = nil
    }
}
