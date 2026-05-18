# Setup Custom VPC and Subnet Architecture for Asgard
# Create the Asgard VPC
resource "aws_vpc" "asgard_vpc_1" {
  cidr_block       = "10.16.0.0/16"
  instance_tenancy = "default" # Default shared hardware

  # Request a /56 Amazon-provided IPv6 block
  assign_generated_ipv6_cidr_block = true

  # DNS Configuration
  enable_dns_support   = true # Enables the Amazon DNS server (169.254.169.253)
  enable_dns_hostnames = true # Allows instances to receive public/private DNS names

  tags = {
    Name = "asgard-vpc-1"
  }
}

# Output the assigned IPv6 CIDR for future subnetting
output "asgard_vpc_ipv6_cidr" {
  value = aws_vpc.asgard_vpc_1.ipv6_cidr_block
}


# Implement multi-tier VPC subnets (3 AZs, 4 tiers. 4 tiers per AZ. 3 AZs x 4 subnets = 12 subnets total)
# Use a locals block to map out the configuration for each subnet, including the IPv4 CIDR, the index for calculating the IPv6 CIDR, and the AZ. Scalably create subnets
locals {
  subnets = {
    # Availability Zone A
    "sn-reserved-A" = { ipv4 = "10.16.0.0/20",   v6_idx = 0,  az = "us-east-1a" }
    "sn-db-A"       = { ipv4 = "10.16.16.0/20",  v6_idx = 1,  az = "us-east-1a" }
    "sn-app-A"      = { ipv4 = "10.16.32.0/20",  v6_idx = 2,  az = "us-east-1a" }
    "sn-web-A"      = { ipv4 = "10.16.48.0/20",  v6_idx = 3,  az = "us-east-1a" }
    
    # Availability Zone B
    "sn-reserved-B" = { ipv4 = "10.16.64.0/20",  v6_idx = 4,  az = "us-east-1b" }
    "sn-db-B"       = { ipv4 = "10.16.80.0/20",  v6_idx = 5,  az = "us-east-1b" }
    "sn-app-B"      = { ipv4 = "10.16.96.0/20",  v6_idx = 6,  az = "us-east-1b" }
    "sn-web-B"      = { ipv4 = "10.16.112.0/20", v6_idx = 7,  az = "us-east-1b" }
    
    # Availability Zone C
    "sn-reserved-C" = { ipv4 = "10.16.128.0/20", v6_idx = 8,  az = "us-east-1c" }
    "sn-db-C"       = { ipv4 = "10.16.144.0/20", v6_idx = 9,  az = "us-east-1c" }
    "sn-app-C"      = { ipv4 = "10.16.160.0/20", v6_idx = 10, az = "us-east-1c" } # 0a in hex
    "sn-web-C"      = { ipv4 = "10.16.176.0/20", v6_idx = 11, az = "us-east-1c" } # 0b in hex
  }
}

# Create the subnets, using a for_each loop to iterate over the local.subnets map
resource "aws_subnet" "asgard_subnets" {
  for_each = local.subnets

  vpc_id            = aws_vpc.asgard_vpc_1.id # Associates all subnets with the VPC created above
  cidr_block        = each.value.ipv4
  availability_zone = each.value.az

  # Enable public IP for web subnets only
  map_public_ip_on_launch = length(regexall("web", each.key)) > 0 ? true : false

  # IPv6 Setup: Calculates the /64 from the VPC's /56
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.asgard_vpc_1.ipv6_cidr_block, 8, each.value.v6_idx)
  assign_ipv6_address_on_creation = true # auto-assign IPv6 addresses to resources launched in this subnet

  tags = {
    Name = each.key
  }
}

# Configure web public subnets
# Create Internet Gateway and attach to the custom VPC
resource "aws_internet_gateway" "asgard_vpc1_igw" {
  vpc_id = aws_vpc.asgard_vpc_1.id  # Reference the VPC ID from the created VPC

  tags = {
    Name = "asgard-vpc1-igw"
  }
}

# Create Custom Route Table that points to the Internet Gateway
resource "aws_route_table" "asgard_vpc1_rt_web" {
  vpc_id = aws_vpc.asgard_vpc_1.id  # Reference the VPC ID from the created VPC

  route {
    cidr_block = "0.0.0.0/0"  # Default Route to route all IPv4 traffic
    gateway_id = aws_internet_gateway.asgard_vpc1_igw.id # Target the created Internet Gateway
  }

  # Route for IPv6 traffic
  route {
    ipv6_cidr_block = "::/0"  # Default Route to route all IPv6 traffic
    gateway_id      = aws_internet_gateway.asgard_vpc1_igw.id
  }

  tags = {
    Name = "asgard-vpc1-rt-web"
  }
}

# Associate the Route Table with the web subnets
# Associate the Route Table with sn-web-A
resource "aws_route_table_association" "web_a" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-A"].id # Reference the web subnets using their keys
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Associate the Route Table with sn-web-B
resource "aws_route_table_association" "web_b" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-B"].id
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Associate the Route Table with sn-web-C
resource "aws_route_table_association" "web_c" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-C"].id
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}


# Create Security Group for the ALB
resource "aws_security_group" "alb_sg" {
  name        = "asgard-alb-sg"
  description = "External security group for Application Load Balancer"
  vpc_id      = aws_vpc.asgard_vpc_1.id # Uses your existing multi-AZ VPC

  # Allow HTTP traffic from the entire internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Route traffic to the web/app tier instances
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asgard-alb-sg"
  }
}

#Create the ALB
# ALB requires placements in at least two AZs for high availability, so we'll place it in the public web subnets of AZ A, AZ B, and AZ C
resource "aws_lb" "asgard_alb" {
  name               = "asgard-architecture-alb"
  internal           = false # Publicly accessible from the internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  # Deploying listener nodes across your 3 public web subnets
  subnets            = [
    aws_subnet.asgard_subnets["sn-web-A"].id, 
    aws_subnet.asgard_subnets["sn-web-B"].id, 
    aws_subnet.asgard_subnets["sn-web-C"].id
  ]

  enable_deletion_protection = false # Set to true for production systems

  tags = {
    Name = "asgard-alb"
  }
}

# Create Target Group & Listener Configuration
# The Target Group defines where the traffic goes once it hits the ALB. The Listener binds the incoming traffic on port 80 to that specific target group.
# The destination pool for your ASG EC2 instances
resource "aws_lb_target_group" "asgard_web_tg" {
  name     = "asgard-web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.asgard_vpc_1.id

  # Vital for the ELB health check & replacement logic shown in the diagram
  health_check {
    enabled             = true
    path                = "/" # Adjust to /index.php or a specific health file later
    port                = "80"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "asgard-web-target-group"
  }
}

# The routing rule mapping port 80 to the target group
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.asgard_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asgard_web_tg.arn
  }
}

# Output the ALB entry point DNS name for easy access after deployment
output "alb_dns_name" {
  description = "The native entry point for your scalable application architecture"
  value       = aws_lb.asgard_alb.dns_name
}


# Create the ASG
# We will configure the ASG to use ELB health checks. This ensures that if Nginx or the application fails on an instance, the ALB marks it unhealthy, and the ASG automatically destroys and replaces it.
# Create Instance Security Group for the ASG
resource "aws_security_group" "asgard_instance_sg" {
  name        = "asgard-instance-sg"
  description = "Security group for ASG instances"
  vpc_id      = aws_vpc.asgard_vpc_1.id

  # Inbound: ONLY allow traffic from the ALB Security Group
  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Outbound: Allow all traffic (required for software updates, pulling packages, EFS, RDS)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asgard-instance-sg"
  }
}

# Dynamically fetch the latest Ubuntu 24.04 LTS (Noble Numbat) AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's Official AWS Account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"] # Use "arm64" if using Graviton instances (t4g, m7g, etc.)
  }
}

# Create the Launch Template
# This serves as the immutable blueprint for your web tier (the ASG/Cluster instances). We will use the dynamic Ubuntu data source approach and pass a basic #cloud-config setup to install Nginx so that the ALB health check passes immediately upon boot.
resource "aws_launch_template" "asgard_web_template" {
  name_prefix   = "asgard-web-template-"
  image_id      = data.aws_ami.ubuntu.id # Dynamically fetches the latest Ubuntu 24.04
  instance_type = "t3.micro"

  # Network configuration inside the template
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.asgard_instance_sg.id]
  }

  # Enforce IMDSv2 for production-grade security alignment
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Cloud-init passed via Base64 encoding to bootstrap Nginx, install nfs-common (the native Linux utility for mounting network drives), create a local target directory (/var/www/html), and connect the directory to the EFS volume and write it to /etc/fstab to persist reboots, all at launch
  # The database endpoint (aws_db_instance.asgard_db.address) is generated dynamically by AWS only after the RDS instance is created. To make sure your instances know how to talk to the database, we will update the cloud-init configuration to install a MySQL client and write the database connection details into the system environment files.
  user_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
      - nfs-common
      - mysql-client # Installs the MySQL command line client for database connectivity testing
    runcmd:
      # 1. Mount EFS Shared Storage
      - mkdir -p /var/www/html
      - [ mount, -t, nfs4, -o, "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport", "${aws_efs_file_system.asgard_shared_storage.id}.efs.${data.aws_region.current.name}.amazonaws.com:/", "/var/www/html" ]
      - echo "${aws_efs_file_system.asgard_shared_storage.id}.efs.${data.aws_region.current.name}.amazonaws.com:/ /var/www/html nfs4 _netdev,nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
      
      # 2. Inject Database Environment Variables for the Application
      - echo "DB_HOST=${aws_db_instance.asgard_db.address}" >> /etc/environment
      - echo "DB_USER=${aws_db_instance.asgard_db.username}" >> /etc/environment
      
      # 3. Finalize setup and enable Web Server
      - echo "<h1>Asgard 3-Tier Architecture Complete</h1>" > /var/www/html/index.html
      - [ systemctl, enable, --now, nginx ]
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "asgard-web-template"
  }
}

# Create the ASG. It manages the lifecycle of the instances (adding or removing based on load and healthchecks). It distributes them evenly across your three public subnets (PUB-A, PUB-B, PUB-C) and binds them directly to the ALB's target group.
resource "aws_autoscaling_group" "asgard_asg" {
  name_prefix         = "asgard-asg-"
  desired_capacity    = 3
  max_size            = 6
  min_size            = 1
  
  # Deploy across all three public subnets/Availability Zones
  vpc_zone_identifier = [
    aws_subnet.asgard_subnets["sn-web-A"].id, 
    aws_subnet.asgard_subnets["sn-web-B"].id, 
    aws_subnet.asgard_subnets["sn-web-C"].id
  ]

  # Links the ASG directly to your load balancer target group
  target_group_arns = [aws_lb_target_group.asgard_web_tg.arn]

  # CRITICAL: Changes health checking from EC2 (pinging hypervisor) to ELB (pinging port 80)
  health_check_type         = "ELB"
  health_check_grace_period = 300 # Gives cloud-init 5 minutes to install Nginx before checking

  launch_template {
    id      = aws_launch_template.asgard_web_template.id
    version = "$Latest"
  }

  # CRITICAL: Keeps everything building in orderly architectural sequence. Prevents instances from booting before storage network interfaces and databases are online
  depends_on = [
    aws_efs_mount_target.mount_target_a,
    aws_efs_mount_target.mount_target_b,
    aws_efs_mount_target.mount_target_c,
    aws_db_instance.asgard_db
  ]

  # Automatically tags instances launched by this group
  tag {
    key                 = "Name"
    value               = "asgard-web-node"
    propagate_at_launch = true
  }
}


# Create an EFS file system in the private App tier and mount it across the ASG instances as a shared file system for data persistence. This is a common pattern for stateful applications in an ASG. 
# Create Data Source for Current Region to keep your mount strings fully dynamic and prevent hardcoding
data "aws_region" "current" {}

# Create EFS Security Group. 
# The EFS mount targets need a firewall rule that permits incoming NFS traffic strictly from your web tier instances.
resource "aws_security_group" "asgard_efs_sg" {
  name        = "asgard-efs-sg"
  description = "Allow NFS traffic from ASG instances"
  vpc_id      = aws_vpc.asgard_vpc_1.id

  # Inbound: Allow NFS (Port 2049) ONLY from the EC2 Instance Security Group
  ingress {
    description     = "NFS from ASG web tier"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.asgard_instance_sg.id]
  }

  # Outbound: Standard tracking
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asgard-efs-sg"
  }
}

# Create the EFS File System & Multi-AZ Mount Targets
# This block creates the storage volume and anchors a network endpoint into each of your 3 private subnets.
# The core elastic file system resource
resource "aws_efs_file_system" "asgard_shared_storage" {
  creation_token = "asgard-wp-media"
  encrypted      = true

  tags = {
    Name = "AsgardSharedStorage"
  }
}

# Mount Target for Private App Tier Subnet 1 (AZ-A)
resource "aws_efs_mount_target" "mount_target_a" {
  file_system_id  = aws_efs_file_system.asgard_shared_storage.id
  subnet_id       = aws_subnet.asgard_subnets["sn-app-A"].id
  security_groups = [aws_security_group.asgard_efs_sg.id]
}

# Mount Target for Private App Tier Subnet 2 (AZ-B)
resource "aws_efs_mount_target" "mount_target_b" {
  file_system_id  = aws_efs_file_system.asgard_shared_storage.id
  subnet_id       = aws_subnet.asgard_subnets["sn-app-B"].id
  security_groups = [aws_security_group.asgard_efs_sg.id]
}

# Mount Target for Private App Tier Subnet 3 (AZ-C)
resource "aws_efs_mount_target" "mount_target_c" {
  file_system_id  = aws_efs_file_system.asgard_shared_storage.id
  subnet_id       = aws_subnet.asgard_subnets["sn-app-C"].id
  security_groups = [aws_security_group.asgard_efs_sg.id]
}


# Create RDS Instances
# Create Subnet Group with 3 subnets (one in each AZ) for high availability
resource "aws_db_subnet_group" "asgard_db_group" {
  name       = "asgard-cuisines-subnet-group"
  subnet_ids = [
    aws_subnet.asgard_subnets["sn-db-A"].id, 
    aws_subnet.asgard_subnets["sn-db-B"].id, 
    aws_subnet.asgard_subnets["sn-db-C"].id
  ]

  tags = {
    Name = "AsgardCuisinesDBSubnetGroup"
  }
}

# Create Security Group for the RDS
resource "aws_security_group" "rds_sg" {
  name        = "asgard-rds-sg"
  description = "Allow MySQL traffic from App/Web tier only"
  vpc_id      = aws_vpc.asgard_vpc_1.id

  # Allow inbound traffic to MySQL port from the App Server's CIDR (or Security Group in a real setup)
  ingress {
    description     = "MySQL access from ASG instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    # This creates the secure trust boundary between the tiers
    security_groups = [aws_security_group.asgard_instance_sg.id]
  }

  # Allow all outbound traffic (or restrict as needed)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asgard-rds-sg"
  }
}

# Create the RDS database
resource "aws_db_instance" "asgard_db" {
  identifier           = "asgardcuisines"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage     = 20
  
  # Credentials
  username             = "asgard"
  password             = "ekwu5555"
  
  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.asgard_db_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # Standard for backend database safety

  # Storage Settings
  max_allocated_storage = 0 # Disables storage autoscaling as requested
  
  # Final Housekeeping
  skip_final_snapshot    = true # Use only for labs; set to false in production
  
  tags = {
    Project = "AsgardCuisines"
  }
}

