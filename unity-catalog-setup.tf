variable "uc_admin_group_name" {}
variable group_name1{}
variable group_name2{}

# Unity Catalog Setup and IAM

// optional prefix for metastore name
locals {
  prefix = "unity"
}

# extract workspace ID for unity catalog metastore assignment
# or provide a hard coded value
locals {
  workspace_id = databricks_mws_workspaces.databricks_workspace.workspace_id
}

// create uc admin group
resource "databricks_group" "uc_admins" {
  provider     = databricks.accounts
  display_name = var.uc_admin_group_name
}

# // create uc admin user1
resource "databricks_user" "admin_member0" { 
  provider     = databricks.accounts
  user_name = "hk-test-user@databricks.com" # replace
}

// retrieve existing account admin user from account console
data "databricks_user" "admin_member1" {
  provider     = databricks.accounts
  user_name = var.databricks_admin_user
}

// retrieve existing google SA from account console
data "databricks_user" "admin_member2" {
  provider     = databricks.accounts
  user_name = var.google_service_account_email
}

// add user to admin group
resource "databricks_group_member" "admin_member0" { 
  provider     = databricks.accounts
  group_id  = databricks_group.uc_admins.id
  member_id = databricks_user.admin_member0.id
}

// add user to admin group
resource "databricks_group_member" "admin_member1" { 
  provider     = databricks.accounts
  group_id  = databricks_group.uc_admins.id
  member_id = data.databricks_user.admin_member1.id
}

// add user to admin group
resource "databricks_group_member" "admin_member2" { 
  provider     = databricks.accounts
  group_id  = databricks_group.uc_admins.id
  member_id = data.databricks_user.admin_member2.id
}

// create storage bucket for metastore

resource "google_storage_bucket" "unity_metastore" {
  name          = "${local.prefix}-metastore-${var.google_region}-${random_string.databricks_suffix.result}" # replace if needed
  location      = var.google_region
  force_destroy = true
}

# // create metastore
resource "databricks_metastore" "this" {
  provider      = databricks.accounts
  name          = "primary-metastore-${var.google_region}-${random_string.databricks_suffix.result}" # replace if needed
  storage_root  = "gs://${google_storage_bucket.unity_metastore.name}"
  force_destroy = true
  owner         = var.uc_admin_group_name
  region = var.google_region
}

# at this moment destroying databricks_metastore_data_access resource is not supported using TF
# please use `terraform state rm databricks_metastore_data_access.first` and the manually delete 
# metastore on the account console

// Configures data access permissions for the Unity Catalog metastore

resource "databricks_metastore_data_access" "first" {
  provider     = databricks.accounts
  metastore_id = databricks_metastore.this.id
  databricks_gcp_service_account {}
  name       = "default-storage-creds" // storage credentials created for the default storage account
  is_default = true
}

resource "google_storage_bucket_iam_member" "unity_sa_admin" {
  depends_on = [
    databricks_metastore_data_access.first
  ]
  bucket = google_storage_bucket.unity_metastore.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${databricks_metastore_data_access.first.databricks_gcp_service_account[0].email}"
}

resource "google_storage_bucket_iam_member" "unity_sa_reader" {
  depends_on = [
    databricks_metastore_data_access.first
  ]
  bucket = google_storage_bucket.unity_metastore.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${databricks_metastore_data_access.first.databricks_gcp_service_account[0].email}"
}

# // Assigns the created metastore to the Databricks workspace

resource "databricks_metastore_assignment" "this" {
  provider             = databricks.accounts
  workspace_id         = local.workspace_id
  metastore_id         = databricks_metastore.this.id
  default_catalog_name = "main"
}


// add additional non-admin groups to account console

resource "databricks_group" "data_eng" {
  provider     = databricks.accounts
  display_name = var.group_name1
}

// add user
resource "databricks_user" "member0" { 
  provider     = databricks.accounts
  user_name = "${random_string.databricks_suffix.result}_dev@databricks.com" # replace with real user email
}

// add group to account console

resource "databricks_group" "data_analytics" {
  provider     = databricks.accounts
  display_name = var.group_name2
}

// add user
resource "databricks_user" "member1" { 
  provider     = databricks.accounts
  user_name = "${random_string.databricks_suffix.result}_analyst@databricks.com" # replace with real user email
}


// assign groups to workspace

resource "databricks_mws_permission_assignment" "add_admin_group" {
  provider = databricks.accounts
  workspace_id = local.workspace_id //databricks_mws_workspaces.this.workspace_id
  principal_id = databricks_group.data_analytics.id
  permissions  = ["ADMIN"]
}

// assign groups to workspace

resource "databricks_mws_permission_assignment" "add_non_admin_group" {
  provider = databricks.accounts
  workspace_id = local.workspace_id //databricks_mws_workspaces.this.workspace_id
  principal_id = databricks_group.data_eng.id
  permissions  = ["USER"]
}