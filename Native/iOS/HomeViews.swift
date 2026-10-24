import SwiftUI

struct SpottrRoot: View {
    @Bindable var store: TrainingStore
    var body: some View {
        TabView {
            TodayView(store: store).tabItem { Label("Today", systemImage: "house") }
            WeeklyProgressView(store: store).tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
            SkillsView(store: store).tabItem { Label("Skills", systemImage: "point.3.connected.trianglepath.dotted") }
            CoachView(store: store).tabItem { Label("Coach", systemImage: "bubble") }
        }
        .fullScreenCover(isPresented: $store.presented) { SessionView(store: store).interactiveDismissDisabled() }
        .foregroundStyle(Palette.ink)
    }
}

struct TodayView: View {
    @Bindable var store: TrainingStore
    @State private var libraryPresented = false
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
                Button { libraryPresented = true } label: {
                    Label("Exercise library", systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                Label("Keep your rhythm.", systemImage: "applewatch").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                if let error = store.error { Text(error).font(.caption).foregroundStyle(Palette.red) }
            }.padding(24)
        }.background(.white).sheet(isPresented: $libraryPresented) { ExerciseLibraryView(store: store) }
    }
}
