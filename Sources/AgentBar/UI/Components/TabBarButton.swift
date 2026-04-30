import SwiftUI

struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .font(.system(size: 13, weight: self.isSelected ? .semibold : .regular))
                .foregroundStyle(self.isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if self.isSelected {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
