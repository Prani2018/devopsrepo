# Configure the Google Cloud Provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "my-gke-cluster"
}

variable "github_repo_url" {
  description = "GitHub repository URL for the application"
  type        = string
  default     = "https://github.com/your-username/your-repo.git"
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:latest"
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required APIs
resource "google_project_service" "container_api" {
  project = var.project_id
  service = "container.googleapis.com"
  
  disable_dependent_services = true
}

resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"
  
  disable_dependent_services = true
}

# Create VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_api]
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.11.0.0/24"
  }
  
  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.12.0.0/16"
  }
}

# Create GKE cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone
  
  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-ranges"
    services_secondary_range_name = "services-range"
  }
  
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  depends_on = [
    google_project_service.container_api,
    google_compute_network.vpc,
    google_compute_subnetwork.subnet,
  ]
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${google_container_cluster.primary.name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    labels = {
      env = var.project_id
    }

    machine_type = "e2-medium"
    disk_type    = "pd-standard"
    disk_size_gb = 20
    
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    tags = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

# Get cluster credentials for Kubernetes provider
data "google_container_cluster" "my_cluster" {
  name     = google_container_cluster.primary.name
  location = var.zone
  depends_on = [google_container_cluster.primary]
}

data "google_client_config" "default" {
  depends_on = [google_container_cluster.primary]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.my_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.my_cluster.master_auth.0.cluster_ca_certificate)
}

# Create namespace
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = "my-app"
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

# Create ConfigMap with GitHub repo information
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }
  
  data = {
    github_repo = var.github_repo_url
    environment = "production"
  }
}

# Create Secret for GitHub access (if needed)
resource "kubernetes_secret" "github_secret" {
  metadata {
    name      = "github-secret"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }
  
  type = "Opaque"
  
  data = {
    # Add your GitHub token or SSH key here
    # github_token = "your-github-token"
    # ssh_key = "your-ssh-private-key"
  }
}

# Create Deployment
resource "kubernetes_deployment" "app_deployment" {
  metadata {
    name      = "my-app-deployment"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
    labels = {
      app = "my-app"
    }
  }
  
  spec {
    replicas = 2
    
    selector {
      match_labels = {
        app = "my-app"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "my-app"
        }
      }
      
      spec {
        container {
          image = var.container_image
          name  = "my-app-container"
          
          port {
            container_port = 80
          }
          
          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata[0].name
            }
          }
          
          # If you need to clone from GitHub repository
          # volume_mount {
          #   name       = "github-repo"
          #   mount_path = "/app"
          # }
          
          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
        
        # Init container to clone GitHub repository (optional)
        # init_container {
        #   name  = "git-clone"
        #   image = "alpine/git:latest"
        #   command = ["git", "clone", var.github_repo_url, "/repo"]
        #   
        #   volume_mount {
        #     name       = "github-repo"
        #     mount_path = "/repo"
        #   }
        # }
        
        # volume {
        #   name = "github-repo"
        #   empty_dir {}
        # }
      }
    }
  }
  
  depends_on = [
    kubernetes_config_map.app_config,
    kubernetes_secret.github_secret
  ]
}

# Create Service
resource "kubernetes_service" "app_service" {
  metadata {
    name      = "my-app-service"
    namespace = kubernetes_namespace.app_namespace.metadata[0].name
  }
  
  spec {
    selector = {
      app = kubernetes_deployment.app_deployment.metadata[0].labels.app
    }
    
    session_affinity = "ClientIP"
    
    port {
      port        = 80
      target_port = 80
    }
    
    type = "LoadBalancer"
  }
}

# Output values
output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
  sensitive   = true
}

output "service_external_ip" {
  value       = kubernetes_service.app_service.status.0.load_balancer.0.ingress.0.ip
  description = "External IP of the LoadBalancer service"
}

output "cluster_location" {
  value       = google_container_cluster.primary.location
  description = "Cluster location"
}

output "namespace" {
  value       = kubernetes_namespace.app_namespace.metadata[0].name
  description = "Kubernetes namespace"
}