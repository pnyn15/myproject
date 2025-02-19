terraform {
  required_providers {
    aws = {
      source= "hashicorp/aws"
    }
  }  
}

provider "aws"{
  region = "us-east-2"
}

resource "aws_vpc" "projectvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "projectvpc"
  }
}

resource "aws_subnet" "public-subnet-1" {
  vpc_id = aws_vpc.projectvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public-subnet-1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id = aws_vpc.projectvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  map_public_ip_on_launch = true
  depends_on = [ aws_subnet.public-subnet-1 ]
  tags = {
    Name = "Public-subnet-2"
  }
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id = aws_vpc.projectvpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-2a"
  depends_on = [ aws_subnet.public-subnet-2 ]
  tags = {
    Name = "Private-subnet-1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id = aws_vpc.projectvpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-2b"
  depends_on = [ aws_subnet.private-subnet-1 ]
  tags = {
    Name = "Private-subnet-2"
  }
}

resource "aws_internet_gateway" "project-igw" {
  vpc_id = aws_vpc.projectvpc.id
  depends_on = [ aws_vpc.projectvpc ]
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.projectvpc.id
  depends_on = [ aws_subnet.public-subnet-2 ]
}

resource "aws_route" "public-internet-access" {
  route_table_id = aws_route_table.public-route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.project-igw.id
  depends_on = [ aws_route_table.public-route-table ]
}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.projectvpc.id
  depends_on = [ aws_route.public-internet-access]
}

resource "aws_eip" "nat" {
  domain = "vpc"
   tags = {
      Name = "nat-eip"
   }
}

resource "aws_nat_gateway" "project-NAT" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public-subnet-1.id
  tags = {
    Name = "Project-NAT"
  }
}

resource "aws_route_table_association" "public-subnet-associataion" {
  subnet_id = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "public-subnet2-associataion" {
  subnet_id = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "private-subnet-associataion" {
  subnet_id = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private-route-table.id
}

resource "aws_route_table_association" "private-subnet1-associataion" {
  subnet_id = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.private-route-table.id
}

resource "aws_instance" "example" {
  ami = var.instance_ami
  instance_type = var.instance_type
  key_name = var.key_name
  subnet_id = aws_subnet.public-subnet-1.id
  tags = {
    Name = "Bastion-EC2"
  }
}

resource "aws_instance" "example1" {
  ami = var.instance_ami
  instance_type = var.instance_type
  key_name = var.key_name
  subnet_id = aws_subnet.private-subnet-1.id
  tags = {
    Name = "Private-EC2"
  }
}

resource "aws_lb" "alb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
}

resource "aws_lb_target_group" "my-TG" {
  name     = "my-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.projectvpc.id
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my-TG.arn
  }
}

resource "aws_launch_template" "my_launch" {
  name          = "my-launch"
  instance_type = var.instance_type
  key_name      = var.key_name
  image_id      = var.instance_ami
}

resource "aws_autoscaling_group" "myauto" {
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]

  launch_template {
    id      = aws_launch_template.my_launch.id
    version = "$Latest"
  }
}
resource "aws_db_instance" "myrds" {
  identifier             = "projectrds"
  instance_class         = var.db_instance_class
  engine                 = var.engine
  engine_version         = var.engine_version
  allocated_storage      = var.allocated_storage
  username               = var.username
  password               = var.password
  db_name                = var.db_name
  skip_final_snapshot = true
  multi_az               = false
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.id
  backup_retention_period = 7
   tags = {
    Name       = "yashdb"
    Created_BY = "yash"
  }
}


resource "aws_db_instance" "rdsreplica1" {
  replicate_source_db = aws_db_instance.myrds.identifier
  instance_class      = var.db_instance_class
  skip_final_snapshot = true
  publicly_accessible = false
  depends_on = [aws_db_instance.myrds]
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]
}

resource "aws_security_group" "ALBSG" {
  name        = "yash-alb-sg"
  description = "External load balancer security group"
  vpc_id      = aws_vpc.projectvpc.id
  tags = {
    Name       = "yash-SG"
    Created_BY = "yash"
    Project    = "terraform"
  }

  # Inbound rules
  ingress {
    description = "Allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from anywhere
  }

  ingress {
    description = "Allow Tomcat"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from anywhere
  }

  # Outbound rule allowing all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "BastionSG" {
  name        = "yash-Bastion-SG"
  description = "web tier security group"
  vpc_id      = aws_vpc.projectvpc.id

  ingress {
    description = "Allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from anywhere
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name       = "yash-Bastion-SG"
    Created_BY = "yash"
    Project    = "terraform"
  }
}




resource "aws_security_group" "db-sg" {
  vpc_id = aws_vpc.projectvpc.id
  name   = "db-sg"
  tags = {
    Name = "db-sg"
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/24", "10.0.4.0/24"]
    # Allow traffic from private subnets
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "app-tier" {
    name = "app-tier-SG"
    description = "private-instance-sg"
    vpc_id = aws_vpc.projectvpc.id
    tags = {
      Name = "app-tier-SG"
    }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = [aws_security_group.BastionSG.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ALBSG.id] # Only Bastion can access
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "db_name" {
    description = "db name for ec2-instance"
    default = "shopping"
    
}

variable "username" {
    description = "username for db"
    default = "admin"
}

variable "password" {
    description = "password for db"
    default = "root12345"
}

variable "db_instance_class" {
  description = "instance-class"
  default = "db.t3.micro"
}


variable "engine" {
    default = "mysql"
}


variable "engine_version" {
    default = "8.0"
}

variable "allocated_storage" {
    default = 20

}
variable "instance_ami" {
    description = "ami for all ec2-instances"
    default = "ami-08c65a248ce71fb2d"
    
}

variable "instance_type" {
    description = "instance type for ec2"
    default = "t2.micro"
    
}

variable "key_name" {
    description = "keyname for ec2"
    default = "ohio"
}
