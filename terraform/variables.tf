variable "aws_access_key" {
    description = "AWS Access KEy"
    type        = string
    sensitive   = true
}

variable "aws_secret_key" {
    description = "AWS Secret Key"
    type        = string
    sensitive   = true
}

variable "aws_region" {
    description = "AWS Region"
    type = string
    default = "eu-central-1"
}

variable "aws_az" {
    description = "AWS Availability Zone"
    type = string
    default = "eu-central-1a"
}

variable "aws_route53_domain_name" {
    description = "DNS Domain"
    type = string
    sensitive = true
}

variable "aws_route53_zone_id" {
    description = "DNS Zone"
    type = string
    sensitive = true
}

variable "k8s_master_count" {
    description = "Count of K8S Master Nodes"
    type = number
    default = 1
}

variable "k8s_worker_count" {
    description = "Count of K8S Worker Nodes"
    type = number
    default = 3
}

variable "bastion_fqdn_list" {
  description = "List of FQDNs to assign A records to on the bastion host."
  type        = list(string)
  default     = [
    "bastion", 
    "vault", 
    "boundary", 
    "consul",
    "grafana"
  ]
}

variable "k8s_master_fqdn_list" {
  description = "List of FQDNs to assign A records to on the k8s master."
  type        = list(string)
  default     = ["api.k8s"]
}

variable "common_tags" {
  type = map(string)
  default = {
    Environment = "lab"
    Project     = "cloud-lab"
    Owner       = "arpa-infra"
    ManagedBy   = "terraform"
  }
}

