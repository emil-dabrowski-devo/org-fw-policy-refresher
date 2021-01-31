#enable APIs
locals {
  org_fw_policy_services_list = {
    for p in var.org_fw_policy_services:
    "${p}" => {
      service   = p
    }
  }
}

resource "google_project_service" "project_services" {
    for_each = local.org_fw_policy_services_list
    project = var.project_id
    service = each.value.service
    disable_dependent_services = false
    disable_on_destroy = false
}


#create Service Account
resource "google_service_account" "sa_fw_policy_account" {
  account_id   = var.sa_account
  display_name = "Organization Firewall Policies Refresher"
  project = var.project_id
}

#add rights 
locals {
  server_pr_fw_roles_list = {
    for p in var.sa_pr_fw_pol_roles:
    "${p}" => {
      role   = p
    }
  }
}

resource "google_project_iam_member" "project_fw_policy_roles" {
  for_each = local.server_pr_fw_roles_list
  project  = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.sa_fw_policy_account.email}"
}

locals {
  server_folder_fw_roles_list = {
    for p in var.sa_folder_fw_pol_roles:
    "${p}" => {
      role   = p
    }
  }
}

resource "google_folder_iam_member" "folder_fw_policy_roles" {
  for_each = local.server_folder_fw_roles_list
  folder  = var.folder_fw_policy
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.sa_fw_policy_account.email}"
}

#create cf

resource "google_storage_bucket" "bucket" {
  name = "${var.project_id}-org-fw-id"
  location = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "archive" {
  name   = "app.zip"
  bucket = google_storage_bucket.bucket.name
  source = "./app.zip"
}

resource "google_cloudfunctions_function" "org_fw_policy_function" {
  name        = "org-fw-policy-refresh"
  description = "Refreshing list of allowd IPs to Google Services"
  runtime     = "python38"
  project     = var.project_id
  region      = var.region
  service_account_email = google_service_account.sa_fw_policy_account.email

  available_memory_mb   = 128
  trigger_http          = true
  timeout               = 60
  entry_point           = "init_app"
  labels = {
    my-label = "my-label-value"
  }
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name

  environment_variables = {
       AUTH_KEY = var.org_fw_policy_auth_key
       CLOUD_URL = var.org_fw_policy_cloud_url
       GOOG_URL = var.org_fw_policy_goog_url
       ORG_POLICY_ID = google_compute_organization_security_policy.org_policy.id   
       PROJECT_ID = var.project_id
       RULE_ID = var.org_fw_id
       SERVICE_ACCOUNT = google_service_account.sa_fw_policy_account.email
       SVC_URL = var.org_fw_svc_url
  }
  depends_on = [google_project_service.project_services]
}

resource "google_cloudfunctions_function_iam_member" "org_fw_policy_invoker" {
  project        = google_cloudfunctions_function.org_fw_policy_function.project
  region         = google_cloudfunctions_function.org_fw_policy_function.region
  cloud_function = google_cloudfunctions_function.org_fw_policy_function.name

  role   = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.sa_fw_policy_account.email}"
  depends_on = [ google_cloudfunctions_function.org_fw_policy_function ]
}

#create scheduler
resource "google_app_engine_application" "org_fw_policy_appengine" {
  project     = var.project_id
  location_id = var.region
}

resource "google_cloud_scheduler_job" "org_fw_policy_job" {
  name             = "run-cidrs-refresh"
  project          = var.project_id
  description      = "Refresh cidrs in fw policy"
  schedule         = "0 0 * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "240s"
  region = var.region

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.org_fw_policy_function.https_trigger_url
    headers     = {"Content-Type" = "application/json"}
    body        = base64encode("{\"message\":\"${var.org_fw_policy_auth_key}\"}")
    oidc_token {
      service_account_email = google_service_account.sa_fw_policy_account.email
    }
  }
  depends_on = [google_project_service.project_services, google_app_engine_application.org_fw_policy_appengine]
}
