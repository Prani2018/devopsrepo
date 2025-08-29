# setup.ps1 - Windows PowerShell setup script for GCP Kubernetes with Terraform

Write-Host "Setting up GCP Kubernetes deployment with Terraform on Windows..." -ForegroundColor Green

# Function to check if a command exists
function Test-Command($command) {
    try {
        Get-Command $command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Check and install prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check if Chocolatey is installed
if (-not (Test-Command "choco")) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Install Terraform if not present
if (-not (Test-Command "terraform")) {
    Write-Host "Installing Terraform..." -ForegroundColor Yellow
    choco install terraform -y
} else {
    Write-Host "Terraform is already installed." -ForegroundColor Green
}

# Install Google Cloud SDK if not present
if (-not (Test-Command "gcloud")) {
    Write-Host "Installing Google Cloud SDK..." -ForegroundColor Yellow
    choco install gcloudsdk -y
} else {
    Write-Host "Google Cloud SDK is already installed." -ForegroundColor Green
}

# Install kubectl if not present
if (-not (Test-Command "kubectl")) {
    Write-Host "Installing kubectl..." -ForegroundColor Yellow
    choco install kubernetes-cli -y
} else {
    Write-Host "kubectl is already installed." -ForegroundColor Green
}

# Install Git if not present
if (-not (Test-Command "git")) {
    Write-Host "Installing Git..." -ForegroundColor Yellow
    choco install git -y
} else {
    Write-Host "Git is already installed." -ForegroundColor Green
}

Write-Host "Prerequisites check completed!" -ForegroundColor Green

# Prompt for GCP authentication
Write-Host "`nSetting up GCP authentication..." -ForegroundColor Yellow
Write-Host "Please follow the browser authentication process."

try {
    gcloud auth login
    Write-Host "GCP authentication successful!" -ForegroundColor Green
} catch {
    Write-Host "GCP authentication failed. Please run 'gcloud auth login' manually." -ForegroundColor Red
    exit 1
}

# Get project ID
$projectId = Read-Host "Enter your GCP Project ID"
gcloud config set project $projectId

# Enable required APIs
Write-Host "Enabling required GCP APIs..." -ForegroundColor Yellow
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com

# Create application default credentials
Write-Host "Setting up application default credentials..." -ForegroundColor Yellow
gcloud auth application-default login

# Create terraform.tfvars file
Write-Host "Creating terraform.tfvars file..." -ForegroundColor Yellow
$githubRepo = Read-Host "Enter your GitHub repository URL (e.g., https://github.com/username/repo.git)"
$containerImage = Read-Host "Enter container image to deploy (default: nginx:latest)"

if ([string]::IsNullOrWhiteSpace($containerImage)) {
    $containerImage = "nginx:latest"
}

$tfvarsContent = @"
project_id      = "$projectId"
region          = "us-central1"
zone            = "us-central1-a"
cluster_name    = "my-gke-cluster"
github_repo_url = "$githubRepo"
container_image = "$containerImage"
"@

$tfvarsContent | Out-File -FilePath "terraform.tfvars" -Encoding UTF8

Write-Host "`nSetup completed successfully!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Review and modify terraform.tfvars if needed"
Write-Host "2. Run: terraform init"
Write-Host "3. Run: terraform plan"
Write-Host "4. Run: terraform apply"
Write-Host "5. Configure kubectl: gcloud container clusters get-credentials my-gke-cluster --zone us-central1-a"