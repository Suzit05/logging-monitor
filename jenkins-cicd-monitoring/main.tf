provider "aws" {
  region = "eu-north-1"
}

#s3 for logs

resource "aws_s3_bucket" "jenkins_logs" {
  bucket = "jenkins-cicd-logs-05"
  tags = {
    Name = "jenkins_logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_encrypt" {
  bucket = aws_s3_bucket.jenkins_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


#IAM ROLE

resource "aws_iam_role" "log_iam_role" {
  name = "jenkins-s3-access-role"

 assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "ec2.amazonaws.com"
                }
            },
        ]
    })
}

resource "aws_iam_role_policy_attachment" "log_iam_policy" {
  role = aws_iam_role.log_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "log_profile" {
  role = aws_iam_role.log_iam_role.name
  name = "jenkins-instance-profile"
}

#security group

resource "aws_security_group" "jenkins_sg" {
  name = "jenkins-sg"
  description = "security group for jenkins server"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#key pair 

resource "aws_key_pair" "log_key" {
  key_name = "jenkins-cicd-key"
  public_key = file("/mnt/c/Users/sujee/.ssh/id_rsa.pub")
}


# ec2 instance

resource "aws_instance" "jenkins_cicd_instance" {
  instance_type = "t3.micro"
  ami = "ami-073130f74f5ffb161"
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  
  iam_instance_profile = aws_iam_instance_profile.log_profile.name
  key_name = aws_key_pair.log_key.key_name  


  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y

              sudo apt install openjdk-11-jdk -y
              sudo apt install amazon-cloudwatch-agent -y

              wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
              sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
              sudo apt update -y
              sudo apt install jenkins -y
              sudo systemctl start jenkins
              sudo systemctl enable jenkins
              EOF

  tags = {
    Name = "Jenkins-server"
  }


}

#cloudwatch log group,stream, filter and metrics alarm

resource "aws_cloudwatch_log_group" "jekins_log_group" {
  name = "/aws/jenkins/logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "jenkins_log_stream" {
  name = "jenkins-log-stream"
  log_group_name = aws_cloudwatch_log_group.jekins_log_group.name
}

resource "aws_cloudwatch_log_metric_filter" "error_filter" {
  name = "JenkinsErrorFilter"
  log_group_name = aws_cloudwatch_log_group.jekins_log_group.name
  pattern = "ERROR"

  metric_transformation {
    name = "JenkinsErrorMetric"
    namespace = "JenkinsMetrics"
    value = "1"
  }
}


resource "aws_cloudwatch_metric_alarm" "jenkins_alarm" {
  alarm_name          = "HighJenkinsErrors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name = "JenkinsErrorMetric"
  namespace   = "JenkinsMetrics"

  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Trigger if Jenkins logs show too many errors"
  actions_enabled     = true
  alarm_actions       = [] # You can attach SNS topics here
}


#output 


output "jenkins_url" {
  
  description = "url to access jenkins server"
  value = "http://${aws_instance.jenkins_cicd_instance.public_ip}:8080"
}

