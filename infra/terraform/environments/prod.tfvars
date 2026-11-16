aws_region             = "us-east-2"
project_name           = "aws-ecs-ephemeral-environments"
ecr_repository_name    = "app"
environment            = "prod"
is_ephemeral           = false
create_shared_resources = false
vpc_cidr               = "10.30.0.0/16"
task_cpu               = 512
task_memory            = 1024
desired_count          = 2
log_retention_days     = 90

