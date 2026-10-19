-- MovieLens Dataset Project
-- Cleaning

-- Checking for and removing duplicate primary keys from columns.

-- movies:
SELECT movieId, COUNT(*)
FROM movielens.movies
GROUP BY movieId
HAVING COUNT(*) > 1;

-- links
SELECT movieId, COUNT(*)
FROM movielens.links
GROUP BY movieId
HAVING COUNT(*) > 1;

-- ratings: composite PK is userId + movieId
SELECT userId, movieId, COUNT(*)
FROM movielens.ratings
GROUP BY userId, movieId
HAVING COUNT(*) > 1;

-- tags: composite check on userId + movieId + tag
SELECT userId, movieId, tag, COUNT(*)
FROM movielens.tags
GROUP BY userId, movieId, tag
HAVING COUNT(*) > 1;

-- Only the tags table returned 4 duplicates.
-- Since it's only 4, manually inspecting each one to see if they need to be removed.

SELECT * FROM movielens.tags
WHERE userId = 78213 AND movieId = 143863;

SELECT * FROM movielens.tags
WHERE userId = 147560 AND movieId = 97688;

SELECT * FROM movielens.tags
WHERE userId = 155001 AND movieId = 172549;

SELECT * FROM movielens.tags
WHERE userId = 159555 AND movieId = 318;

-- Confirmed these are not true duplicates. MySQL's default collation treats accented characters as equal (e.g., "Zdzislaw" vs. "Zdzisław").
-- All rows contain different tag text and represent distinct submissions.
-- No deduping performed.

-- Checking for NULLs and empty strings.

-- movies
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN movieId IS NULL THEN 1 ELSE 0 END) AS missing_movieId,
    SUM(CASE WHEN title IS NULL OR title = '' THEN 1 ELSE 0 END) AS missing_title,
    SUM(CASE WHEN genres IS NULL OR genres = '' THEN 1 ELSE 0 END) AS missing_genres
FROM movielens.movies;

-- links
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN movieId IS NULL THEN 1 ELSE 0 END) AS missing_movieId,
    SUM(CASE WHEN imdbId IS NULL THEN 1 ELSE 0 END) AS missing_imdbId,
    SUM(CASE WHEN tmdbId IS NULL THEN 1 ELSE 0 END) AS missing_tmdbId
FROM movielens.links;

-- ratings
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN userId IS NULL THEN 1 ELSE 0 END) AS missing_userId,
    SUM(CASE WHEN movieId IS NULL THEN 1 ELSE 0 END) AS missing_movieId,
    SUM(CASE WHEN rating IS NULL THEN 1 ELSE 0 END) AS missing_rating
FROM movielens.ratings;

-- tags
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN userId IS NULL THEN 1 ELSE 0 END) AS missing_userId,
    SUM(CASE WHEN movieId IS NULL THEN 1 ELSE 0 END) AS missing_movieId,
    SUM(CASE WHEN tag IS NULL OR tag = '' THEN 1 ELSE 0 END) AS missing_tag
FROM movielens.tags;

-- Surprisingly, no NULLs or empty strings.

-- The title column has the release year embedded in the movie title
-- Splitting it out into two columns for easier exploration and analysis

-- Adding new columns
ALTER TABLE movielens.movies
ADD COLUMN release_year INT,
ADD COLUMN title_clean VARCHAR(255);

-- Extracting the year
UPDATE movielens.movies
SET release_year = CAST(
    REGEXP_REPLACE(
        REGEXP_SUBSTR(title, '\\([0-9]{4}\\)$'),
        '[()]', ''
    ) AS UNSIGNED
)
WHERE title REGEXP '\\([0-9]{4}\\)$';

-- Extracting the title
UPDATE movielens.movies
SET title_clean = TRIM(
    REGEXP_REPLACE(title, '\\s*\\([0-9]{4}\\)$', '')
)
WHERE title REGEXP '\\([0-9]{4}\\)$';

-- Testing to see if any years did not extract properly.
SELECT movieId, title, release_year, title_clean
FROM movielens.movies
WHERE release_year IS NULL;

-- 771 results did not extract properly.

-- Using HEX to check for hidden trailing characters at the byte level
SELECT movieId, title, HEX(title), CHAR_LENGTH(title)
FROM movielens.movies
WHERE title LIKE 'Love Letter%';

-- Extracting year again but with TRIM built in.
UPDATE movielens.movies
SET release_year = CAST(
    REGEXP_REPLACE(
        REGEXP_SUBSTR(TRIM(title), '\\([0-9]{4}\\)$'),
        '[()]', ''
    ) AS UNSIGNED
)
WHERE release_year IS NULL
  AND TRIM(title) REGEXP '\\([0-9]{4}\\)$';

-- This reduced it to 617 NULLs. Checking them next.

-- This shows titles with no year pattern at all anywhere
SELECT movieId, title
FROM movielens.movies
WHERE release_year IS NULL
  AND title NOT REGEXP '\\([0-9]{4}\\)'
;

-- Result: 615

-- This shows titles with a year that were not caught by original query.
SELECT movieId, title
FROM movielens.movies
WHERE release_year IS NULL
  AND title REGEXP '\\([0-9]{4}\\)'
;

-- Result: 2, which accounts for all 617. Adjusting these two manually.

UPDATE movielens.movies
SET release_year = 1983,
    title_clean = 'Mona and the Time of Burning Love (Mona ja palavan rakkauden aika)'
WHERE movieId = 98063;

UPDATE movielens.movies
SET release_year = 1957,
    title_clean = 'The Naked Truth (Your Past Is Showing)'
WHERE movieId = 141628;

-- The remaining 615 titles have no year embedded at all (missing data).
-- Left as NULL rather than guessed.

-- Normalizing the pipe-separated genres column, which can't be cleanly queried by genre in standard SQL.
-- Split into a separate movie_genres junction table to allow proper filtering, joining, and aggregation by genre.

CREATE TABLE movielens.movie_genres (
    movieId INT,
    genre VARCHAR(50)
);

INSERT INTO movielens.movie_genres (movieId, genre)
WITH RECURSIVE split_genres AS (
    -- Anchor: start with the full genre string, position 1
    SELECT
        movieId,
        genres,
        SUBSTRING_INDEX(genres, '|', 1) AS genre,
        SUBSTRING(genres, LENGTH(SUBSTRING_INDEX(genres, '|', 1)) + 2) AS remaining
    FROM movielens.movies
    WHERE genres IS NOT NULL AND genres != ''

    UNION ALL

    SELECT
        movieId,
        remaining,
        SUBSTRING_INDEX(remaining, '|', 1) AS genre,
        SUBSTRING(remaining, LENGTH(SUBSTRING_INDEX(remaining, '|', 1)) + 2) AS remaining
    FROM split_genres
    WHERE remaining != ''
)
SELECT movieId, genre
FROM split_genres;

-- Running a few sample queries to make sure the recursive CTE for genre worked.
SELECT COUNT(*) FROM movielens.movie_genres;
SELECT COUNT(DISTINCT movieId) FROM movielens.movie_genres;
SELECT * FROM movielens.movie_genres WHERE movieId = 1;

-- Finding what happened to the movies with no genre
SELECT COUNT(*) FROM movielens.movies
WHERE genres = '(no genres listed)';

-- Checking for hidden characters.
SELECT movieId, genres, HEX(genres), CHAR_LENGTH(genres)
FROM movielens.movies
WHERE genres LIKE '%no genres%'
LIMIT 1;

SELECT COUNT(*) FROM movielens.movies
WHERE genres LIKE '%\r';

-- Every row in the original movies table had this hidden character.
-- The CSV uses Windows line endings (\r\n), but LOAD DATA INFILE split on \n only,
-- leaving a trailing \r on the last column (genres) of every row. Stripping it here.
-- (Could also be prevented at import with LINES TERMINATED BY '\r\n'.)

UPDATE movielens.movies
SET genres = TRIM(TRAILING '\r' FROM genres);

-- Rebuilding movie_genres with newly cleaned column.

TRUNCATE TABLE movielens.movie_genres;

INSERT INTO movielens.movie_genres (movieId, genre)
WITH RECURSIVE split_genres AS (
    SELECT
        movieId,
        genres,
        SUBSTRING_INDEX(genres, '|', 1) AS genre,
        SUBSTRING(genres, LENGTH(SUBSTRING_INDEX(genres, '|', 1)) + 2) AS remaining
    FROM movielens.movies
    WHERE genres IS NOT NULL AND genres != ''

    UNION ALL

    SELECT
        movieId,
        remaining,
        SUBSTRING_INDEX(remaining, '|', 1) AS genre,
        SUBSTRING(remaining, LENGTH(SUBSTRING_INDEX(remaining, '|', 1)) + 2) AS remaining
    FROM split_genres
    WHERE remaining != ''
)
SELECT movieId, genre
FROM split_genres;

SELECT * FROM movielens.movies
WHERE genres = '(no genres listed)';

SELECT * FROM movielens.movie_genres
WHERE genre = '(no genres listed)';

-- Both tables show 7080 movies with this value, confirming the junction table
-- correctly carried the placeholder through after the \r fix and rebuild.

-- Checking whether the title column had the same issue, in case it slipped past earlier checks.
SELECT COUNT(*) FROM movielens.movies
WHERE title LIKE '%\r';

-- It did not. No action needed.

-- Validity check on the ratings table
SELECT rating, COUNT(*)
FROM movielens.ratings
WHERE rating < 0.5 OR rating > 5.0
GROUP BY rating;

SELECT rating, COUNT(*)
FROM movielens.ratings
WHERE rating * 2 != FLOOR(rating * 2)
GROUP BY rating;

-- Both checks returned 0 rows, confirming all 32M ratings fall within the valid
-- 0.5–5.0 range on proper half-star increments.
