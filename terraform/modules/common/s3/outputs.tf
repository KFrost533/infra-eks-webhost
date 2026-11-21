output "bucket_name" {
  value = aws_s3_bucket.loki_logs.id
}

output "bucket_arn" {
  value = aws_s3_bucket.loki_logs.arn
}
