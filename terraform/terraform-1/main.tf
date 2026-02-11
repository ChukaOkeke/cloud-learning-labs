# Configure the Terraform AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  # Access keys can be set in the environment variables or through the AWS CLI configuration
}

# Create a VPC
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "prod-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id  # Reference the VPC ID from the created VPC

}

# Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id  # Reference the VPC ID from the created VPC

  route {
    cidr_block = "0.0.0.0/0"  # Default Route to route all IPv4 traffic to the Internet Gateway
    gateway_id = aws_internet_gateway.gw.id # Reference the Internet Gateway ID from the created Internet Gateway
  }

  tags = {
    Name = "prod-route-table"
  }
}

# Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id  # Reference the VPC ID from the created VPC
  cidr_block        = "10.0.1.0/24"  # Define the CIDR block for the subnet
  #cidr_block        = var.subnet_prefix  # Define the CIDR block for the subnet with variable reference
  availability_zone = "us-east-1a"   # Define the availability zone for the subnet

  tags = {
    Name = "prod-subnet"
  }
}

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id  # Reference the Subnet ID from the created Subnet
  route_table_id = aws_route_table.prod-route-table.id  # Reference the Route Table ID from the created Route Table
}

# Create a Security Group to allow port 22, 80, and 443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id # Reference the VPC created above

  tags = {
    Name = "allow_web_traffic"
  }
}

# HTTPS Ingress Rule
resource "aws_vpc_security_group_ingress_rule" "allow_https_ipv4" {
  description = "HTTPS"
  security_group_id = aws_security_group.allow_web.id # Reference the Security Group ID from the created Security Group
  cidr_ipv4         = "0.0.0.0/0" # Allow any IP address to access the web server
  from_port         = 443 # Define the port for HTTPS access
  ip_protocol       = "tcp" # Define the protocol for HTTPS access
  to_port           = 443
}

# HTTP Ingress Rule
resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  description = "HTTP"
  security_group_id = aws_security_group.allow_web.id # Reference the Security Group ID from the created Security Group
  cidr_ipv4         = "0.0.0.0/0" # Allow any IP address to access the web server
  from_port         = 80  # Define the port for HTTP access
  ip_protocol       = "tcp" # Define the protocol for HTTP access
  to_port           = 80
}

# SSH Ingress Rule
resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  description = "SSH"
  security_group_id = aws_security_group.allow_web.id # Reference the Security Group ID from the created Security Group
  cidr_ipv4         = "0.0.0.0/0" # Allow any IP address to access the web server
  from_port         = 22  # Define the port for SSH access
  ip_protocol       = "tcp" # Define the protocol for SSH access
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0" # Allow any IP address to access the web server
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Create a network interface with an ip in the subnet that was created
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id  # Reference the Subnet ID from the created Subnet
  private_ips     = ["10.0.1.50"] # Assign a specific private IP address to the host within the subnet's CIDR block
  security_groups = [aws_security_group.allow_web.id] # Attach the security group created above

}

# Assign an Elastic IP to the network interface that was created
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id # Reference the Network Interface ID from the created Network Interface
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw, aws_instance.web-server] # Ensure the Internet Gateway and EC2 instance are created before the Elastic IP is associated
}

# Create Ubuntu server and install/enable apache2
resource "aws_instance" "web-server" {
  ami           = "ami-0b6c6ebed2801a5cb" # Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
  instance_type = "t3.micro"
  availability_zone = "us-east-1a" # Define the availability zone for the instance
  key_name = "main-key"
  
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id # Reference the Network Interface ID from the created Network Interface  
  }

  # primary_network_interface_id = aws_network_interface.web-server-nic.id # Reference the Network Interface ID from the created Network Interface

  # Script to run
  user_data = <<-EOF
#!/bin/bash
# Force the system to use IPv4 for all apt commands
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4

# Update and install
sudo apt update -y
sudo apt install apache2 -y

# Start and enable
sudo systemctl start apache2
sudo systemctl enable apache2

# Create the page (Ensuring directory exists just in case)
sudo mkdir -p /var/www/html
echo "<h1>My first web server</h1>" | sudo tee /var/www/html/index.html
EOF
  tags = {
    Name = "web-server"
  }
}

# # Output the value of a resource property
# output "web_server_public_ip" {
#   value = aws_eip.one.public_ip
# }

# # Define variables
# variable "subnet_prefix" {
#   description = "The CIDR prefix for the subnet"
#   #default     
#   #type        
# }

# # General syntax for provisioning a resource
# resource "provider_resource" "name" {
#   # Resource configuration goes here
#   key = "value"
#   key2 = "value2"
# }