variable prefix {
  description = "Prefix for resources created by this module"
  type        = string
  default     = "tf-azure-bigip"
}

variable location {}

variable cidr {
  description = "Azure VPC CIDR"
  type        = string
  default     = "10.2.0.0/16"
}


variable availabilityZones {
  description = "If you want the VM placed in an Azure Availability Zone, and the Azure region you are deploying to supports it, specify the numbers of the existing Availability Zone you want to use."
  type        = list
  default     = [1]
}


variable AllowedIPs {}

variable instance_count {
  description = "Number of Bigip instances to create( From terraform 0.13, module supports count feature to spin mutliple instances )"
  type        = number
  default     = 1
}


variable f5_ssh_publickey {
  description = "Path to the public key to be used for ssh access to the VM.  Only used with non-Windows vms and can be left as-is even if using Windows vms. If specifying a path to a certification on a Windows machine to provision a linux vm use the / in the path versus backslash. e.g. c:/home/id_rsa.pub"
  default     = "~/.ssh/id_rsa.pub"
}

variable f5_version {
  type    = string
  default = "15.1.201000"
}

variable f5_product_name {
  type    = string
  #default = "f5-big-ip-best"
  default = "f5-big-ip-byol"
}

variable f5_image_name {
  type    = string
  #default = "f5-bigip-virtual-edition-200m-best-hourly"
  default = "f5-big-all-2slot-byol"
}

