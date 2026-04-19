import SwiftUI

struct AnswerCardView: View {
    let text: String
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var didCopy = false

    private let cardWidth: CGFloat = 360
    private let textMaxHeight: CGFloat = 220
    // If text exceeds this many characters, use a scrolling view. Otherwise the card fits the text.
    private let scrollThreshold = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if text.count > scrollThreshold {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.95))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: textMaxHeight)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Button(action: {
                    onCopy()
                    withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.13, green: 0.13, blue: 0.13).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}
