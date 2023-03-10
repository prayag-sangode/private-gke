
resource "google_compute_network" "vpc" {
  name                    = "gkepvtvpc"
  auto_create_subnetworks = false
}


resource "google_compute_subnetwork" "subnet" {
  name          = "gkepvtsubnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/24"
}


resource "google_container_cluster" "primary" {
  name                     = "pvt-gke-cluster"
  location                 = var.location
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  remove_default_node_pool = true
  # networking_mode          = "VPC_NATIVE" 
  initial_node_count = 1

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.13.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.11.0.0/21"
    services_ipv4_cidr_block = "10.12.0.0/21"
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.7/32"
      display_name = "gkeauthnet"
    }

  }
}


resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = var.location
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "dev"
    }

    machine_type    = "e2-medium"
    preemptible     = true
    service_account = "GCP-SA@mypoc-374706.iam.gserviceaccount.com"

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

resource "google_compute_address" "internal_ip_addr" {
  project      = var.project
  address_type = "INTERNAL"
  region       = var.region
  subnetwork   = "gkepvtsubnet"
  name         = "int-ip"
  address      = "10.0.0.7"
  description  = "An internal IP address for bastion host"
}

resource "google_compute_instance" "default" {
  project      = var.project
  zone         = var.zone
  name         = "bastion-host"
  machine_type = "e2-medium"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = "gkepvtvpc"
    subnetwork = "gkepvtsubnet"
    network_ip = google_compute_address.internal_ip_addr.address
  }
  tags = ["bastion-host"]
}


resource "google_compute_firewall" "rules" {
  project = var.project
  name    = "allow-ssh"
  network = "gkepvtvpc"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_tags = ["bastion-host"]
}


resource "google_project_iam_member" "project" {
  project = var.project
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:GCP-SA@mypoc-374706.iam.gserviceaccount.com"
}


resource "google_compute_router" "router" {
  project = var.project
  name    = "nat-router"
  network = "gkepvtvpc"
  region  = var.region
}


module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = var.project
  region     = var.region
  router     = google_compute_router.router.name
  name       = "nat-config"

}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Private Cluster Host"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Private Cluster Name"
}
