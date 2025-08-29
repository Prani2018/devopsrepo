# terraform.tfvars
# Copy this file and update with your specific values

project_id      = "your-gcp-project-id"
region          = "us-central1"
zone            = "us-central1-a"
cluster_name    = "my-gke-cluster"
github_repo_url = "https://github.com/your-username/your-repo.git"
container_image = "nginx:latest"  # Replace with your application image

# Example with custom application:
# container_image = "gcr.io/your-project/your-app:latest"