

query "sqs_queue_input" {
  sql = <<-EOQ
    select
      title as label,
      queue_arn as value,
      json_build_object(
        'account_id', account_id,
        'region', region
      ) as tags
    from
      aws_sqs_queue
    order by
      title;
  EOQ
}

# card queries

query "sqs_queue_encryption" {
  sql = <<-EOQ
    select
      'Encryption' as label,
      case when kms_master_key_id is not null or sqs_managed_sse_enabled then 'Enabled' else 'Disabled' end as value,
      case when kms_master_key_id is not null or sqs_managed_sse_enabled then 'ok' else 'alert' end as "type"
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_content_based_deduplication" {
  sql = <<-EOQ
    select
      'Content Based Deduplication' as label,
      content_based_deduplication as value
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_delay_seconds" {
  sql = <<-EOQ
    select
      'Delay Seconds' as label,
      delay_seconds as value
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_message_retention_seconds" {
  sql = <<-EOQ
    select
      'Message Retention Seconds' as label,
      message_retention_seconds as value
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

# with queries

query "eventbridge_rules_for_sqs_queue" {
  sql = <<-EOQ
    select
      arn as eventbridge_rule_arn
    from
      aws_eventbridge_rule as r,
      jsonb_array_elements(targets) as t
    where
      account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4)
      and t ->> 'Arn' = $1;
  EOQ
}

query "kms_keys_for_sqs_queue" {
  sql = <<-EOQ
    with sqs_queue as (
      select
        kms_master_key_id,
        queue_arn,
        region,
        account_id
      from
        aws_sqs_queue
      where
        account_id = split_part($1, ':', 5)
        and region = split_part($1, ':', 4)
        and queue_arn = $1
      order by
        queue_arn,
        region,
        account_id
    ), kms_keys as (
      select
        aliases,
        arn,
        region,
        account_id
      from
        aws_kms_key
      where
        account_id = split_part($1, ':', 5)
        and region = split_part($1, ':', 4)
      order by
        region,
        account_id
    )
    select
      k.arn as key_arn
    from
      sqs_queue as q,
      kms_keys as k,
      jsonb_array_elements(aliases) as a
    where
      a ->> 'AliasName' = q.kms_master_key_id
      and k.region = q.region
      and k.account_id = q.account_id;
  EOQ
}

query "lambda_functions_for_sqs_queue" {
  sql = <<-EOQ
    select
      arn as function_arn
    from
      aws_lambda_function
    where
      dead_letter_config_target_arn = $1
      and account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4)
  EOQ
}

query "queue_policy_std_for_sqs_queue" {
  sql = <<-EOQ
    select
      policy_std
    from
      aws_sqs_queue
    where
      account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4)
      and queue_arn = $1;
  EOQ
}

query "s3_buckets_for_sqs_queue" {
  sql = <<-EOQ
    select
      b.arn as bucket_arn
    from
      aws_s3_bucket as b,
      jsonb_array_elements(event_notification_configuration -> 'QueueConfigurations') as q
    where
      event_notification_configuration -> 'QueueConfigurations' <> 'null'
      and q ->> 'QueueArn' = $1
      and account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4);
  EOQ
}

query "vpc_endpoints_for_sqs_queue" {
  sql = <<-EOQ
    select
      vpc_endpoint_id
    from
      aws_vpc_endpoint,
      jsonb_array_elements(policy_std -> 'Statement') as s,
      jsonb_array_elements_text(s -> 'Resource') as r
    where
      r = $1
      and account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4);
  EOQ
}

query "vpc_vpcs_for_sqs_queue" {
  sql = <<-EOQ
    select
      vpc_id
    from
      aws_vpc_endpoint,
      jsonb_array_elements(policy_std -> 'Statement') as s,
      jsonb_array_elements_text(s -> 'Resource') as r
    where
      r = $1
      and account_id = split_part($1, ':', 5)
      and region = split_part($1, ':', 4)
  EOQ
}

# table queries

query "sqs_queue_overview" {
  sql = <<-EOQ
    select
      queue_url as "Queue URL",
      title as "Title",
      region as "Region",
      account_id as "Account ID",
      queue_arn as "ARN"
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_tags_detail" {
  sql = <<-EOQ
    with jsondata as (
      select
        tags::json as tags
      from
        aws_sqs_queue
      where
        queue_arn = $1
    )
    select
      key as "Key",
      value as "Value"
    from
      jsondata,
      json_each_text(tags)
    order by
      key;
  EOQ

}

query "sqs_queue_policy" {
  sql = <<-EOQ
    select
      p ->> 'Sid' as "SID",
      p ->> 'Effect' as "Effect",
      p -> 'Principal' as "Principal",
      p -> 'Action'  as "Action",
      p -> 'Resource' as "Resource"

    from
      aws_sqs_queue,
      jsonb_array_elements(policy_std -> 'Statement') as p
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_message" {
  sql = <<-EOQ
    select
      max_message_size as "Max Message Size",
      message_retention_seconds as "Message Retention Seconds",
      visibility_timeout_seconds as "Visibility Timeout Seconds"
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}

query "sqs_queue_encryption_details" {
  sql = <<-EOQ
    select
      case when kms_master_key_id is not null then 'Enabled' else 'Disabled' end as "Encryption",
      kms_master_key_id as "KMS Master Key ID"
    from
      aws_sqs_queue
    where
      queue_arn = $1;
  EOQ

}
