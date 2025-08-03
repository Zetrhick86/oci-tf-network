

# inputs

variable "compartment_id" {
  type = string
}

variable "app_name" {
  type = string
}

variable "subnet_ids" {
    type = list(string)
    description = "list at least 1 and at most 3 subnets to deploy the functions in"
}
variable "nsg_ids" {
  type = list(string)
  description = "list of ocids of network security groups to associate with the application"
  default = null
}

variable "shape" {
  type = string
  default = "GENERIC_X86"
  description = "Accepted values are: GENERIC_X86, GENERIC_ARM, GENERIC_X86_ARM"
}


variable "app_config" {
    # These values are passed on to the function as environment variables, functions may override application configuration. 
    # Keys must be ASCII strings consisting solely of letters, digits, and the '_' (underscore) character, and must not begin with a digit. 
    # Values should be limited to printable unicode characters. Example: {"MY_FUNCTION_CONFIG": "ConfVal"}
  type = map(string)
  description = "json object describing environment variables for the function"
  default = {}
}


variable "apm_domain_id" {
    type = string
    description = "the domain to use for Application Performance Monitoring"
    default = null
}
variable "create_apm_domain" {
  type = bool
  default = false
}


variable "create_logging_group" {
  type = bool
  default = true
}
variable "logging_group_id" {
  type = string
  default = null
}

variable "log_retention" {
  type = number
  default = 30
  description = "amount of time to retain logs in 30 day increments. Valid values: 30,60,90,120,150,180"
}



variable "create_ocir" {
  type = bool
  default = false
}
variable "ocir_id" {
  type = string
  default = null
}
variable "region" {
    type = string
    default = null
}
variable "image_prefix" {
  type = string
  default = null
  description = "format: <region_endpoint>/<tenancy_namespace>/<repo_name>/"
}


variable "functions" {
    description = "a list of objects describing the functions to deploy"
    type = list(object({
      name = string

      memory = number
      timeout = optional(number)

      config = optional(map(string))

      # either need to provide the full url or the name and version.
      image_full_url = optional(string)
      image_name = optional(string)
      image_version = optional(string)

      concurrency_set_count = optional(number) # values 1-x. will be automatically converted for you

    }))
    default = []
}


# Schedules only currently work in phoenix region
variable "schedules" {
  type = map(object({
    description = optional(string)

    recurrence_details = string # "30 19 * * *"
    recurrence_type = string # cron

    function_names = list(string) # todo relate function name to id or include this in functions object

    time_ends = string  # 2016-08-25T21:10:29.600Z
    time_starts = string # 2016-08-25T21:10:29.600Z

  }))
  default = {}
}


# outputs

output "application" {
  value = oci_functions_application.this
}

output "functions" {
    value = length(var.functions) > 0 ? oci_functions_function.these : null
}


output "apm_dompain" {
  value = var.create_apm_domain ? oci_apm_apm_domain.this[0] : null
}

output "log_group" {
    value = var.create_logging_group ? oci_logging_log_group.this[0] : null
}

output "log" {
    value = oci_logging_log.this
}

output "ocir" {
  value = local.ocir
}



# logic

data "oci_identity_regions" "this" {
    count = var.region != null ? 1 : 0
    filter {
      name = "name"
      values = [var.region]
    }
}

data "oci_artifacts_container_repository" "this" {
    count = var.ocir_id != null ? 1 : 0
    repository_id = var.ocir_id
}





locals {

    ocir = (
      var.create_ocir
            ? oci_artifacts_container_repository.this[0]
            : var.ocir_id != null
              ? data.oci_artifacts_container_repository.this[0]
              : null
        )

  image_prefix =(
    length(var.functions) < 1 || var.ocir_id == null
        ? ""
        : var.image_prefix != null
            ? var.image_prefix
            : "${lower(data.oci_identity_regions.this[0].regions[0].key)}.ocir.io/${local.ocir.namespace}/${local.ocir.display_name}/"
  )
}


# resource or mixed module blocks

resource "oci_apm_apm_domain" "this" {
    count = var.create_apm_domain ? 1 : 0
    compartment_id = var.compartment_id
    display_name = "${var.app_name}-funcapm"
}

resource "oci_artifacts_container_repository" "this" {
    count = var.create_ocir ? 1 : 0

    compartment_id = var.compartment_id
    display_name = "${var.app_name}-funcocir"

    is_immutable = true
    is_public = false
}

resource "oci_functions_application" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.app_name}-funcapp"

  subnet_ids     = var.subnet_ids
  network_security_group_ids = var.nsg_ids

  config = var.app_config

  shape = var.shape

  dynamic "trace_config" {
        for_each = var.apm_domain_id != null || var.create_apm_domain ? {1=1}:{}
        iterator = this
        content {
          domain_id = var.apm_domain_id != null ? var.apm_domain_id : oci_apm_apm_domain.this[0].id
          is_enabled = true
        }
    }
/*
  trace_config {
        domain_id = oci_apm_apm_domain.this.id
        is_enabled = true
  }

image_policy_config {
        #Required
        is_policy_enabled = var.application_image_policy_config_is_policy_enabled

        #Optional
        key_details {
            #Required
            kms_key_id = oci_kms_key.test_key.id
        }
    }

    # Not setting up syslog url as we are using oci logging, which ignores this value
    syslog_url = var.application_syslog_url

  */

}


resource "oci_logging_log_group" "this" {
    count = var.create_logging_group ? 1 : 0
  compartment_id = var.compartment_id
  display_name   = "${var.app_name}-funclog-group"
}

resource "oci_logging_log" "this" {
  display_name = "${var.app_name}-funclog"
  log_group_id = var.create_logging_group ? oci_logging_log_group.this[0].id : var.logging_group_id
  log_type     = "SERVICE"

  configuration {
    source {
      category    = "invoke"
      resource    = oci_functions_application.this.id
      service     = "functions"
      source_type = "OCISERVICE"
    }

    compartment_id = var.compartment_id
  }

  is_enabled         = true
  retention_duration = var.log_retention
}


resource "oci_functions_function" "these" {
    for_each = {for func in var.functions: func.name => func}

    application_id = oci_functions_application.this.id
    display_name = "${each.key}-func"

    memory_in_mbs = each.value.memory
    timeout_in_seconds = each.value.timeout == null ? 30 : each.value.timeout


    config = each.value.config



    image = each.value.image_full_url != null ? each.value.image_full_url : "${local.image_prefix}${each.value.image_name}:${each.value.image_version}"
    # TODO: do we need to use the image digest
    # image_digest = var.function_image_digest
    /*
    source_details {
        #Required
        pbf_listing_id = oci_functions_pbf_listing.test_pbf_listing.id
        source_type = var.function_source_details_source_type
    }
    */


    dynamic trace_config {
        for_each = (
            var.apm_domain_id != null
                ? {apm=var.apm_domain_id}
            : var.create_apm_domain
                ? {apm=oci_apm_apm_domain.this[0].id}
                : {}
        )
        iterator = trace
        content {
          is_enabled = true
        }

    }


    # https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsusingprovisionedconcurrency.htm
    dynamic "provisioned_concurrency_config" {
        for_each = each.value.concurrency_set_count != null ? {1=1} : {}
        iterator = concurrency
        content {
            strategy = each.value.concurrency_set_count == null ? "NONE" : "CONSTANT"
            count = (
                each.value.memory == 128 ?
                    ceil(each.value.concurrency_set_count/4) * 40
                : each.value.memory == 256 ?
                    ceil(each.value.concurrency_set_count/2) * 20
                : each.value.concurrency_set_count*10
            )
        }

    }
}

resource "oci_resource_scheduler_schedule" "these" {
  for_each = var.schedules
  # for_each = oci_functions_function.these

  action = "START_RESOURCE" #TODO: verify this is how to initiate a function as functions don't start/stop
  compartment_id = var.compartment_id

  recurrence_details = each.value.recurrence_details
  recurrence_type = each.value.recurrence_type

  description = each.value.description
  display_name = "${each.key}-schedule"


  dynamic "resources" {
    for_each = each.value.function_names
    content {
      id = resources.value # TODO lookup id from name
    }
  }

  time_ends = each.value.time_ends
  time_starts = each.value.time_starts
}


terraform {
  
  required_version = ">1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">7.9.0"
    }
  }
}
