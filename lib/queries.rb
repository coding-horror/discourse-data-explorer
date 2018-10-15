class Queries
  def self.default
    # For each query, add id, name and description here and add sql below
    queries = {
        "most-common-likers": {
            "id": -1,
            "name": "Most Common Likers",
            "description": "Which users like particular other users the most?"
        },
        "most-messages": {
            "id": -2,
            "name": "Who has been sending the most messages in the last week?",
            "description": "tracking down suspicious PM activity"
        },
        "edited-post-spam": {
            "id": -3,
            "name": "Last 500 posts that were edited by TL0/TL1 users",
            "description": "fighting human-driven copy-paste spam"
        },
        "new-topics": {
            "id": -4,
            "name": "New Topics by Category",
            "description": "Lists all new topics ordered by category and creation_date. The query accepts a ‘months_ago’ parameter. It defaults to 0 to give you the stats for the current month."
        },
        "active-topics": {
            "id": -5,
            "name": "Top 100 Active Topics",
            "description": "based on the number of replies, it accepts a ‘months_ago’ parameter, defaults to 1 to give results for the last calendar month."
        },
        "top-likers": {
            "id": -6,
            "name": "Top 100 Likers",
            "description": "returns the top 100 likers for a given monthly period ordered by like_count. It accepts a ‘months_ago’ parameter, defaults to 1 to give results for the last calendar month."
        },
        "quality-users": {
            "id": -7,
            "name": "Top 50 Quality Users",
            "description": "based on post score calculated using reply count, likes, incoming links, bookmarks, time spent and read count."
        },
        "user-participation": {
            "id": -8,
            "name": "User Participation Statistics",
            "description": "Detailed statistics for the most active users"
        }
    }.with_indifferent_access

    queries["most-common-likers"]["sql"] = <<~SQL
    WITH pairs AS (
        SELECT p.user_id liked, pa.user_id liker
        FROM post_actions pa
        LEFT JOIN posts p ON p.id = pa.post_id
        WHERE post_action_type_id = 2
    )
    SELECT liker liker_user_id, liked liked_user_id, count(*)
    FROM pairs
    GROUP BY liked, liker
    ORDER BY count DESC
    SQL

    queries["most-messages"]["sql"] = <<~SQL
    SELECT user_id, count(*) AS message_count
    FROM topics
    WHERE archetype = 'private_message' AND subtype = 'user_to_user'
    AND age(created_at) < interval '7 days'
    GROUP BY user_id
    ORDER BY message_count DESC
    SQL

    queries["edited-post-spam"]["sql"] = <<~SQL
    SELECT
        p.id AS post_id,
        topic_id
    FROM posts p
        JOIN users u
            ON u.id = p.user_id
        JOIN topics t
            ON t.id = p.topic_id
    WHERE p.last_editor_id = p.user_id
        AND p.self_edits > 0
        AND (u.trust_level = 0 OR u.trust_level = 1)
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
        AND t.archetype = 'regular'
    ORDER BY p.updated_at DESC
    LIMIT 500
    SQL

    queries["new-topics"]["sql"] = <<~SQL
    -- [params]
    -- int :months_ago = 1

    WITH query_period as (
        SELECT
            date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' as period_start,
            date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' + INTERVAL '1 month' - INTERVAL '1 second' as period_end
    )

    SELECT
        t.id as topic_id,
        t.category_id
    FROM topics t
    RIGHT JOIN query_period qp
        ON t.created_at >= qp.period_start
            AND t.created_at <= qp.period_end
    WHERE t.user_id > 0
        AND t.category_id IS NOT NULL
    ORDER BY t.category_id, t.created_at DESC
    SQL

    queries["active-topics"]["sql"] = <<~SQL
    -- [params]
    -- int :months_ago = 1

    WITH query_period AS
    (SELECT date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' AS period_start,
                                                        date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' + INTERVAL '1 month' - INTERVAL '1 second' AS period_end)
    SELECT t.id AS topic_id,
        t.category_id,
        COUNT(p.id) AS reply_count
    FROM topics t
    JOIN posts p ON t.id = p.topic_id
    JOIN query_period qp ON p.created_at >= qp.period_start
    AND p.created_at <= qp.period_end
    WHERE t.archetype = 'regular'
    AND t.user_id > 0
    GROUP BY t.id
    ORDER BY COUNT(p.id) DESC, t.score DESC
    LIMIT 100
    SQL

    queries["top-likers"]["sql"] = <<~SQL
    -- [params]
    -- int :months_ago = 1

    WITH query_period AS (
        SELECT
            date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' as period_start,
            date_trunc('month', CURRENT_DATE) - INTERVAL ':months_ago months' + INTERVAL '1 month' - INTERVAL '1 second' as period_end
            )

        SELECT
            ua.user_id,
            count(1) AS like_count
        FROM user_actions ua
        INNER JOIN query_period qp
        ON ua.created_at >= qp.period_start
        AND ua.created_at <= qp.period_end
        WHERE ua.action_type = 1
        GROUP BY ua.user_id
        ORDER BY like_count DESC
        LIMIT 100
    SQL

    queries["quality-users"]["sql"] = <<~SQL
    SELECT sum(p.score) / count(p) AS "average score per post",
        count(p.id) AS post_count,
        p.user_id
    FROM posts p
    JOIN users u ON u.id = p.user_id
    WHERE p.created_at >= CURRENT_DATE - INTERVAL '6 month'
    AND NOT u.admin
    AND u.active
    GROUP BY user_id,
        u.views
    HAVING count(p.id) > 50
    ORDER BY sum(p.score) / count(p) DESC
    LIMIT 50
    SQL

    queries["user-participation"]["sql"] = <<~SQL
    -- [params]
    -- int :from_days_ago = 0
    -- int :duration_days = 30
    WITH t AS (
        SELECT CURRENT_TIMESTAMP - ((:from_days_ago + :duration_days) * (INTERVAL '1 days')) AS START,
            CURRENT_TIMESTAMP - (:from_days_ago * (INTERVAL '1 days')) AS END
    ),
    pr AS (
        SELECT user_id, COUNT(1) AS visits,
            SUM(posts_read) AS posts_read
        FROM user_visits, t
        WHERE posts_read > 0
            AND visited_at > t.START
            AND visited_at < t.
            END
        GROUP BY
            user_id
    ),
    pc AS (
        SELECT user_id, COUNT(1) AS posts_created
        FROM posts, t
        WHERE
            created_at > t.START
            AND created_at < t.
            END
        GROUP BY
            user_id
    ),
    ttopics AS (
        SELECT user_id, posts_count
        FROM topics, t
        WHERE created_at > t.START
            AND created_at < t.
            END
    ),
    tc AS (
        SELECT user_id, COUNT(1) AS topics_created
        FROM ttopics
        GROUP BY user_id
    ),
    twr AS (
        SELECT user_id, COUNT(1) AS topics_with_replies
        FROM ttopics
        WHERE posts_count > 1
        GROUP BY user_id
    ),
    tv AS (
        SELECT user_id,
            COUNT(DISTINCT(topic_id)) AS topics_viewed
        FROM topic_views, t
        WHERE viewed_at > t.START
            AND viewed_at < t.
            END
        GROUP BY user_id
    ),
    likes AS (
        SELECT post_actions.user_id AS given_by_user_id,
            posts.user_id AS received_by_user_id
        FROM t,
            post_actions
            LEFT JOIN
            posts
            ON post_actions.post_id = posts.id
        WHERE
            post_actions.created_at > t.START
            AND post_actions.created_at < t.
            END
            AND post_action_type_id = 2
    ),
    lg AS (
        SELECT given_by_user_id AS user_id,
            COUNT(1) AS likes_given
        FROM likes
        GROUP BY user_id
    ),
    lr AS (
        SELECT received_by_user_id AS user_id,
            COUNT(1) AS likes_received
        FROM likes
        GROUP BY user_id
    ),
    e AS (
        SELECT email, user_id
        FROM user_emails u
        WHERE u.PRIMARY = TRUE
    )
    SELECT
        pr.user_id,
        username,
        name,
        email,
        visits,
        COALESCE(topics_viewed, 0) AS topics_viewed,
        COALESCE(posts_read, 0) AS posts_read,
        COALESCE(posts_created, 0) AS posts_created,
        COALESCE(topics_created, 0) AS topics_created,
        COALESCE(topics_with_replies, 0) AS topics_with_replies,
        COALESCE(likes_given, 0) AS likes_given,
        COALESCE(likes_received, 0) AS likes_received
    FROM pr
    LEFT JOIN tv USING (user_id)
    LEFT JOIN pc USING (user_id)
    LEFT JOIN tc USING (user_id)
    LEFT JOIN twr USING (user_id)
    LEFT JOIN lg USING (user_id)
    LEFT JOIN lr USING (user_id)
    LEFT JOIN e USING (user_id)
    LEFT JOIN users ON pr.user_id = users.id
    ORDER BY
        visits DESC,
        posts_read DESC,
        posts_created DESC
    SQL

  # convert query ids from "mostcommonlikers" to "-1", "mostmessages" to "-2" etc.
  queries.transform_keys!.with_index { |key, idx| "-#{idx + 1}" }
  queries
  end
end
