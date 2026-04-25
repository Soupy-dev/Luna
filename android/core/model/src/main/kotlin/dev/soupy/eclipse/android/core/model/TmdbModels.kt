package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

private const val TmdbImageBaseUrl = "https://image.tmdb.org/t/p/w780"
private const val TmdbBackdropBaseUrl = "https://image.tmdb.org/t/p/w1280"

@Serializable
data class TMDBSearchResponse(
    val page: Int = 1,
    val results: List<TMDBSearchResult> = emptyList(),
    @SerialName("total_pages") val totalPages: Int = 0,
    @SerialName("total_results") val totalResults: Int = 0,
)

@Serializable
data class TMDBSearchResult(
    val id: Int = 0,
    @SerialName("media_type") val mediaType: String? = null,
    val title: String? = null,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("genre_ids") val genreIds: List<Int> = emptyList(),
)

val TMDBSearchResult.displayTitle: String
    get() = title ?: name ?: "Unknown"

val TMDBSearchResult.displayDate: String?
    get() = releaseDate ?: firstAirDate

val TMDBSearchResult.isMovie: Boolean
    get() = mediaType == "movie" || title != null

val TMDBSearchResult.isTVShow: Boolean
    get() = mediaType == "tv" || name != null

val TMDBSearchResult.fullPosterUrl: String?
    get() = posterPath?.let { "$TmdbImageBaseUrl$it" }

val TMDBSearchResult.fullBackdropUrl: String?
    get() = backdropPath?.let { "$TmdbBackdropBaseUrl$it" }

@Serializable
data class TMDBMovie(
    val id: Int = 0,
    val title: String = "",
    val overview: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("genre_ids") val genreIds: List<Int> = emptyList(),
)

@Serializable
data class TMDBTVShow(
    val id: Int = 0,
    val name: String = "",
    val overview: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("genre_ids") val genreIds: List<Int> = emptyList(),
)

@Serializable
data class TMDBMovieDetail(
    val id: Int = 0,
    val title: String = "",
    val overview: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    val runtime: Int? = null,
    val genres: List<TMDBGenre> = emptyList(),
    @SerialName("external_ids") val externalIds: TMDBExternalIds? = null,
)

val TMDBMovieDetail.fullPosterUrl: String?
    get() = posterPath?.let { "$TmdbImageBaseUrl$it" }

val TMDBMovieDetail.fullBackdropUrl: String?
    get() = backdropPath?.let { "$TmdbBackdropBaseUrl$it" }

@Serializable
data class TMDBExternalIds(
    @SerialName("imdb_id") val imdbId: String? = null,
    @SerialName("tvdb_id") val tvdbId: Int? = null,
)

@Serializable
data class TMDBTVShowDetail(
    val id: Int = 0,
    val name: String = "",
    val overview: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("last_air_date") val lastAirDate: String? = null,
    @SerialName("episode_run_time") val episodeRunTime: List<Int> = emptyList(),
    val genres: List<TMDBGenre> = emptyList(),
    val seasons: List<TMDBSeason> = emptyList(),
    @SerialName("number_of_seasons") val numberOfSeasons: Int? = null,
    @SerialName("number_of_episodes") val numberOfEpisodes: Int? = null,
    val status: String? = null,
    @SerialName("origin_country") val originCountry: List<String> = emptyList(),
    @SerialName("external_ids") val externalIds: TMDBExternalIds? = null,
)

val TMDBTVShowDetail.fullPosterUrl: String?
    get() = posterPath?.let { "$TmdbImageBaseUrl$it" }

val TMDBTVShowDetail.fullBackdropUrl: String?
    get() = backdropPath?.let { "$TmdbBackdropBaseUrl$it" }

@Serializable
data class TMDBGenre(
    val id: Int = 0,
    val name: String = "",
)

@Serializable
data class TMDBSeason(
    val id: Int = 0,
    val name: String = "",
    @SerialName("season_number") val seasonNumber: Int = 0,
    @SerialName("episode_count") val episodeCount: Int = 0,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("air_date") val airDate: String? = null,
)

@Serializable
data class TMDBEpisode(
    val id: Int = 0,
    val name: String = "",
    val overview: String = "",
    @SerialName("episode_number") val episodeNumber: Int = 0,
    @SerialName("season_number") val seasonNumber: Int = 0,
    @SerialName("air_date") val airDate: String? = null,
    @SerialName("runtime") val runtime: Int? = null,
    @SerialName("still_path") val stillPath: String? = null,
)

val TMDBEpisode.fullStillUrl: String?
    get() = stillPath?.let { "$TmdbImageBaseUrl$it" }

@Serializable
data class TMDBSeasonDetail(
    val id: Int = 0,
    val name: String = "",
    val overview: String = "",
    @SerialName("season_number") val seasonNumber: Int = 0,
    @SerialName("air_date") val airDate: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    val episodes: List<TMDBEpisode> = emptyList(),
)

@Serializable
data class TMDBCreditsResponse(
    val id: Int = 0,
    val cast: List<TMDBCastMember> = emptyList(),
)

@Serializable
data class TMDBCastMember(
    val id: Int = 0,
    val name: String = "",
    val character: String = "",
    @SerialName("profile_path") val profilePath: String? = null,
    val order: Int = 0,
)

val TMDBCastMember.fullProfileUrl: String?
    get() = profilePath?.let { "$TmdbImageBaseUrl$it" }

@Serializable
data class TMDBContentRatingsResponse(
    val results: List<TMDBContentRating> = emptyList(),
)

@Serializable
data class TMDBContentRating(
    @SerialName("iso_3166_1") val countryCode: String = "",
    val rating: String = "",
)

val TMDBContentRatingsResponse.usRating: String?
    get() = results.firstOrNull { it.countryCode.equals("US", ignoreCase = true) }
        ?.rating
        ?.takeIf { it.isNotBlank() }

@Serializable
data class TMDBReleaseDatesResponse(
    val results: List<TMDBReleaseDateCountry> = emptyList(),
)

@Serializable
data class TMDBReleaseDateCountry(
    @SerialName("iso_3166_1") val countryCode: String = "",
    @SerialName("release_dates") val releaseDates: List<TMDBReleaseDateEntry> = emptyList(),
)

@Serializable
data class TMDBReleaseDateEntry(
    val certification: String = "",
    val type: Int = 0,
)

val TMDBReleaseDatesResponse.usCertification: String?
    get() = results.firstOrNull { it.countryCode.equals("US", ignoreCase = true) }
        ?.releaseDates
        ?.firstOrNull { it.certification.isNotBlank() }
        ?.certification

@Serializable
data class TMDBTVShowWithSeasons(
    val show: TMDBTVShowDetail,
    val seasonDetails: List<TMDBSeasonDetail> = emptyList(),
)

