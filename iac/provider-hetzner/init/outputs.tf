// ---
// Network
// ---
output "network_id" {
  value = module.network.network_id
}

output "subnet_id" {
  value = module.network.subnet_id
}

// ---
// SSH
// ---
output "ssh_key_id" {
  value = hcloud_ssh_key.cluster.id
}

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
