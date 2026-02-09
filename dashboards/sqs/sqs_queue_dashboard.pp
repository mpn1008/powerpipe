
# Card Queries

query "sqs_queue_count" {
  sql = <<-EOQ
    select count(*) as "Queues" from aws_sqs_queue;
  EOQ
}

query "sqs_queue_fifo_count" {
  sql = <<-EOQ
    select count(*) as "FIFO Queues" from aws_sqs_queue where fifo_queue;
  EOQ
}

query "sqs_queue_unencrypted_count" {
  sql = <<-EOQ
    select
      count(*) as value,
      'Unencrypted' as label,
      case count(*) when 0 then 'ok' else 'alert' end as "type"
    from
      aws_sqs_queue
    where
      kms_master_key_id is null and not sqs_managed_sse_enabled;
  EOQ
}

query "sqs_queue_anonymous_access_count" {
  sql = <<-EOQ
      select
        count(*) as value,
        'Publicly Accessible' as label,
        case count(*) when 0 then 'ok' else 'alert' end as "type"
      from
        aws_sqs_queue,
        jsonb_array_elements(policy_std -> 'Statement') as s,
        jsonb_array_elements_text(s -> 'Principal' -> 'AWS') as p,
        string_to_array(p, ':') as pa,
        jsonb_array_elements_text(s -> 'Action') as a
      where
        s ->> 'Effect' = 'Allow'
        and (
          pa[5] != account_id
          or p = '*'
        );
  EOQ
}

query "sqs_queue_cost_mtd" {
  sql = <<-EOQ
    select
      'Cost - MTD' as label,
      sum(unblended_cost_amount)::numeric::money as value
    from
      aws_cost_by_service_usage_type_monthly as c
    where
      service = 'Amazon Simple Queue Service'
      and period_end > date_trunc('month', CURRENT_DATE::timestamp);
  EOQ
}

# Assessment Queries

query "sqs_queue_by_encryption_status" {
  sql = <<-EOQ
    select
      encryption_status,
      count(*)
    from (
      select kms_master_key_id,
        case when kms_master_key_id is not null or sqs_managed_sse_enabled then
          'enabled'
        else
          'disabled'
        end encryption_status
      from
        aws_sqs_queue) as t
    group by
      encryption_status
    order by
      encryption_status desc;
  EOQ
}

query "sqs_queue_by_dlq_status" {
  sql = <<-EOQ
    select
      redrive_policy_status,
      count(*)
    from (
      select redrive_policy,
        case when redrive_policy is not null then
          'configured'
        else
          'not configured'
        end redrive_policy_status
      from
        aws_sqs_queue) as t
    group by
      redrive_policy_status
    order by
      redrive_policy_status desc;
  EOQ
}

query "sqs_queue_public_access_status" {
  sql = <<-EOQ
    with public_access as (
      select
      title
    from
      aws_sqs_queue,
      jsonb_array_elements(policy_std -> 'Statement') as s,
      jsonb_array_elements_text(s -> 'Principal' -> 'AWS') as p,
      string_to_array(p, ':') as pa,
      jsonb_array_elements_text(s -> 'Action') as a
    where
      s ->> 'Effect' = 'Allow'
      and (
        pa[5] != account_id
        or p = '*'
      )
    ),
    public_access_status as (
      select
        case
          when a.title is null or policy_std is null then 'private'
        else
          'public'
        end public_access_status
      from
        aws_sqs_queue as q
        left join public_access as a on q.title = a.title
      )
      select
        public_access_status,
        count(*)
      from
        public_access_status
      group by
        public_access_status
      order by
        public_access_status desc;
  EOQ
}

# Cost Queries

query "sqs_queue_monthly_forecast_table" {
  sql = <<-EOQ
    with monthly_costs as (
      select
        period_start,
        period_end,
        case
          when date_trunc('month', period_start) = date_trunc('month', CURRENT_DATE::timestamp) then 'Month to Date'
          when date_trunc('month', period_start) = date_trunc('month', CURRENT_DATE::timestamp - interval '1 month') then 'Previous Month'
          else to_char (period_start, 'Month')
        end as period_label,
        period_end::date - period_start::date as days,
        sum(unblended_cost_amount)::numeric::money as unblended_cost_amount,
        (sum(unblended_cost_amount) / (period_end::date - period_start::date ) )::numeric::money as average_daily_cost,
        date_part('days', date_trunc ('month', period_start) + '1 MONTH'::interval  - '1 DAY'::interval ) as days_in_month,
        sum(unblended_cost_amount) / (period_end::date - period_start::date ) * date_part('days', date_trunc ('month', period_start) + '1 MONTH'::interval  - '1 DAY'::interval )::numeric::money  as forecast_amount
      from
        aws_cost_by_service_usage_type_monthly as c
      where
        service = 'Amazon Simple Queue Service'
        and date_trunc('month', period_start) >= date_trunc('month', CURRENT_DATE::timestamp - interval '1 month')
        group by
        period_start,
        period_end
    )
    select
      period_label as "Period",
      unblended_cost_amount as "Cost",
      average_daily_cost as "Daily Avg Cost"
    from
      monthly_costs

    union all
    select
      'This Month (Forecast)' as "Period",
      (select forecast_amount from monthly_costs where period_label = 'Month to Date') as "Cost",
      (select average_daily_cost from monthly_costs where period_label = 'Month to Date') as "Daily Avg Cost";
  EOQ
}

query "sqs_queue_cost_per_month" {
  sql = <<-EOQ
    select
       to_char(period_start, 'Mon-YY') as "Month",
       sum(unblended_cost_amount)::numeric::money as "Unblended Cost"
    from
      aws_cost_by_service_usage_type_monthly
    where
      service = 'Amazon Simple Queue Service'
    group by
      period_start
    order by
      period_start;
  EOQ
}

# Analysis Queries

query "sqs_queue_by_account" {
  sql = <<-EOQ
    select
      a.title as "Account",
      count(i.*) as "total"
    from
      aws_sqs_queue as i,
      aws_account as a
    where
      a.account_id = i.account_id
    group by
      a.title
    order by 
      count(i.*) desc;
  EOQ
}

query "sqs_queue_by_region" {
  sql = <<-EOQ
    select
      region,
      count(i.*) as total
    from
      aws_sqs_queue as i
    group by
      region;
  EOQ
}

query "sqs_queue_by_type" {
  sql = <<-EOQ
    select
      case
        when fifo_queue then 'FIFO'
        else 'Standard'
      end as queue_type,
      count(i.*) as total
    from
      aws_sqs_queue as i
    group by
      fifo_queue;
  EOQ
}
