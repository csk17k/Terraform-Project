provider "google" {
  version = "~> 3.67.0"
  project = var.project
  region  = var.region
  credentials = file("credentials.json")
}
# New resource for the storage bucket our application will use.
resource "google_storage_bucket" "static-site" {
  name     = "csk2021"
  location = "US"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_compute_network" "webserver" {
  name                    = "${var.prefix}-vpc-${var.region}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "webserver" {
  name          = "${var.prefix}-subnet"
  region        = var.region
  network       = google_compute_network.webserver.self_link
  ip_cidr_range = var.subnet_prefix
}

resource "google_compute_firewall" "http-server" {
  name    = "default-allow-ssh-http"
  network = google_compute_network.webserver.self_link

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }

  // Allow traffic from everywhere to instances with an http-server tag
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

resource "google_compute_instance" "webserver" {
  name         = "${var.prefix}-webserver"
  zone         = "${var.region}-b"
  machine_type = var.machine_type

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.webserver.self_link
    access_config {
    }
  }

    tags = ["http-server"]

  labels = {
    name = "webserver"
  }
}

# Create build and run
resource "null_resource" "gcloud" {
  provisioner "local-exec" {
    command = "gcloud builds submit --config=cloudbuild.yaml"
  }
}

# Deploy image to Cloud Run
resource "google_cloud_run_service" "mywebapp" {
  name     = "mywebapp"
  location = "us-central1"
  template {
    spec {
      containers {
        image = "gcr.io/gcp-service-line-314413/tomcat"
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Create public access
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}
# Enable public access on Cloud Run service
resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.mywebapp.location
  project     = google_cloud_run_service.mywebapp.project
  service     = google_cloud_run_service.mywebapp.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

# Return service URL
output "url" {
  value = "${google_cloud_run_service.mywebapp.status[0].url}"
}
