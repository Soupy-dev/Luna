package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.displayDate
import dev.soupy.eclipse.android.core.model.displayTitle
import dev.soupy.eclipse.android.core.model.isMovie
import dev.soupy.eclipse.android.core.model.isTVShow
import dev.soupy.eclipse.android.core.network.TmdbService
import kotlin.math.max

data class AnimeTmdbMatch(
    val target: DetailTarget,
    val tmdbId: Int,
    val mediaType: String,
    val title: String,
    val matchedQuery: String,
    val confidence: Double,
)

class AnimeTmdbMapper(
    private val tmdbService: TmdbService,
) {
    suspend fun findBestMatch(media: AniListMedia): AnimeTmdbMatch? {
        val titleCandidates = media.titleCandidates()
        if (titleCandidates.isEmpty()) return null

        val preferredMediaType = if (media.format.equals("MOVIE", ignoreCase = true)) "movie" else "tv"
        val scoredMatches = mutableListOf<AnimeTmdbMatch>()

        titleCandidates.take(8).forEach { query ->
            val results = tmdbService.searchMulti(query = query, page = 1)
                .orNull()
                ?.results
                .orEmpty()
                .filter { result -> result.isMovie || result.isTVShow }

            results.mapNotNullTo(scoredMatches) { result ->
                result.toAnimeTmdbMatch(
                    query = query,
                    media = media,
                    preferredMediaType = preferredMediaType,
                )
            }
        }

        return scoredMatches
            .groupBy { "${it.mediaType}:${it.tmdbId}" }
            .mapNotNull { (_, matches) -> matches.maxByOrNull(AnimeTmdbMatch::confidence) }
            .maxWithOrNull(
                compareBy<AnimeTmdbMatch> { it.confidence }
                    .thenBy { if (it.mediaType == preferredMediaType) 1 else 0 },
            )
            ?.takeIf { it.confidence >= 0.42 }
    }
}

private fun TMDBSearchResult.toAnimeTmdbMatch(
    query: String,
    media: AniListMedia,
    preferredMediaType: String,
): AnimeTmdbMatch? {
    val resultMediaType = when {
        isMovie -> "movie"
        isTVShow -> "tv"
        else -> return null
    }
    val queryScore = titleSimilarity(query, displayTitle)
    val sourceTitleScore = media.titleCandidates()
        .maxOfOrNull { title -> titleSimilarity(title, displayTitle) }
        ?: queryScore
    val titleScore = max(queryScore, sourceTitleScore)
    val yearScore = yearScore(media.seasonYear, displayDate?.take(4)?.toIntOrNull())
    val formatScore = if (resultMediaType == preferredMediaType) 0.13 else -0.04
    val animationHint = if (16 in genreIds) 0.04 else 0.0
    val confidence = (titleScore + yearScore + formatScore + animationHint).coerceIn(0.0, 1.0)

    return AnimeTmdbMatch(
        target = if (resultMediaType == "movie") {
            DetailTarget.TmdbMovie(id)
        } else {
            DetailTarget.TmdbShow(id)
        },
        tmdbId = id,
        mediaType = resultMediaType,
        title = displayTitle,
        matchedQuery = query,
        confidence = confidence,
    )
}

private fun AniListMedia.titleCandidates(): List<String> {
    val ordered = buildList {
        add(title.userPreferred)
        add(title.english)
        add(title.romaji)
        add(title.native)
        addAll(synonyms)
    }

    return ordered
        .filterNotNull()
        .flatMap { title ->
            listOf(
                title,
                title.withoutSeasonSuffix(),
                title.substringBefore(':').trim(),
            )
        }
        .map { it.trim().trim('[', ']') }
        .filter { it.length > 1 }
        .distinctBy { it.normalizedTitle() }
}

private fun titleSimilarity(left: String, right: String): Double {
    val a = left.normalizedTitle()
    val b = right.normalizedTitle()
    if (a.isEmpty() || b.isEmpty()) return 0.0
    if (a == b) return 0.72
    if (a.contains(b) || b.contains(a)) return 0.56

    val tokenScore = tokenOverlap(a, b) * 0.42
    val editScore = normalizedLevenshtein(a, b) * 0.28
    return tokenScore + editScore
}

private fun yearScore(animeYear: Int?, tmdbYear: Int?): Double {
    if (animeYear == null || tmdbYear == null) return 0.0
    val diff = kotlin.math.abs(animeYear - tmdbYear)
    return when (diff) {
        0 -> 0.15
        1 -> 0.08
        else -> 0.0
    }
}

private fun tokenOverlap(left: String, right: String): Double {
    val leftTokens = left.split(' ').filter(String::isNotBlank).toSet()
    val rightTokens = right.split(' ').filter(String::isNotBlank).toSet()
    if (leftTokens.isEmpty() || rightTokens.isEmpty()) return 0.0
    val shared = leftTokens.intersect(rightTokens).size.toDouble()
    val total = leftTokens.union(rightTokens).size.toDouble()
    return shared / total
}

private fun normalizedLevenshtein(left: String, right: String): Double {
    val maxLength = max(left.length, right.length)
    if (maxLength == 0) return 1.0

    val previous = IntArray(right.length + 1) { it }
    val current = IntArray(right.length + 1)

    left.forEachIndexed { leftIndex, leftChar ->
        current[0] = leftIndex + 1
        right.forEachIndexed { rightIndex, rightChar ->
            val deletion = previous[rightIndex + 1] + 1
            val insertion = current[rightIndex] + 1
            val substitution = previous[rightIndex] + if (leftChar == rightChar) 0 else 1
            current[rightIndex + 1] = minOf(deletion, insertion, substitution)
        }
        for (index in previous.indices) {
            previous[index] = current[index]
        }
    }

    return 1.0 - (previous[right.length].toDouble() / maxLength.toDouble())
}

private fun String.normalizedTitle(): String = lowercase()
    .replace(Regex("[^a-z0-9\\s]"), " ")
    .replace(Regex("\\b(the|a|an)\\b"), " ")
    .replace(Regex("\\s+"), " ")
    .trim()

private fun String.withoutSeasonSuffix(): String = replace(
    Regex("\\s+(season|part)\\s+\\d+$", RegexOption.IGNORE_CASE),
    "",
).trim()
