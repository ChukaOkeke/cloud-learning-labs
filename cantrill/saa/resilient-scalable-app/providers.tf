# Landing Zone
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

  # S3 Backend for the NEW DEMO's state
terraform {
  backend "s3" {
      bucket  = "my-cantrill-labs-terraform-state"
      key     = "demos/scp/terraform.tfstate" # Unique key for this demo
      region  = "us-east-1"
      dynamodb_table = "terraform-state-locking" 
      encrypt        = true # Enable encryption at rest in S3 for the state file
      profile = "iamadmin-general"
    }
}


# 1. PULL DATA FROM THE FOUNDATION ORG STATE
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket  = "my-cantrill-labs-terraform-state"
    key     = "foundation/terraform.tfstate" # Points back to your Org state
    region  = "us-east-1"
    dynamodb_table = "terraform-state-locking" 
    encrypt        = true # Enable encryption at rest in S3 for the state file
    profile = "iamadmin-general"
  }
}

# 2. DEFAULT PROVIDER (General/Master/Management Account)
provider "aws" {
  region  = "us-east-1"
  profile = "iamadmin-general"
}


# 3. DEV ACCOUNT PROVIDER (Assumes Role into DEV)
provider "aws" {
  alias  = "dev"
  region = "us-east-1"
  assume_role {
    # Dynamically pulls the ID from your Foundation output
    role_arn = "arn:aws:iam::${data.terraform_remote_state.foundation.outputs.dev_account_id}:role/OrganizationAccountAccessRole"
  }
  profile = "iamadmin-general"
}

# 4. PROD ACCOUNT PROVIDER (Assumes Role into PROD)
provider "aws" {
  alias  = "prod"
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::${data.terraform_remote_state.foundation.outputs.prod_account_id}:role/OrganizationAccountAccessRole"
  }
  profile = "iamadmin-general"
}