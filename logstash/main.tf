provider "aws" {
  region = "eu-north-1"
}

resource "aws_key_pair" "mykey" {
  key_name = "mydeployer-key"
  public_key = file("/mnt/c/Users/sujee/.ssh/id_rsa.pub")
}

resource "aws_security_group" "logstash_sg" {
  name = "logstash_sg"
  description = "Allow SSH and logstash ports"

  ingress  {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

}
  ingress  {
    from_port = 5044  #logstash
    to_port = 5044
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

}
  ingress  {
    from_port = 5601  #kibana
    to_port = 5601
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

}
  egress  {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]

}
}

resource "aws_instance" "logstash_server" {
  instance_type = "t3.micro"
  key_name = aws_key_pair.mykey.key_name
  security_groups = [aws_security_group.logstash_sg.name]
  ami = "ami-04233b5aecce09244"
  tags = {
    Name = "logstash-server"
  }
  user_data = <<-EOF
              #!/bin/bash
              set -e

              
              yum udate -y
              yum install -y java-11-openjdk
              rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

              cat <<EOT > /etc/yum.repos.d/logstash.repo
              [logstash-8.x]
              name=Elastic repository for 8.x packages
              baseurl=https://artifacts.elastic.co/packages/8.x/yum
              gpgcheck=1
              gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
              enabled=1
              autorefresh=1
              type=rpm-md
              EOT

              yum install -y logstash

              # Create Logstash pipeline config
              cat <<EOT > /etc/logstash/conf.d/logstash.conf
              input {
                beats {
                  port => 5044
                }
              }

              output {
                stdout {
                  codec => rubydebug
                }
              }
              EOT

              # Set permissions
              chown logstash:logstash /etc/logstash/conf.d/logstash.conf

              # Enable and start Logstash
              systemctl daemon-reexec
              systemctl enable logstash
              systemctl start logstash
              EOF
              }

output "public_ip" {
  value = aws_instance.logstash_server.public_ip
}

#logstash - has no web ui , u cannot access it through web browser