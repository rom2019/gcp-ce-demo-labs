terraform {
  backend "gcs" {
    bucket = "ce-demo-tfstate"
    prefix = "demo-network-ncc-static-routing-hybrid"
  }
}