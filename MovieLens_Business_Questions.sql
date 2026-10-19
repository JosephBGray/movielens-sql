-- MovieLens Dataset Project
-- Business Questions

-- 1. Which genres have the highest average rating vs. highest volume of ratings?

-- Ordered by average rating.
SELECT
    mg.genre,
    COUNT(r.rating) AS total_ratings,
    ROUND(AVG(r.rating), 2) AS avg_rating
FROM movielens.movie_genres mg
JOIN movielens.ratings r ON mg.movieId = r.movieId
WHERE mg.genre != '(no genres listed)'
GROUP BY mg.genre
ORDER BY avg_rating DESC;

-- Ordered by volume of ratings.
SELECT
    mg.genre,
    COUNT(r.rating) AS total_ratings,
    ROUND(AVG(r.rating), 2) AS avg_rating
FROM movielens.movie_genres mg
JOIN movielens.ratings r ON mg.movieId = r.movieId
WHERE mg.genre != '(no genres listed)'
GROUP BY mg.genre
ORDER BY total_ratings DESC;

-- Here we can see the most/least-rated genres and the highest/lowest-rated genres.
-- There does not seem to be a strong correlation between the two metrics.

-- Ranking genres by both metrics side by side, to see how much the rankings diverge.
WITH genre_stats AS (
    SELECT
        mg.genre,
        COUNT(r.rating) AS total_ratings,
        ROUND(AVG(r.rating), 2) AS avg_rating
    FROM movielens.movie_genres mg
    JOIN movielens.ratings r ON mg.movieId = r.movieId
    WHERE mg.genre != '(no genres listed)'
    GROUP BY mg.genre
)
SELECT
    genre,
    total_ratings,
    avg_rating,
    RANK() OVER (ORDER BY total_ratings DESC) AS volume_rank,
    RANK() OVER (ORDER BY avg_rating DESC) AS rating_rank,
    CAST(RANK() OVER (ORDER BY total_ratings DESC) AS SIGNED)
        - CAST(RANK() OVER (ORDER BY avg_rating DESC) AS SIGNED) AS rank_gap
FROM genre_stats
ORDER BY total_ratings DESC;

-- Initial insights: There is a general trend for the most popular genres (assuming more ratings = more popular) to have a lower average rating, while more niche genres tend to rate higher.
-- Drama is the clear exception to the trend. Despite being the most-rated genre, it still ranks #5 in average rating. (Compare to Comedy with 2nd most ratings but ranked #18 in average rating.)
-- Film-Noir is #1 in average rating but has the lowest volume of ratings.
-- Takeaway: niche-genre viewers likely seek out movies they already expect to like, while mainstream genres draw a broader, less selective audience.
-- This is a possible explanation of the volume vs. rating trend.

-- --------------------

-- 2. Has average rating / rating volume changed over the decades (overall, and by genre)?

-- Overall trend by decade, all genres combined
SELECT
    FLOOR(m.release_year / 10) * 10 AS decade,
    COUNT(r.rating) AS total_ratings,
    ROUND(AVG(r.rating), 2) AS avg_rating
FROM movielens.movies m
JOIN movielens.ratings r ON m.movieId = r.movieId
WHERE m.release_year IS NOT NULL
GROUP BY decade
ORDER BY decade;

-- The number of ratings peaks for movies from the 1990s, then tapers off again for the following decades.

-- Same trend, broken out by genre
SELECT
    mg.genre,
    FLOOR(m.release_year / 10) * 10 AS decade,
    COUNT(r.rating) AS total_ratings,
    ROUND(AVG(r.rating), 2) AS avg_rating
FROM movielens.movies m
JOIN movielens.ratings r ON m.movieId = r.movieId
JOIN movielens.movie_genres mg ON m.movieId = mg.movieId
WHERE m.release_year IS NOT NULL
  AND mg.genre != '(no genres listed)'
GROUP BY mg.genre, decade
ORDER BY mg.genre, decade;

-- At a glance, the trend holds genre-to-genre. Comedy, for example: 1890s movies have
-- just 198 ratings, 1990s movies peak at 4,311,767, then taper to 1,262,063 by the 2010s.

-- Quickly checking the 1890s bucket, since that era seemed very early. Confirmed to reflect real early films, not a data extraction error.
SELECT movieId, title_clean, release_year
FROM movielens.movies
WHERE release_year BETWEEN 1890 AND 1899;

-- Supplementary movie count per decade to see how this aligns with the ratings per decade trend.
SELECT
    FLOOR(release_year / 10) * 10 AS decade,
    COUNT(*) AS total_movies
FROM movielens.movies
WHERE release_year IS NOT NULL
GROUP BY decade
ORDER BY decade;

-- Interestingly, there were more movies in the 2000s and even more in the 2010s, despite the 1990s having the highest number of ratings.
-- Unlikely that this is because movie-watching peaked in the 1990s.
-- We can possibly attribute this to cumulative ratings (a movie from 1992 has been around longer to receive more ratings than a movie from 2015 has).
-- Another possible cause of this could be that the popularity of the MovieLens platform peaked in the late-90s / early-2000s, meaning more users were rating on the site during this time.

-- This query investigates the MovieLens user base - how many ratings per movie were coming through by decade?
SELECT
    FLOOR(m.release_year / 10) * 10 AS decade,
    COUNT(DISTINCT m.movieId) AS total_movies,
    COUNT(r.rating) AS total_ratings,
    ROUND(COUNT(r.rating) / COUNT(DISTINCT m.movieId), 1) AS avg_ratings_per_movie
FROM movielens.movies m
JOIN movielens.ratings r ON m.movieId = r.movieId
WHERE m.release_year IS NOT NULL
GROUP BY decade
ORDER BY decade;

-- Supports the platform-activity theory (e.g., 1990s: 1,357 ratings/movie vs. 2010s: 165 ratings/movie).
-- The dataset can't directly confirm MovieLens user activity over time,
-- so this is the most likely explanation, not a directly proven cause.

-- --------------------

-- 3. Do a small group of "power users" drive a disproportionate share of ratings?

-- This shows how many ratings each user has given.
SELECT
    r.userId,
    COUNT(r.rating) AS total_ratings
FROM movielens.ratings r
GROUP BY r.userId
ORDER BY total_ratings DESC
LIMIT 20;

-- Breaking into decile and percentage to see how ratings are distributed amongst users.
WITH user_totals AS (
    SELECT
        userId,
        COUNT(*) AS total_ratings
    FROM movielens.ratings
    GROUP BY userId
),
ranked AS (
    SELECT
        userId,
        total_ratings,
        NTILE(10) OVER (ORDER BY total_ratings DESC) AS decile
    FROM user_totals
)
SELECT
    decile,
    COUNT(*) AS num_users,
    SUM(total_ratings) AS ratings_from_group,
    ROUND(SUM(total_ratings) * 100.0 / SUM(SUM(total_ratings)) OVER (), 1) AS pct_of_all_ratings
FROM ranked
GROUP BY decile
ORDER BY decile;

-- The top 10% of users are responsible for 47% of all ratings.
-- Zooming into percentiles within this top decile in order to see concentration.

WITH user_totals AS (
    SELECT
        userId,
        COUNT(*) AS total_ratings
    FROM movielens.ratings
    GROUP BY userId
),
ranked AS (
    SELECT
        userId,
        total_ratings,
        NTILE(100) OVER (ORDER BY total_ratings DESC) AS percentile
    FROM user_totals
)
SELECT
    percentile,
    COUNT(*) AS num_users,
    SUM(total_ratings) AS ratings_from_group,
    ROUND(SUM(total_ratings) * 100.0 / SUM(SUM(total_ratings)) OVER (), 1) AS pct_of_all_ratings
FROM ranked
WHERE percentile <= 10
GROUP BY percentile
ORDER BY percentile;

-- The top 1% of users is responsible for 26.6% of all ratings.

-- This shows overall spread of ratings-per-user across the whole platform,
-- for broader context alongside the decile/percentile concentration numbers above.
SELECT
    MIN(total_ratings) AS min_ratings,
    MAX(total_ratings) AS max_ratings,
    ROUND(AVG(total_ratings), 1) AS avg_ratings
FROM (
    SELECT userId, COUNT(*) AS total_ratings
    FROM movielens.ratings
    GROUP BY userId
) user_totals;

-- This gives a concise, clear depiction of how the top user stacks up against the bottom user and the average user.
-- Note: avg_ratings is the mean, which we know to be inflated by the small group of power users.

-- A median would be a more accurate anchor, so showing that now for comparison sake.

SELECT
    total_ratings AS median_ratings
FROM (
    SELECT
        userId,
        COUNT(*) AS total_ratings,
        ROW_NUMBER() OVER (ORDER BY COUNT(*)) AS rn,
        COUNT(*) OVER () AS total_users
    FROM movielens.ratings
    GROUP BY userId
) ranked
WHERE rn = FLOOR((total_users + 1) / 2);

-- Overall takeaway: ratings activity is heavily concentrated. The top 10% of users
-- generate 47% of all ratings, and the top 1% alone account for 26.6%.
-- A small group of power users drives much of the platform's data.
-- This finding might change the way we use or think about this data. It is not reflective of the general public, or even the general MovieLens audience.
-- It is still valuable data, but it reflects a specific population.

-- Sensitivity check: does the genre rating pattern from Question 1 hold up if we exclude the top 1% most active users?
-- This should give an idea of just how much the top 1% is skewing the data overall and give insight on just how reliable the set is as a whole.

WITH user_totals AS (
    SELECT
        userId,
        COUNT(*) AS total_ratings
    FROM movielens.ratings
    GROUP BY userId
),
ranked_users AS (
    SELECT
        userId,
        NTILE(100) OVER (ORDER BY total_ratings DESC) AS percentile
    FROM user_totals
),
filtered_ratings AS (
    SELECT r.*
    FROM movielens.ratings r
    JOIN ranked_users ru ON r.userId = ru.userId
    WHERE ru.percentile > 1  -- excludes the top 1% of raters
)
SELECT
    mg.genre,
    COUNT(fr.rating) AS total_ratings,
    ROUND(AVG(fr.rating), 2) AS avg_rating
FROM movielens.movie_genres mg
JOIN filtered_ratings fr ON mg.movieId = fr.movieId
WHERE mg.genre != '(no genres listed)'
GROUP BY mg.genre
ORDER BY avg_rating DESC;

-- Comparing this result against Question 1 (average rating vs. volume of ratings):
-- Film-Noir still has the least number of ratings while maintaining the highest avg_rating,
-- and Drama still has the highest volume of ratings while maintaining the 5th highest avg_rating.
-- Otherwise, the general trend of mainstream genres having a lower average rating holds up.
-- Since the pattern holds even without the top 1%, the genre trend looks like a real
-- signal, not an artifact of a small, highly active subset.

-- --------------------

-- 4. What are the most commonly applied tags overall, and do genres attract different tag vocabularies?

-- This shows the most used tags overall.
SELECT
    tag,
    COUNT(*) AS times_used
FROM movielens.tags
GROUP BY tag
ORDER BY times_used DESC
LIMIT 20;

-- Surprised "atmospheric" ranks so high at number 2,
-- so checking if popularity is driven by a few prolific taggers or by broad usage.

SELECT
    COUNT(*) AS total_uses,
    COUNT(DISTINCT userId) AS distinct_users
FROM movielens.tags
WHERE tag = 'atmospheric';

-- 2,205 distinct users applied this tag, confirming broad usage.

-- Top tags within a specific genre — swap genre to explore others
SELECT
    t.tag,
    COUNT(*) AS times_used
FROM movielens.tags t
JOIN movielens.movie_genres mg ON t.movieId = mg.movieId
WHERE mg.genre = 'Horror'
GROUP BY t.tag
ORDER BY times_used DESC
LIMIT 15;

-- Top 5 tags per genre, side by side
WITH genre_tag_counts AS (
    SELECT
        mg.genre,
        t.tag,
        COUNT(*) AS times_used,
        RANK() OVER (PARTITION BY mg.genre ORDER BY COUNT(*) DESC) AS tag_rank
    FROM movielens.tags t
    JOIN movielens.movie_genres mg ON t.movieId = mg.movieId
    WHERE mg.genre != '(no genres listed)'
    GROUP BY mg.genre, t.tag
)
SELECT genre, tag, times_used
FROM genre_tag_counts
WHERE tag_rank <= 5
ORDER BY genre, tag_rank;

-- The more commonly used tags (e.g., Sci-Fi, Atmospheric, Action, Comedy, Funny)
-- seem to be used across a number of different genres, explaining why they are used more often.
-- On the other hand, the more niche genres can have some very specific, less-used tags
-- (e.g., Quentin Tarantino is a top 5 tag for the Western genre, and neo-noir is a top 5 tag for the Film-Noir genre).
