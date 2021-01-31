resource "google_compute_organization_security_policy" "org_policy" {
  provider = google-beta

  display_name = var.org_policy_name
  parent       = "folders/${var.folder_fw_policy}"
}

resource "google_compute_organization_security_policy_association" "org_policy_association" {
  provider = google-beta

  name          = google_compute_organization_security_policy.org_policy.display_name
  attachment_id = google_compute_organization_security_policy.org_policy.parent
  policy_id     = google_compute_organization_security_policy.org_policy.id
}

resource "google_compute_organization_security_policy_rule" "allow_egress_to_public" {
  provider = google-beta

  policy_id = google_compute_organization_security_policy.org_policy.id
  action = "allow"

  direction = "EGRESS"
  enable_logging = false
  match {
    config {
      dest_ip_ranges = ["10.0.0.0/24"]
      layer4_config {
        ip_protocol = "tcp"
        ports = ["443"]
      }
    }
  }
  priority = 65534
}
