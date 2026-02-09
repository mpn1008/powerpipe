
query "sqs_queue_encryption_table" {
  sql = <<-EOQ
    select
      q.title as "Queue",
      case when kms_master_key_id is not null or sqs_managed_sse_enabled then 'Enabled' else null end as "Encryption",
      q.kms_master_key_id as "KMS Key ID",
      q.sqs_managed_sse_enabled as "SQS Managed SSE",
      a.title as "Account",
      q.account_id as "Account ID",
      q.region as "Region",
      q.queue_arn as "ARN"
    from
      aws_sqs_queue as q,
      aws_account as a
    where
      q.account_id = a.account_id
    order by
      q.title;
  EOQ
}
