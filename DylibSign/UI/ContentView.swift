import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = InjectorViewModel()
    @State private var importTarget: ImportTarget = .ipa
    @State private var showImporter = false
    @State private var showShare = false

    var body: some View {
        NavigationView {
            Form {
                ipaSection
                tweaksSection
                extrasSection
                injectSection
                modsSection
                signingSection
                actionSection
                if !model.logLines.isEmpty { logSection }
            }
            .navigationTitle("Dylib Sign")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("مسح") { model.reset() }
                        .disabled(model.isRunning)
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTarget.contentTypes,
            allowsMultipleSelection: importTarget.allowsMultiple
        ) { result in
            model.handleImport(result, target: importTarget)
        }
        .alert("تنبيه", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showShare) {
            if let output = model.output {
                ShareSheet(items: [output])
            }
        }
    }

    // MARK: - Sections

    private var ipaSection: some View {
        Section {
            pickRow(title: "ملف IPA", file: model.ipa, systemImage: "app.badge") { open(.ipa) }
        } header: {
            Text("التطبيق")
        } footer: {
            Text("يجب أن يكون الملف مفكوك التشفير (decrypted).")
        }
    }

    private var tweaksSection: some View {
        Section {
            ForEach(model.tweaks, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: icon(for: url))
            }
            .onDelete { model.tweaks.remove(atOffsets: $0) }
            Button {
                open(.tweak)
            } label: {
                Label("إضافة dylib / deb", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("الأدوات المراد حقنها")
        }
    }

    private var extrasSection: some View {
        Section {
            ForEach(model.extras, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: icon(for: url))
            }
            .onDelete { model.extras.remove(atOffsets: $0) }
            Button {
                open(.extra)
            } label: {
                Label("إضافة ملف", systemImage: "plus.circle")
            }
        } header: {
            Text("ملفات إضافية (اختياري)")
        } footer: {
            Text("تُنسخ إلى Frameworks بدون حقن، مثل CydiaSubstrate.framework (ElleKit) أو مكتبات تعتمد عليها الأداة.")
        }
    }

    private var injectSection: some View {
        Section {
            Picker("مسار الحقن", selection: $model.options.location) {
                ForEach(InjectLocation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("حقن ضعيف (Weak)", isOn: $model.options.weakInject)
            Toggle("إصلاح مسار CydiaSubstrate", isOn: $model.options.fixSubstratePaths)
            Toggle("تجاوز فحص التشفير", isOn: $model.options.skipEncryptionCheck)
        } header: {
            Text("الحقن")
        }
    }

    private var modsSection: some View {
        Section {
            TextField("Bundle ID جديد", text: $model.options.bundleID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("اسم التطبيق", text: $model.options.displayName)
            TextField("الإصدار", text: $model.options.version)
                .keyboardType(.decimalPad)
            pickRow(title: "أيقونة (PNG)", file: model.icon, systemImage: "photo") { open(.icon) }
            Toggle("حذف URL Schemes", isOn: $model.options.removeURLSchemes)
            Toggle("تفعيل Document Browser", isOn: $model.options.enableDocumentBrowser)
            Toggle("حذف Extensions", isOn: $model.options.removeExtensions)
            Toggle("حذف مجلد Watch", isOn: $model.options.removeWatchApp)
            Toggle("حذف UISupportedDevices", isOn: $model.options.removeSupportedDevices)
        } header: {
            Text("تعديلات (اختياري)")
        } footer: {
            Text("اترك الحقول فارغة للإبقاء على القيم الأصلية. تغيير الأيقونة يتطلب التوقيع.")
        }
    }

    private var signingSection: some View {
        Section {
            Picker("التوقيع", selection: $model.signing.mode) {
                ForEach(SigningMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.signing.mode == .certificate {
                pickRow(title: "الشهادة (.p12)", file: model.signing.p12, systemImage: "key.fill") { open(.p12) }
                SecureField("كلمة مرور الشهادة", text: $model.signing.password)
                pickRow(title: "البروفايل (.mobileprovision)", file: model.signing.provision, systemImage: "doc.badge.gearshape") {
                    open(.provision)
                }
            }
        } header: {
            Text("التوقيع (اختياري)")
        } footer: {
            Text(model.signing.mode.footnote)
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                model.start()
            } label: {
                HStack {
                    Spacer()
                    if model.isRunning {
                        ProgressView().padding(.trailing, 6)
                        Text("جارٍ الحقن…")
                    } else {
                        Label("ابدأ الحقن", systemImage: "syringe.fill").font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(!model.canStart)

            if let output = model.output {
                VStack(alignment: .leading, spacing: 4) {
                    Label(output.lastPathComponent, systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("محفوظ في تطبيق الملفات ← Dylib Sign ← Output")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    showShare = true
                } label: {
                    Label("مشاركة / حفظ الملف", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var logSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(model.logLines.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("السجل")
        }
    }

    // MARK: - Helpers

    private func open(_ target: ImportTarget) {
        importTarget = target
        showImporter = true
    }

    private func pickRow(title: String, file: URL?, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(file?.lastPathComponent ?? "اختيار")
                    .foregroundColor(file == nil ? .accentColor : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundColor(.primary)
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "deb": return "shippingbox"
        case "framework", "bundle": return "folder"
        default: return "puzzlepiece.extension"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
