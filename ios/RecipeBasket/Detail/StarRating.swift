import SwiftUI

/// Five small stars for a tile: filled up to `rating`.
struct RatingStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Recipe.ratingRange, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Color.orange : Color.secondary.opacity(0.5))
            }
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) of 5")
    }
}

/// The recipe screen's rating control: tap a star to rate, tap the current rating to clear it.
struct StarRatingPicker: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Recipe.ratingRange, id: \.self) { star in
                Button {
                    rating = rating == star ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(star == rating ? "Clear rating" : "Rate \(star) \(star == 1 ? "star" : "stars")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\($0) \($0 == 1 ? "star" : "stars")" } ?? "Not rated")
    }
}

#Preview {
    @Previewable @State var rating: Int? = 3
    List {
        LabeledContent("Rating") { StarRatingPicker(rating: $rating) }
        RatingStars(rating: 4)
    }
}
