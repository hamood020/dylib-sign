import SwiftUI

struct ContentView: View {
    @StateObject private var model = InjectorViewModel()
    @State private var showMods = false
    @State private var showLog = true
    @State private var showShare = false
    @State private var showGuide = false
    @State private var showLibrary = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    appCard
                    tweaksCard
                    injectCard
                    modsCard
                    signingCard
                    if model.output != nil { resultCard }
                    if !model.logLines.isEmpty { logCard }
                    Color.clear.frame(height: 110) // room for the bottom button
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in hideKeyboard() })

            bottomBar
        }
        .preferredColorScheme(.dark)
        .alert("تنبيه", isPresented: Binding(get: { model.errorMessage != nil },
                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showGuide) {
            IPAGuideSheet(onPickFile: { model.pick(.ipa) })
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showLibrary) {
            LibrarySheet(model: model)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showShare) {
            if let output = model.output {
                ShareSheet(items: [output])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.navy, Theme.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(spacing: 0) {
                    Text("DS")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(".dylib")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gold)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .frame(width: 58, height: 58)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15)))
            .shadow(color: Theme.teal.opacity(0.5), radius: 12, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("Dylib Sign")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("حقن الأدوات في التطبيقات بدون جلبريك")
                    .font(.footnote)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            Button {
                withAnimation { model.reset() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .disabled(model.isRunning)
            .accessibilityLabel("مسح الكل")
        }
        .padding(.vertical, 8)
    }

    // MARK: - Cards

    private var appCard: some View {
        StepCard(step: 1, title: "التطبيق", subtitle: "ملف IPA مفكوك التشفير", systemImage: "app.badge.fill") {
            FileSlot(placeholder: "اختر ملف IPA",
                     hint: "اضغط لاختيار الملف من تطبيق الملفات",
                     systemImage: "square.and.arrow.down",
                     file: model.ipa,
                     isLoading: model.preparing == .ipa,
                     onPick: { model.pick(.ipa) },
                     onClear: { if let url = model.ipa { model.remove(url) } })

            Button {
                showGuide = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                    Text("كيف أحصل على ملف IPA؟")
                    Spacer()
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(Color(red: 0.16, green: 0.63, blue: 0.89))
                }
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundColor(Theme.gold)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tweaksCard: some View {
        StepCard(step: 2, title: "الأدوات", subtitle: "dylib أو deb — يمكن إضافة أكثر من ملف", systemImage: "syringe.fill") {
            VStack(spacing: 8) {
                ForEach(model.tweaks, id: \.self) { url in
                    FileChip(url: url) { withAnimation { model.remove(url) } }
                }
                HStack(spacing: 8) {
                    AddButton(title: "من ملفاتي", isLoading: model.preparing == .tweak) { model.pick(.tweak) }
                    Button {
                        showLibrary = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "books.vertical.fill")
                            Text("من المكتبة")
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.goldGradient))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRunning)
                }

                DisclosureGroup {
                    VStack(spacing: 8) {
                        ForEach(model.extras, id: \.self) { url in
                            FileChip(url: url) { withAnimation { model.remove(url) } }
                        }
                        AddButton(title: "إضافة framework / dylib", isLoading: model.preparing == .extra) { model.pick(.extra) }
                        Text("تُنسخ إلى Frameworks بدون حقن، مثل CydiaSubstrate.framework من ElleKit إذا كانت الأداة تحتاجه.")
                            .font(.caption2)
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("ملفات مساعدة (اختياري)\(model.extras.isEmpty ? "" : " • \(model.extras.count)")")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .tint(Theme.gold)
                .padding(.top, 4)
            }
        }
    }

    private var injectCard: some View {
        StepCard(step: 3, title: "طريقة الحقن", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 12) {
                ChoicePicker(options: InjectLocation.allCases, selection: $model.options.location) { $0.title }
                    .environment(\.layoutDirection, .leftToRight)
                OptionToggle(title: "حقن ضعيف (Weak)", subtitle: "لا ينهار التطبيق إذا لم يجد الدايلب",
                             isOn: $model.options.weakInject)
                OptionToggle(title: "إصلاح مسار CydiaSubstrate", subtitle: "مطلوب لأغلب أدوات الجلبريك",
                             isOn: $model.options.fixSubstratePaths)
                OptionToggle(title: "تجاوز فحص التشفير", subtitle: "غير مُستحسن — التطبيق المشفّر لن يعمل",
                             isOn: $model.options.skipEncryptionCheck)
            }
        }
    }

    private var modsCard: some View {
        StepCard(step: 4, title: "تعديلات التطبيق", subtitle: "اختياري — اترك الحقول فارغة للإبقاء على الأصل",
                 systemImage: "slider.horizontal.3") {
            DisclosureGroup(isExpanded: $showMods) {
                VStack(spacing: 10) {
                    StyledField(title: "Bundle ID جديد", systemImage: "number", text: $model.options.bundleID)
                        .environment(\.layoutDirection, .leftToRight)
                    StyledField(title: "اسم التطبيق", systemImage: "textformat", text: $model.options.displayName)
                    StyledField(title: "الإصدار", systemImage: "tag", text: $model.options.version, keyboard: .decimalPad)
                    FileSlot(placeholder: "أيقونة جديدة (PNG)",
                             hint: model.signing.mode == .none ? "تحتاج اختيار توقيع لتطبيقها" : "اختياري",
                             systemImage: "photo",
                             file: model.icon,
                             isLoading: model.preparing == .icon,
                             onPick: { model.pick(.icon) },
                             onClear: { if let url = model.icon { model.remove(url) } })
                    Divider().overlay(Theme.stroke)
                    OptionToggle(title: "حذف URL Schemes", isOn: $model.options.removeURLSchemes)
                    OptionToggle(title: "تفعيل Document Browser", isOn: $model.options.enableDocumentBrowser)
                    OptionToggle(title: "حذف Extensions", isOn: $model.options.removeExtensions)
                    OptionToggle(title: "حذف مجلد Watch", isOn: $model.options.removeWatchApp)
                    OptionToggle(title: "حذف UISupportedDevices", isOn: $model.options.removeSupportedDevices)
                }
                .padding(.top, 10)
            } label: {
                Text(showMods ? "إخفاء التعديلات" : "عرض التعديلات")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .tint(Theme.gold)
        }
    }

    private var signingCard: some View {
        StepCard(step: 5, title: "التوقيع", subtitle: "اختياري", systemImage: "signature") {
            VStack(alignment: .leading, spacing: 12) {
                ChoicePicker(options: SigningMode.allCases, selection: $model.signing.mode) { $0.title }
                Text(model.signing.mode.footnote)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if model.signing.mode == .certificate {
                    FileSlot(placeholder: "الشهادة (.p12)", hint: "ملف الشهادة",
                             systemImage: "key.fill", file: model.signing.p12,
                             isLoading: model.preparing == .p12,
                             onPick: { model.pick(.p12) },
                             onClear: { if let url = model.signing.p12 { model.remove(url) } })
                    StyledField(title: "كلمة مرور الشهادة", systemImage: "lock.fill",
                                text: $model.signing.password, secure: true)
                    FileSlot(placeholder: "البروفايل (.mobileprovision)", hint: "ملف التوزيع المطابق للشهادة",
                             systemImage: "doc.badge.gearshape.fill", file: model.signing.provision,
                             isLoading: model.preparing == .provision,
                             onPick: { model.pick(.provision) },
                             onClear: { if let url = model.signing.provision { model.remove(url) } })
                    OptionToggle(title: "تثبيت مباشرة بعد التوقيع",
                                 subtitle: "يظهر طلب التثبيت من النظام فور انتهاء الحقن",
                                 isOn: $model.autoInstall)
                }
            }
        }
    }

    private var resultCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.success)
            Text("تم الحقن بنجاح")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.white)
            if let output = model.output {
                Text(output.lastPathComponent)
                    .font(.footnote.monospaced())
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Text("محفوظ في: الملفات ← على الـ iPhone ← Dylib Sign ← Output")
                .font(.caption)
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)

            if model.canInstall {
                installSection
            } else {
                Text("للتثبيت المباشر على الجهاز اختر «بشهادة» في خطوة التوقيع.")
                    .font(.caption2)
                    .foregroundColor(Theme.gold.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            Button {
                showShare = true
            } label: {
                Label("مشاركة / حفظ الملف", systemImage: "square.and.arrow.up")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.goldGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.success.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.success.opacity(0.4)))
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var installSection: some View {
        let state = model.installState
        VStack(spacing: 10) {
            Button {
                model.install()
            } label: {
                HStack(spacing: 10) {
                    switch state {
                    case .idle, .finished:
                        Image(systemName: "iphone.and.arrow.forward")
                        Text(state == .finished ? "إعادة التثبيت" : "تثبيت على الجهاز")
                    case .preparing, .waiting, .downloading:
                        ProgressView().tint(.white)
                        Text(state == .downloading ? "جارٍ التثبيت…" : "بانتظار موافقتك…")
                    }
                }
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(LinearGradient(colors: [Theme.teal, Theme.deep],
                                                          startPoint: .leading, endPoint: .trailing)))
                .overlay(Capsule().stroke(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .disabled(state == .preparing || state == .waiting || state == .downloading)

            Group {
                switch state {
                case .idle:
                    Text("يثبّت التطبيق مباشرة على هذا الآيفون كما في ESign.")
                case .preparing, .waiting:
                    Text("اضغط «تثبيت» في النافذة التي تظهر من النظام.")
                case .downloading:
                    Text("ابقَ في التطبيق أو اتركه في الخلفية حتى يكتمل التحميل.")
                case .finished:
                    Text("تم إرسال التطبيق — تابع ظهوره على الشاشة الرئيسية.")
                }
            }
            .font(.caption)
            .foregroundColor(Theme.secondaryText)
            .multilineTextAlignment(.center)

            if state == .waiting || state == .downloading {
                Button("إيقاف") { model.stopInstall() }
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.danger)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.2)))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showLog.toggle() }
            } label: {
                HStack {
                    Label("السجل", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: showLog ? "chevron.up" : "chevron.down")
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showLog {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(model.logLines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.isRunning, let last = model.lastLog {
                Text(last)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let missing = model.missingRequirement {
                Text(missing)
                    .font(.caption)
                    .foregroundColor(Theme.gold.opacity(0.9))
            }

            Button {
                hideKeyboard()
                showLog = true
                model.start()
            } label: {
                HStack(spacing: 10) {
                    if model.isRunning {
                        ProgressView().tint(Theme.navy)
                        Text("جارٍ الحقن…")
                    } else {
                        Image(systemName: "syringe.fill")
                        Text("ابدأ الحقن")
                    }
                }
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundColor(Theme.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.goldGradient))
                .opacity(model.canStart || model.isRunning ? 1 : 0.45)
                .shadow(color: Theme.gold.opacity(model.canStart ? 0.45 : 0), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!model.canStart)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.navy.opacity(0), Theme.navy.opacity(0.85), Theme.navy],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
