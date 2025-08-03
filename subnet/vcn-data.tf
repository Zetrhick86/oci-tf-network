

# inputs

variable "network" {
  default     = null
  description = "network module. overrides other network configuration options."
}


variable "vcn" {
  default     = null
  description = "vcn object."
}

variable "internet_gateway" {
  default     = null
  description = "internet gateway object. can't be used with a nat or service gateway"
}

variable "nat_gateway" {
  default     = null
  description = "nat gateway object. can't be used with an internet gateway."

}

variable "service_gateway" {
  default     = null
  description = "service gateway object. can't be used with an internet gateway"
}





variable "vcn_cidrs" {
  type        = list(string)
  default = null 
  description = "A list of cidr blocks to enable ICMP security rules to. omit to use the list of cidr blocks from the vcn"
}


# outputs


# logic


locals {

  vcn = var.network == null ? var.vcn : var.network.vcn

  internet_gateway = var.network == null ? var.internet_gateway : var.network.internet_gateway

  nat_gateway = var.network == null ? var.nat_gateway : var.network.nat_gateway


  service_gateway = var.network == null ? var.service_gateway : var.network.service_gateway


  internet_access = (
    local.nat_gateway != null
    ? "nat"
    : local.internet_gateway != null
    ? "full"
    : "none"
  )

  cidr_blocks = (
    var.vcn_cidrs != null
    ? var.vcn_cidrs
    : local.vcn.cidr_blocks
  )

  service_cidr = (
    var.service_gateway != null 
    ? data.oci_core_services.this[0].services[0].cidr_block
    : var.network == null 
    ? null 
    : var.network.service_cidr != null
    ? var.network.service_cidr.cidr_block
    : null )

  service_cidr_lookup = var.service_gateway != null ? tolist(var.service_gateway.services[*]) : null

}

# resource or mixed module blocks


data "oci_core_services" "this" {
  count = var.service_gateway != null ? 1 : 0

  filter {
    name   = "id"
    values = [local.service_cidr_lookup[0].service_id]
    # regex  = true
  }

}
