resource "google_cloud_identity_group" "task" {
  display_name         = var.group_display_name
  description          = "Sandbox task01 access group"
  initial_group_config = "WITH_INITIAL_OWNER"
  parent               = "customers/${var.customer_id}"

  group_key {
    id = var.group_email
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_cloud_identity_group_membership" "members" {
  for_each = var.members

  group = google_cloud_identity_group.task.id

  preferred_member_key {
    id = each.value
  }

  roles {
    name = "MEMBER"
  }
}
