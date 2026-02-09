query "rss_steampipe_io_blog_post_totals" {
  sql = <<-EOQ
    select
      count(*) as "Total Blog Posts"
    from
      rss_item
    where
      feed_link = 'https://steampipe.io/blog/feed.xml'
  EOQ
}

dashboard "dashboard_tutorial" {
  title = "Dashboard Tutorial"
  text {
    value = "This will guide you through the key concepts of building your own dashboards."
  }

  card {
    sql = query.rss_steampipe_io_blog_post_totals.sql
  }
}

