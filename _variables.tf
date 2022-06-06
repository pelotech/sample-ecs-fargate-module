variable "ecs_cluster_id" {
  description = "id for the cluster the service will be deployed to"
}
variable "name" {
  description = "name for the service and prefix on resources"
}
variable "image_tag" {
  description = "tag or sha for the image"
}
variable "image_name" {
  description = "image name with full repository path"
}
variable "application_port" {
  default = 80
}
variable "enable_https" {
  default = true
}
variable "enable_https_redirect" {
  default = true
}
variable "acm_ssl_cert_arn" {
  description = "arn to the tls cert for the alb"
}
variable "vpc_id" {
  description = "vpc id for deploying all the resources"
}
variable "region" {}
variable "public_subnet_ids" {}
variable "database_security_group_id" {
  description = "database security group if needed"
  default = ""
}
variable "owner" {}
variable "environment" {}
variable "task_container_definitions_file" {
  description = "Container definitions template file location relative to path.module"
  default     = "templates/container_definitions.json"
}
variable "task_command" {
  description = "The command that is passed to the container."
  type        = list(string)
  default     = []
}
variable "environment_variables" {
  type        = list(any)
  description = "list of env var to inject ie [{name = ENV_NAME, value = ENV_VALUE}]"
  default     = []
}
variable "secrets_from" {
  type        = list(any)
  description = "list of secrects to inject ie [ {\"name\" = \"ENV_VAR\", \"valueFrom\" =\"arn:to:secretmanager:key\"}]"
  default     = []
}