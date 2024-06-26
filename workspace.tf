variable "databricks_account_id" {}
variable "databricks_account_console_url" {}
variable "databricks_workspace_name" {}
variable "databricks_admin_user" {}
variable "google_vpc_id" {}
variable "gke_node_subnet" {}
variable "gke_pod_subnet" {}
variable "gke_service_subnet" {}
variable "gke_master_ip_range" {}



data "google_client_openid_userinfo" "me" {}
data "google_client_config" "current" {}

# Random suffix for databricks resources
resource "random_string" "databricks_suffix" {
  special = false
  upper   = false
  length  = 2
}

// Optional: creates a default SA that databricks will use to create clusters and manage GCP resources. This is not expelicitly needed since your privilaged-sa will do this role if the following databricks SA is not created. 

# resource "google_service_account" "databricks" {
#     account_id   = "databricks" #need to use "databricks"
#     display_name = "Databricks SA for GKE nodes"
#     project = var.google_project_name
# }
# output "service_account" {
#     value       = google_service_account.databricks.email
#     description = "Default SA for GKE nodes"
# }

# # assign role to the gke default SA
# resource "google_project_iam_binding" "databricks_gke_node_role" {
#   project = "${var.google_project_name}"
#   role = "roles/container.nodeServiceAccount"
#   members = [
#     "serviceAccount:${google_service_account.databricks.email}"
#   ]
# }

# Provision databricks network configuration
resource "databricks_mws_networks" "databricks_network" {
  provider     = databricks.accounts
  account_id   = var.databricks_account_id
  # name needs to be of length 3-30 incuding [a-z,A-Z,-_]
  network_name = "fe-dev-sandbox-nw-6d" # replace hard code or generate name with "${var.google_shared_vpc_project}-nw-${random_string.databricks_suffix.result}"
  gcp_network_info {
    network_project_id    = var.google_shared_vpc_project
    vpc_id                = var.google_vpc_id
    subnet_id             = var.gke_node_subnet
    pod_ip_range_name     = var.gke_pod_subnet
    service_ip_range_name = var.gke_service_subnet
    subnet_region         = var.google_region
  }
}
# Provision databricks workspace in a customer managed vpc
# https://docs.gcp.databricks.com/administration-guide/account-settings-gcp/workspaces.html#create-a-workspace-using-the-account-console


resource "databricks_mws_workspaces" "databricks_workspace" {
  provider       = databricks.accounts
  account_id     = var.databricks_account_id
  workspace_name = var.databricks_workspace_name
  location       = var.google_region
  cloud_resource_container {
    gcp {
      project_id = var.google_project_name
    }
  }
  network_id = databricks_mws_networks.databricks_network.network_id
  gke_config {
    connectivity_type = "PRIVATE_NODE_PUBLIC_MASTER"
    master_ip_range   = var.gke_master_ip_range
  }
}


data "databricks_group" "admins" {
  depends_on   = [ databricks_mws_workspaces.databricks_workspace ]
  provider     = databricks.workspace
  display_name = "admins"
}

// creates a databricks user in the workspace using your credentials
resource "databricks_user" "me" {
  depends_on = [ databricks_mws_workspaces.databricks_workspace ]
  provider   = databricks.workspace
  user_name  = var.databricks_admin_user
  workspace_access = true
  allow_cluster_create = true
  allow_instance_pool_create = true
  databricks_sql_access = true
}

output "workspace_url" {
  value = databricks_mws_workspaces.databricks_workspace.workspace_url
}
