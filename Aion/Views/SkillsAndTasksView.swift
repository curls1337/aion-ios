import SwiftUI

enum WorkspaceSegment: String, CaseIterable, Identifiable {
    case skills = "Skills Library"
    case tasks = "Scheduled Tasks"

    var id: String { rawValue }
}

struct SkillsAndTasksView: View {
    @Bindable var store: AionStore
    @Binding var selectedSegment: WorkspaceSegment
    let onLaunchConversation: (UUID) -> Void

    @State private var isNewCronSheetPresented = false
    @Namespace private var segmentNamespace

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(selectedSegment == .skills ? "Skills" : "Schedules")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AionTheme.inkPrimary)

                    Spacer()

                    if selectedSegment == .tasks {
                        Button {
                            AionHaptics.light()
                            isNewCronSheetPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AionTheme.inkPrimary)
                                .frame(width: 40, height: 40)
                                .aionLiquidGlass(in: Circle(), interactive: true, shadowRadius: 8)
                        }
                        .buttonStyle(AionSpringButtonStyle())
                    }
                }

                // Liquid Glass Segmented Switcher
                AionGlassContainer(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(WorkspaceSegment.allCases) { segment in
                            let isSelected = selectedSegment == segment
                            Button {
                                AionHaptics.selection()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                    selectedSegment = segment
                                }
                            } label: {
                                Text(segment.rawValue)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? AionTheme.inkPrimary : AionTheme.inkSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background {
                                        if isSelected {
                                            Capsule()
                                                .fill(AionTheme.surface)
                                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                                                .matchedGeometryEffect(id: "workspace-seg", in: segmentNamespace)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 8)
                }

                if selectedSegment == .skills {
                    skillsListSection
                } else {
                    cronTasksListSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 108)
        }
        .sheet(isPresented: $isNewCronSheetPresented) {
            CreateCronTaskSheet { name, expr, label, prompt in
                store.addCronTask(
                    name: name,
                    scheduleExpression: expr,
                    scheduleLabel: label,
                    prompt: prompt
                )
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(28)
        }
    }

    // MARK: - Skills Cards

    private var skillsListSection: some View {
        VStack(spacing: 12) {
            ForEach(store.skills) { skill in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AionTheme.bentoLavender)
                                .frame(width: 44, height: 44)
                            Image(systemName: skill.iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AionTheme.lavenderAccent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(skill.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(AionTheme.inkPrimary)

                                Text(skill.category)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AionTheme.lavenderAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AionTheme.bentoLavender.opacity(0.75), in: Capsule())
                            }

                            Text(skill.summary)
                                .font(.system(size: 13.5))
                                .foregroundStyle(AionTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        Toggle("", isOn: Binding(
                            get: { skill.isEnabled },
                            set: { _ in store.toggleSkill(skill.id) }
                        ))
                        .labelsHidden()
                        .tint(AionTheme.forest)
                    }

                    HStack {
                        Text(skill.id)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AionTheme.inkTertiary)

                        Spacer()

                        Button {
                            AionHaptics.medium()
                            let convo = store.createNewConversation(
                                title: skill.name,
                                initialPrompt: skill.samplePrompt,
                                skill: skill
                            )
                            onLaunchConversation(convo.id)
                        } label: {
                            Label("Run Skill", systemImage: "play.fill")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 4)
                        }
                        .buttonStyle(AionSpringButtonStyle(scale: 0.95))
                        .disabled(!skill.isEnabled)
                        .opacity(skill.isEnabled ? 1 : 0.45)
                    }
                }
                .padding(16)
                .aionBentoCard(fill: AionTheme.surface, cornerRadius: 22)
            }
        }
    }

    // MARK: - Cron Tasks Cards

    private var cronTasksListSection: some View {
        VStack(spacing: 12) {
            ForEach(store.cronTasks) { task in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AionTheme.bentoSage)
                                .frame(width: 44, height: 44)
                            Image(systemName: "clock.badge.checkmark.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AionTheme.forest)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)

                            Text(task.scheduleLabel)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AionTheme.forest)

                            Text(task.prompt)
                                .font(.system(size: 13.5))
                                .foregroundStyle(AionTheme.inkSecondary)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }

                        Spacer(minLength: 4)

                        Toggle("", isOn: Binding(
                            get: { task.isActive },
                            set: { _ in store.toggleCronTask(task.id) }
                        ))
                        .labelsHidden()
                        .tint(AionTheme.forest)
                    }

                    HStack {
                        Text(task.scheduleExpression)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AionTheme.inkTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AionTheme.surfaceSecondary, in: Capsule())

                        Spacer()

                        Button {
                            AionHaptics.medium()
                            if let convo = store.runCronTaskNow(task) {
                                onLaunchConversation(convo.id)
                            }
                        } label: {
                            Label("Run Now", systemImage: "bolt.fill")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(AionTheme.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .aionLiquidGlass(in: Capsule(), interactive: true, shadowRadius: 4)
                        }
                        .buttonStyle(AionSpringButtonStyle(scale: 0.95))
                    }
                }
                .padding(16)
                .aionBentoCard(fill: AionTheme.surface, cornerRadius: 22)
                .contextMenu {
                    Button(role: .destructive) {
                        store.deleteCronTask(task.id)
                    } label: {
                        Label("Delete Schedule", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct CreateCronTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var selectedPresetIndex = 0

    let onCreate: (String, String, String, String) -> Void

    private let presets: [(label: String, expr: String)] = [
        ("Weekdays · 08:00", "0 8 * * MON-FRI"),
        ("Every hour", "0 * * * *"),
        ("Daily · 18:00", "0 18 * * *"),
        ("Fridays · 17:00", "0 17 * * FRI")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Task Name (e.g. Daily Standup)", text: $name)
                    TextField("Prompt for Aion", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $selectedPresetIndex) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { index, item in
                            Text(item.label).tag(index)
                        }
                    }
                    HStack {
                        Text("Cron Expression")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(presets[selectedPresetIndex].expr)
                            .font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let preset = presets[selectedPresetIndex]
                        onCreate(name.trimmingCharacters(in: .whitespaces), preset.expr, preset.label, prompt.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
