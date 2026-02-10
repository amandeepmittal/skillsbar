import SwiftUI

struct SectionHeaderView: View {
    let title: String
    let isGroup: Bool

    init(title: String, isGroup: Bool = false) {
        self.title = title
        self.isGroup = isGroup
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: isGroup ? 12 : 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isGroup ? 12 : 8)
            .padding(.bottom, 4)
    }
}
