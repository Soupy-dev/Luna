package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.AniListRelatedMedia
import dev.soupy.eclipse.android.core.model.AniListRelations
import dev.soupy.eclipse.android.core.model.AniListTitle
import dev.soupy.eclipse.android.core.model.TMDBSeason
import dev.soupy.eclipse.android.core.model.TMDBTVShowDetail
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AnimeTmdbMapperTest {
    @Test
    fun titleCandidatesKeepBaseTitleForSeasonSuffixes() {
        val media = AniListMedia(
            title = AniListTitle(
                english = "SPY x FAMILY Season 2",
                romaji = "Spy x Family 2nd Season",
            ),
        )

        val candidates = media.titleCandidates()

        assertTrue(candidates.any { it.equals("SPY x FAMILY", ignoreCase = true) })
        assertEquals(candidates.size, candidates.distinctBy { it.lowercase() }.size)
    }

    @Test
    fun seasonMatcherPrefersEpisodeAndYearAlignedSeason() {
        val anime = AniListMedia(
            title = AniListTitle(english = "Example Anime Season 2"),
            seasonYear = 2023,
            episodes = 12,
            format = "TV",
        )
        val show = TMDBTVShowDetail(
            id = 10,
            name = "Example Anime",
            firstAirDate = "2022-01-10",
            seasons = listOf(
                TMDBSeason(seasonNumber = 1, episodeCount = 25, airDate = "2022-01-10"),
                TMDBSeason(seasonNumber = 2, episodeCount = 12, airDate = "2023-04-05"),
                TMDBSeason(seasonNumber = 3, episodeCount = 13, airDate = "2024-07-01"),
            ),
        )

        val match = anime.bestTmdbSeasonMatch(show)

        assertEquals(2, match?.seasonNumber)
        assertTrue((match?.confidence ?: 0.0) > 0.15)
    }

    @Test
    fun titleSimilarityBlendsTokenEditAndJaroSignals() {
        val score = titleSimilarity(
            left = "Frieren Beyond Journey's End",
            right = "Frieren: Beyond Journey's End",
        )

        assertTrue(score > 0.7)
    }

    @Test
    fun reconstructionMapsSequelsAndSpecialsAcrossTmdbSeasons() {
        val seasonOne = AniListMedia(
            id = 1,
            title = AniListTitle(english = "Example Anime"),
            seasonYear = 2021,
            episodes = 12,
            format = "TV",
        )
        val special = AniListMedia(
            id = 3,
            title = AniListTitle(english = "Example Anime OVA"),
            seasonYear = 2021,
            episodes = 1,
            format = "OVA",
        )
        val seasonTwo = AniListMedia(
            id = 2,
            title = AniListTitle(english = "Example Anime Season 2"),
            seasonYear = 2022,
            episodes = 12,
            format = "TV",
            relations = AniListRelations(
                edges = listOf(
                    AniListRelatedMedia(relationType = "PREQUEL", node = seasonOne),
                    AniListRelatedMedia(relationType = "SIDE_STORY", node = special),
                ),
            ),
        )
        val show = TMDBTVShowDetail(
            id = 10,
            name = "Example Anime",
            seasons = listOf(
                TMDBSeason(seasonNumber = 0, episodeCount = 1, airDate = "2021-06-01"),
                TMDBSeason(seasonNumber = 1, episodeCount = 12, airDate = "2021-01-10"),
                TMDBSeason(seasonNumber = 2, episodeCount = 12, airDate = "2022-01-10"),
            ),
        )

        val mappings = seasonTwo.reconstructTmdbEpisodeMappings(
            show = show,
            anchorSeasonMatch = AnimeTmdbSeasonMatch(seasonNumber = 2, confidence = 0.2),
        )

        assertTrue(mappings.any { it.anilistMediaId == 1 && it.tmdbSeasonNumber == 1 })
        assertTrue(mappings.any { it.anilistMediaId == 2 && it.tmdbSeasonNumber == 2 })
        assertTrue(mappings.any { it.anilistMediaId == 3 && it.tmdbSeasonNumber == 0 && it.isSpecial })
    }
}
