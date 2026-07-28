// ---
// Buckets
// ---
output "setup_bucket_name" {
  value = minio_s3_bucket.setup.bucket
}

output "fc_template_build_cache_bucket_name" {
  value = minio_s3_bucket.fc_template_build_cache.bucket
}

output "fc_template_bucket_name" {
  value = minio_s3_bucket.fc_templates.bucket
}

output "fc_env_pipeline_bucket_name" {
  value = minio_s3_bucket.fc_env_pipeline.bucket
}

output "fc_kernels_bucket_name" {
  value = minio_s3_bucket.fc_kernels.bucket
}

output "fc_versions_bucket_name" {
  value = minio_s3_bucket.fc_versions.bucket
}

output "loki_bucket_name" {
  value = minio_s3_bucket.loki_storage.bucket
}

output "clickhouse_backups_bucket_name" {
  value = minio_s3_bucket.clickhouse_backups.bucket
}
