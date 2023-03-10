terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.8.0"
    }
  }
  backend "gcs" {
    bucket = "gcp-backend-19158"
    prefix = "terraform/state"
  }
}


provider "google" {
  region  = "asia-south2"
  project = "mypoc-374706"
  zone    = "asia-south2-a"

}
