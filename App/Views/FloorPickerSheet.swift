import SwiftUI

struct FloorPickerSheet: View {
    let basementCount: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var levels: [Int] {
        Array(stride(from: 0, through: -max(1, basementCount), by: -1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    ForEach(levels, id: \.self) { level in
                        Button {
                            onSelect(level)
                            dismiss()
                        } label: {
                            VStack(spacing: 2) {
                                Text(FloorStyle.short(level))
                                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                                Text(FloorStyle.long(level))
                                    .font(.caption.weight(.medium))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .background(FloorStyle.gradient(level), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                if level == selected {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                                        .padding(3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(level == selected ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .navigationTitle("몇 층에 주차했나요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
