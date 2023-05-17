provider "aws" {
  region = "us-east-1"
}

# Створюємо VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

# Створюємо публічну і приватну підмережі
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "main-route-table"
  }
}

# Додаємо маршрутизацію між публічною і приватною підмережами
resource "aws_route_table_association" "public" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id = aws_subnet.private.id
  route_table_id = aws_route_table.main.id
}

# Створюємо інтернет-шлюз
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Створюємо security group для публічних і приватних EC2 серверів
resource "aws_security_group" "public" {
  name_prefix = "public-sg-"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private" {
  name_prefix = "private-sg-"
  vpc_id = aws_vpc.main.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 в публічній підмережі
resource "aws_instance" "public" {
  ami = "ami-0c55b159cbfafe1f0" # Ubuntu 18.04 LTS
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.public.id]

  key_name = "my-key"

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host = self.public_ip
  }

  user_data = <<EOF
              #!/bin/bash
              # Install Docker
              sudo apt-get update
              sudo apt-get install -y docker.io

              # Start Prometheus Stack
              sudo docker run -d --name prometheus -p 9090:9090 prom/prometheus

              # Install Node Exporter
              sudo docker run -d --name node-exporter -p 9100:9100 \
                -v "/proc:/host/proc" -v "/sys:/host/sys" \
                -v "/:/rootfs" \
                --net="host" \
                quay.io/prometheus/node-exporter \
                --path.procfs /host/proc \
                --path.sysfs /host/sys \
                --collector.filesystem.ignored-mount-points "^/(sys|proc|dev|host|etc)($|/)"

              # Install cAdvisor Exporter
              sudo docker run -d --name cadvisor-exporter -p 8080:8080 \
                --link node-exporter:node-exporter \
                --net="host" \
                google/cadvisor:v0.36.0 \
                -prometheus_endpoint http://node-exporter:9100/metrics
              EOF

  provisioner "remote-exec" {
    inline = [
      "sudo docker ps" # Check if Docker is running
    ]
  }

  tags = {
    Name = "public-ec2"
  }
}
# EC2 в приватній підмережі
resource "aws_instance" "private" {
  ami = "ami-0c55b159cbfafe1f0" # Ubuntu 18.04 LTS
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private.id]

  key_name = "my-key"

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host = self.private_ip
  }

  user_data = <<EOF
              #!/bin/bash
              # Install Docker
              sudo apt-get update
              sudo apt-get install -y docker.io

              # Install Node Exporter
              sudo docker run -d --name node-exporter -p 9100:9100 \
                -v "/proc:/host/proc" -v "/sys:/host/sys" \
                -v "/:/rootfs" \
                --net="host" \
                quay.io/prometheus/node-exporter \
                --path.procfs /host/proc \
                --path.sysfs /host/sys \
                --collector.filesystem.ignored-mount-points "^/(sys|proc|dev|host|etc)($|/)"

              # Install cAdvisor Exporter
              sudo docker run -d --name cadvisor-exporter -p 8080:8080 \
                --link node-exporter:node-exporter \
                --net="host" \
                google/cadvisor:v0.36.0 \
                -prometheus_endpoint http://node-exporter:9100/metrics
              EOF

  provisioner "remote-exec" {
    inline = [
      "sudo docker ps" # Check if Docker is running
    ]
  }

  tags = {
    Name = "private-ec2"
  }
}