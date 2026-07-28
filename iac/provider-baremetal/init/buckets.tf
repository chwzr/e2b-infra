resource "minio_s3_bucket" "setup" {
  bucket = "${var.bucket_prefix}instance-setup"
  acl    = "private"
}

resource "minio_s3_bucket" "fc_kernels" {
  bucket = "${var.bucket_prefix}fc-kernels"
  acl    = "private"
}

resource "minio_s3_bucket" "fc_versions" {
  bucket = "${var.bucket_prefix}fc-versions"
  acl    = "private"
}

resource "minio_s3_bucket" "fc_env_pipeline" {
  bucket = "${var.bucket_prefix}fc-env-pipeline"
  acl    = "private"
}

resource "minio_s3_bucket" "fc_templates" {
  bucket = "${var.bucket_prefix}fc-templates"
  acl    = "private"
}

resource "minio_s3_bucket" "fc_template_build_cache" {
  bucket = "${var.bucket_prefix}fc-build-cache"
  acl    = "private"
}

resource "minio_s3_bucket" "loki_storage" {
  bucket = "${var.bucket_prefix}loki-storage"
  acl    = "private"
}

resource "minio_s3_bucket" "clickhouse_backups" {
  bucket = "${var.bucket_prefix}clickhouse-backups"
  acl    = "private"
}
