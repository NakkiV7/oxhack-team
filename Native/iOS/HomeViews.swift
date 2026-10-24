import SwiftUI

struct SpottrRoot: View {
    @Bindable var store: TrainingStore
    var body: some View {
        TabView {
            TodayView(store: store).tabItem { Label("Today", systemImage: "house") }
            ProgressView(store: store).tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
            CoachView().tabItem { Label("Coach", systemImage: "bubble") }
        }
        .fullScreenCover(isPresented: $store.presented) { SessionView(store: store).interactiveDismissDisabled() }
        .foregroundStyle(Palette.ink)
    }
}

struct TodayView: View {
    @Bindable var store: TrainingStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    Text("Spottr").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1.2)
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional").padding(12).background(Palette.surface, in: Circle())
                }.padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 9) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.caption).foregroundStyle(.secondary)
                    Text("Let’s get to work.").font(.system(size: 32, weight: .bold)).tracking(-1)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image("strength").resizable().scaledToFit().frame(width: 27, height: 27)
                        Text("Strength").font(.caption.weight(.semibold))
                    }
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Build your\nfoundation.").font(.system(size: 27, weight: .bold)).tracking(-0.8)
                            HStack(spacing: 14) {
                                Label("12 min", systemImage: "clock")
                                Label("6 sets", systemImage: "square.3.layers.3d")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image("\(store.selectedExercise.rawValue)-mid").resizable().scaledToFit().frame(width: 116, height: 155)
                    }
                    PrimaryButton(title: "Start session", action: store.start)
                }.padding(21).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
                HStack { Text("Your session").font(.headline); Spacer(); Text("Bodyweight").font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    ForEach(Exercise.allCases, id: \.self) { exercise in
                        Button { store.selectedExercise = exercise } label: {
                            HStack(spacing: 14) {
                                Image("\(exercise.rawValue)-mid").resizable().scaledToFit().frame(width: 42, height: 47)
                                    .padding(6).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.title).font(.subheadline.weight(.semibold))
                                    Text("3 sets × \(exercise.target) reps").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: store.selectedExercise == exercise ? "checkmark.circle.fill" : "circle").font(.body)
                            }.padding(.vertical, 15).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Start with \(exercise.title)")
                        Divider()
                    }
                }
                Label("Keep your rhythm.", systemImage: "applewatch").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }.padding(24)
        }.background(.white)
    }
}

struct ProgressView: View {
    let store: TrainingStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("Every rep adds up.").font(.system(size: 31, weight: .bold)).tracking(-1)
                    if store.history.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "chart.xyaxis.line").font(.system(size: 38, weight: .light))
                            Text("Your first session starts here.").font(.headline)
                            Text("Finish a set to see your reps, time and effort in one place.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(30).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    ForEach(store.history) { record in
                        VStack(alignment: .leading, spacing: 16) {
                            Label(record.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                            Text("\(record.sets.count) \(record.sets.count == 1 ? "set" : "sets") · \(record.reps) reps").font(.title3.weight(.semibold))
                            Label(clockText(record.activeSeconds), systemImage: "clock").font(.subheadline)
                            ForEach(record.sets) { set in
                                HStack {
                                    Text("\(set.exercise.title) · \(set.number)")
                                    Spacer()
                                    Text("\(set.reps) reps")
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                }.padding(24)
            }.navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CoachView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text("Keep the control.").font(.system(size: 32, weight: .bold)).tracking(-1)
                    Text("Set your iPhone to the side at hip height, with your whole body in view. Train one person at a time.")
                        .foregroundStyle(.secondary)
                    ForEach(Exercise.allCases, id: \.self) { exercise in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(exercise.title).font(.title3.bold())
                            HStack {
                                ForEach(["top", "mid", "bottom"], id: \.self) { phase in
                                    Image("\(exercise.rawValue)-\(phase)").resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 110)
                                }
                            }
                            Text(exercise.guide).font(.subheadline.weight(.medium))
                            Text(exercise == .squat ? "Choose a comfortable depth. Return to standing to complete the rep." : "Keep shoulders, hips and ankles in one line. Return to extended arms to complete the rep.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 23))
                    }
                    Label("Stop if you feel pain or discomfort.", systemImage: "hand.raised").font(.subheadline)
                }.padding(24)
            }.navigationTitle("Your coach").navigationBarTitleDisplayMode(.inline)
        }
    }
}
