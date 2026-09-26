# FrostPlay
An iOS streaming app with TV, Movies, and Anime

# Freebuff Build  Description
- An iOS app that will be build and tested myself, NOT a typescript web app,
- UI will not be bloated, It will contain a ui Similar to things like dulo.cx, Where you pick a stremaing service (netflix, disney+, hulu, etc) And will display shows/movies/anime from those platforms, Using TMDB/Anilist, however each one will return the corrisponding movie id, only sorting streaming service shows, similar to dulo.cx,
- will include: Home, Search, Library, Recently watched, Settings,
- Settings will include: Themes, Source Choosing, Prefered streams for anime (Dub, Sub). but settings will include sub categories for specific settings, like you click a subcategory and it shows the corresponding setting options
- More features will br added, And if you find any bugs, possible convinient additions or recommended additions, feel free to tell me

## Initial implementation decisions
- Native SwiftUI app targeting iOS 17+.
- No accounts; library, settings, and recently watched data are stored locally.
- TMDB provides movie/TV metadata and AniList provides anime metadata.
- VidLink is the initial movie/TV playback source; MegaPlay is the initial anime source.
- Anime playback addresses MegaPlay directly by AniList ID (MAL ID as fallback) through its documented `/stream/ani/{anilist-id}/{episode}/{language}` and `/stream/mal/{mal-id}/{episode}/{language}` routes. Playback therefore does not depend on resolving Anikoto's internal catalog ID out of its bounded "recent-anime" feed; Anikoto remains only a last-resort resolver for titles with no external ID.
- VidLink and MegaPlay document embed-based playback, so the first player uses `WKWebView`. A hybrid playback layer is also prepared for direct HLS/MP4 sources through `AVPlayer`.
- Source adapters are isolated behind a shared resolver so source priority and fallback behavior can be changed in Settings.
- Playback sources are separated by title type. Settings stores a default source for anime and a separate default for movies/TV, and the resolver only offers MegaPlay to anime (addressed by AniList/MAL ID) and VidLink/MoviesAPI to TMDB titles, so a TMDB title can never attempt MegaPlay. The source picker on a title writes the default for that title type.
- AniList owns anime display metadata and episode rows; titles that publish no per-episode title get positional episode numbering instead of an empty list.
- TMDB requires a `TMDB_API_KEY` value in the app target's configuration; it must not be hard-coded into source files.
