#customize these parameters
variable "project_id" {default = ""}
variable "folder_fw_policy" {default = ""}
variable "org_fw_policy_auth_key" {default = ""}
variable "org_fw_policy_id" {default = ""}
variable "org_fw_id" {default = "65534"}

#default values - can be customized
variable "sa_account" {default = "org-fw-policy-refresher"}
variable "org_policy_name" {default = "org-fw-policy"}
variable "region" {default = "europe-west3"}


#required values - shouldn't be changed
variable "sa_pr_fw_pol_roles" {default = [
  "roles/cloudfunctions.invoker", 
  "roles/cloudscheduler.serviceAgent", 
  "roles/iam.serviceAccountTokenCreator",
  "roles/iam.serviceAccountUser",
  "roles/logging.logWriter"
  ]}
variable "sa_folder_fw_policy_roles" { default = [
  "roles/compute.securityAdmin", 
  "roles/compute.orgFirewallPolicyAdmin"
  ]}
variable "org_fw_policy_services" {default = [
  "orgpolicy.googleapis.com", 
  "iam.googleapis.com", 
  "cloudfunctions.googleapis.com", 
  "cloudscheduler.googleapis.com", 
  "cloudbuild.googleapis.com", 
  "appengine.googleapis.com"]}
variable "org_fw_policy_cloud_url" {default = "https://www.gstatic.com/ipranges/cloud.json"}
variable "org_fw_policy_goog_url" {default = "https://www.gstatic.com/ipranges/goog.json"}
variable "org_fw_svc_url" {default = "https://www.googleapis.com/compute/beta/"}

